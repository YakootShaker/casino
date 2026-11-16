# Stage 5: Initial Zoom Out Review Report

**Target Document:** `docs/designs/quiz_buzzer_2device_architecture.md`  
**Reference Document:** `concepts_brief.md`  
**Reviewers:** Skeptical Architect (`egm-zoom-out`), Inventive Catalyst (`egm-inventive-catalyst`)

---

## Executive Summary

The Initial Zoom Out evaluation affirms the central thesis of the 2-device topology (eliminating network round-trip discrepancies by centralizing player touch arbitration on a single physical screen). However, the architecture suffers from critical lifecycle oversights, distributed race conditions between human adjudication and client timer pumps, premature security theater, and asset buffering race conditions.

---

## 🔴 Blocker Findings

### 1. Missing `start_game` / `next_question` Lifecycle RPC
* **Reviewer:** `egm-zoom-out`
* **Affected Scope:** Section 2 (Lines 161–182), Section 4 (Lines 274–664), CUJ 2 (Lines 75–88)
* **Finding:** `create_room` initializes the room in `phase = 'lobby'`. `join_room` assigns the console UID. None of the remaining RPCs (`buzz`, `judge_mark`, `expire_turn`, `skip_question`) can transition from `lobby` to `question_active`. There is no mechanism to start the match or fetch the initial question. Furthermore, Decision D4 specifies that the Referee selects the category, yet existing RPCs automatically draw questions via `ORDER BY random()`, bypassing the Referee.
* **Remediation:** Introduce an authoritative `start_game(p_room_id, p_category)` and `next_question(p_room_id, p_category)` RPC, giving the Referee direct category control.

### 2. Split Game State Breaks Realtime Reactive Score Updates
* **Reviewer:** `egm-zoom-out`
* **Affected Scope:** Section 3 (Lines 191–241), Section 4.4 & 4.6 (Lines 438–445, 612–617), Section 5 (Lines 920–931)
* **Finding:** The architecture specifies a single Supabase Realtime channel listening exclusively to `game_states`. However, `player_scores` is stored in the `rooms` table, while turn status is in `game_states`. When `judge_mark` or `adjust_score` updates scores, the Realtime listener on `game_states` receives no notification. Score updates are invisible to both the Referee and Players Console unless an expensive manual REST poll occurs.
* **Remediation:** Move `player_scores` directly into `game_states` (or merge `rooms` and `game_states` into a unified entity) so every state broadcast delivers current scores.

### 3. Client-Driven Auto-Penalty Overrides Live Human Adjudication
* **Reviewers:** `egm-zoom-out`, `egm-inventive-catalyst`
* **Affected Scope:** Section 4.5 (`expire_turn`), Section 5.3 (Lines 681–686), CUJ 4 (Lines 99–108)
* **Finding:** In `expire_turn`, when the 10-second timer elapses on any client, that client calls `expire_turn`, which immediately docks −1 point from the player, locks them out, and advances the question. In verbal party trivia, players often finish speaking at second 9.9, and the Referee taps "Correct (+1)" at second 10.2. The client timer auto-fires, applies a -1 penalty, locks the player, and when the Referee's `judge_mark('correct')` arrives, it is rejected with `NOT_IN_BUZZER_ACTIVE`. The player suffers an unfair 2-point penalty swing (+1 lost, -1 deducted).
* **Remediation:** Decouple timer expiration from score deductions. When `buzz_expires_at` elapses, transition to `judge_evaluating` or flag `time_expired = true`. The Referee must confirm the timeout or evaluate the verbal answer.

### 4. Sub-Second Server Turn Expiry Gated by Coarse 1-Second HTTP Date Header
* **Reviewer:** `egm-inventive-catalyst`
* **Affected Scope:** Section 4.5 (`expire_turn`), Section 5.2 (`Clock-Offset Correction`), Section 5.3
* **Finding:** The design relies on a client-side clock offset ($\Delta_{\text{clock}}$) derived from the HTTP `Date` header returned by Supabase. Standard HTTP `Date` headers have only 1-second resolution (no milliseconds), introducing up to $\pm 1000\text{ms}$ of sampling error. If a client's countdown hits zero and fires `expire_turn` while running slightly ahead of the server, Postgres strictly rejects the call (`buzz_expires_at > clock_timestamp()`). Because the stream emits zero once without retries, the game permanently deadlocks in `buzzer_active`.
* **Remediation:** Replace HTTP `Date` parsing with a lightweight server timestamp probe (`SELECT clock_timestamp()`) during pairing. Provide a 250ms tolerance cushion in `expire_turn` or a 150ms client retry on `transitioned: false`.

### 5. Content Delivery & Asset Buffering Race Condition Against Buzzer Arming
* **Reviewer:** `egm-inventive-catalyst`
* **Affected Scope:** Section 1 (Architecture), Section 4.4, Section 4.7, Section 5.4
* **Finding:** When a question advances, the server updates `phase = 'question_active'` and `current_question_id = v_new_q`. Both devices receive the update concurrently. The Players Console immediately unlocks all buzzers. However, the Referee device must first receive the Realtime event, extract `current_question_id`, fetch question media via REST, and buffer the audio clip with `just_audio`. Players on the console can buzz before the Referee's device has even rendered the clue or loaded the audio.
* **Remediation:** Segment the question cycle into `question_revealed` (Referee reads/previews; buzzers armed with a visual indicator) and `buzzer_open` (armed when Referee initiates or audio buffer completes). Inline new question metadata directly in the `judge_mark` / `next_question` RPC response.

---

## 🟡 Major Findings

### 6. Phantom Phase `judge_evaluating` Violates Database Check Constraint
* **Reviewer:** `egm-zoom-out`
* **Affected Scope:** Section 2 (Lines 161–182) vs. Section 3 (Line 232)
* **Finding:** The state machine diagram (Lines 165–173) defines `[judge_evaluating]` as a formal transition state, but the DDL check constraint specifies `CHECK (phase IN ('lobby', 'question_active', 'buzzer_active', 'game_over'))`. Transitioning to `judge_evaluating` triggers a database runtime constraint failure.
* **Remediation:** Add `'judge_evaluating'` to the database `phase` check constraint.

### 7. YAGNI & Security Theater: Cryptographic Role Tokens & Keystore Storage
* **Reviewer:** `egm-zoom-out`
* **Affected Scope:** Section 3 (Lines 191–204), Section 4.1–4.2, Section 6, Section 8.3
* **Finding:** Mandating 256-bit cryptographically random tokens, SHA-256 Postgres hashing (`referee_token_hash`, `console_token_hash`), iOS Keychain (`synchronizable: false`), and Android Keystore (`EncryptedSharedPreferences`) for a casual living-room party game adds high friction. If app data is cleared on Android, the room becomes permanently unjoinable for 4 hours.
* **Remediation:** Simplify session persistence. The 6-digit numeric PIN paired with client-stored room ID and role in `shared_preferences` is sufficient and immune to Keystore corruption.

### 8. Speculative Abstraction: Database View `v_console_questions`
* **Reviewer:** `egm-zoom-out`
* **Affected Scope:** Section 6 (Lines 698–699), Section 8.2
* **Finding:** The design specifies creating a Postgres View (`v_console_questions`) and RLS rules to sanitize question data so the Players Console cannot inspect `reference_answer`. However, the Players Console never queries questions. Creating views and RLS policies for a client that never requests that data is unnecessary complexity.
* **Remediation:** Remove `v_console_questions`. Restrict `questions` SELECT strictly to `auth.uid() = referee_uid`.

### 9. Optimistic Auditory & Haptic Klaxon on Raw Pointer Down (False Positive Disturbance)
* **Reviewer:** `egm-inventive-catalyst`
* **Affected Scope:** Section 5.1 (`Touch Arbitration Engine`)
* **Finding:** Firing `HapticFeedback.heavyImpact()` and playing `buzz.mp3` immediately on `PointerDownEvent` before server RPC confirmation creates loud false alarms if the buzz is rejected (wrong phase, player already locked, or opponent tapped 5ms earlier).
* **Remediation:** Implement two-tier feedback: immediate subtle tactile tick (`selectionClick()`) and localized visual ripple on touch, followed by full klaxon and heavy vibration only upon server confirmation.

### 10. Contiguous Boundary Collision on Shared Landscape Surface
* **Reviewer:** `egm-inventive-catalyst`
* **Affected Scope:** Section 5.1, Section 7.6, Section 5.5
* **Finding:** Three columns placed directly adjacent across a mobile landscape screen (~50mm per player) produce boundary collisions and palm resting conflicts. If a finger is already resting on the screen when the buzzer arms, `onPointerDown` will not fire.
* **Remediation:** Add 12–16dp neutral dead-zone gutters between columns, and require pointer lift-and-press (`onPointerUp` then `onPointerDown`) if a finger was resting prior to buzzer arming.

---

## 🟢 Nit Findings

### 11. Acoustic Spatial Stereo Panning
* **Reviewer:** `egm-inventive-catalyst`
* **Finding:** Pan Player 0 hard-left, Player 1 center, and Player 2 hard-right, giving distinct tonal signatures so players and Referee perceive who buzzed without looking down at the screen.

### 12. Screen Sleep Protection (`wakelock_plus`)
* **Reviewer:** `egm-inventive-catalyst`
* **Finding:** Add `wakelock_plus` to prevent OS screen sleep during prolonged question reading.

### 13. Monotonic Snapshot Fencing vs. Speculative REST Refetches
* **Reviewer:** `egm-inventive-catalyst`
* **Finding:** `game_states` is a full snapshot, not an incremental delta. Treat `state_version` purely as an out-of-order rejection fence (`state_version > local_version`) rather than triggering redundant REST refetches on version gaps.

### 14. SQL Duplication in Question Selection
* **Reviewer:** `egm-zoom-out`
* **Finding:** Extract repeated `ORDER BY random() LIMIT 1` question selection into a private helper function.
