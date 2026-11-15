# Stage 8: Intermediate Zoom Out Review Report

**Target Document:** `docs/designs/quiz_buzzer_2device_architecture.md`  
**Reference Inputs:** Stage 5 Report (`zoom_out_report.md`), Stage 6 Report (`comprehension_report.md`), Stage 7 Report (`critic_report.md`), Context Brief (`concepts_brief.md`)  
**Reviewer:** Skeptical Architect (`egm-zoom-out`)

---

## Executive Architectural Assessment

Stepping back from low-level syntax and DDL constraints to evaluate the macro architecture:

1. **The Core Thesis is Sound, but Misaligned with Real Gameplay Pacing:**
   The fundamental premise—eliminating network latency bias by anchoring three players to a single shared physical screen with local pointer arbitration (`Listener`) and a separate Referee cockpit—is the right solution for casual living-room trivia.
   However, the design treats a human-moderated living-room trivia game like an autonomous, machine-driven distributed transaction pipeline. By chaining question advancement directly to judgment, auto-docking player scores on client timer expiry, and immediately opening buzzers before media is buffered or clues are read aloud, the architecture creates severe gameplay friction and pacing collisions.

2. **Relational Over-Engineering Created False Concurrency Hazards:**
   The arbitrary split between `rooms` and `game_states` (two 1:1 tables created and destroyed together for an ephemeral 4-hour session) is the root cause of the reverse-order lock deadlocks (`40P01`), broken Realtime score synchronization, and redundant database operations. Unifying mutable game state—or collapsing the schema into a single `rooms` table—eliminates these issues by design without requiring fragile lock-ordering conventions.

3. **Security Theater & Premature Abstraction Must Be Purged:**
   Generating 32-byte raw hex tokens, hashing with `pgcrypto` SHA-256, storing credentials in Android Keystore / iOS Keychain via `flutter_secure_storage`, and constructing a sanitized `v_console_questions` view for a console that never requests trivia content is enterprise bloat for a casual living-room game. Standard Supabase anonymous authentication (`auth.uid()`) combined with local storage (`shared_preferences`) fulfills 100% of the security goals with zero Keystore corruption risk.

---

## 🔴 Blocker Findings (Architectural Risks & Flaws)

### 1. The Runaway Game Loop: Lack of Referee Pacing & Question Intermission
* **Affected Scope:** Section 1.2 (State Machine), Section 4.4 (`judge_mark`), Section 4.5 (`expire_turn`)
* **Finding:** In `judge_mark` and `expire_turn`, the server immediately draws the next question and sets `phase = 'question_active'`. The moment the Referee taps "Correct (+1)", the server immediately arms the buzzers for the *next* question before the Referee can announce the answer or read the next clue. A player touching the screen immediately buzzes in for a clue that has not been spoken or displayed.
* **Remediation:** Introduce an explicit intermission / pacing phase: `question_revealed` (or `round_summary`). After an answer is scored or question is exhausted, transition to `question_revealed` where the Referee sees the result and reference answer, and explicitly taps "Next Question" or "Open Buzzer" when ready to deliver the next clue.

### 2. Clue Delivery & Asset Buffering Race Against Buzzer Arming
* **Affected Scope:** Section 4.4, Section 5.1, Section 5.4
* **Finding:** The design couples question drawing directly with buzzer activation (`phase = 'question_active'`). When a question advances, Device 2 immediately unlocks all columns while Device 1 is still fetching question metadata, rendering images, or buffering audio clips over the network. Players on Device 2 can buzz in before the Referee's device has even rendered the image or buffered the audio.
* **Remediation:** Buzzers must NOT arm automatically on question selection. Buzzers must only transition to active when the Referee taps "Open Buzzer" after reading/displaying the prompt, or when audio playback initiates.

### 3. Client Auto-Penalty Overrides Human Verbal Adjudication
* **Affected Scope:** Section 4.5 (`expire_turn`), Section 5.3
* **Finding:** In verbal party trivia, players frequently start speaking at second 9.5 of a 10-second countdown. At second 10.01, Device 2's background timer triggers `expire_turn`, which automatically docks -1 point, locks the player, and clears the turn. At second 10.2, the Referee taps "Correct (+1)", which is rejected with `NOT_IN_BUZZER_ACTIVE`.
* **Remediation:** Remove automatic score deductions from `expire_turn`. When the 10-second countdown elapses, the client plays a timeout chime and flags `time_expired = true`. The Referee remains the sole human arbiter who taps "Incorrect / Timeout (-1)" or awards the point if the player answered in time.

### 4. Over-Normalized Two-Table Split (`rooms` vs `game_states`) Creates Deadlocks & Sync Failures
* **Affected Scope:** Section 3, Section 4
* **Finding:** The schema splits an ephemeral, 4-hour trivia match across two tables (`rooms` and `game_states`) in a 1:1 relationship with cascading deletes. This artificial separation caused deadlock error `40P01` and broken Realtime updates.
* **Remediation:** Consolidate all mutable session state into a single table (either merge `game_states` columns into `rooms`, or move `player_scores` and `player_names` into `game_states` so gameplay RPCs never touch or lock `rooms`). Having gameplay RPCs mutate exactly one table eliminates deadlocks by definition and guarantees unified Realtime broadcasts.

---

## 🟡 Major Findings (Over-Engineering & YAGNI Violations)

### 5. YAGNI & Security Theater: Keystore Storage & Hashed Tokens
* **Affected Scope:** Section 1.3, Section 3, Section 4.1–4.2, Section 5.3, Section 8.3
* **Finding:** Mandating 256-bit cryptographically random tokens, SHA-256 database hashing (`referee_token_hash`, `console_token_hash`), and `flutter_secure_storage` adds fragile dependencies with zero user value. Supabase Anonymous Auth already generates a unique, cryptographically signed `auth.uid()`.
* **Remediation:** Eliminate custom 32-byte token generation, `pgcrypto` hashing, and `flutter_secure_storage`. Rely on Supabase's built-in anonymous `auth.uid()` bound to `rooms.referee_uid` and `rooms.console_uid`, storing `room_id` and `role` in `shared_preferences`.

### 6. Ghost Artifact: View `v_console_questions` Violates Content Isolation
* **Affected Scope:** Section 6, Section 8.2
* **Finding:** The Players Console shows zero question content—it is strictly a 3-column buzzer panel. Yet the design specifies creating a PostgreSQL View (`v_console_questions`) and RLS policies to sanitize reference answers for the console.
* **Remediation:** Remove `v_console_questions` completely. Restrict `questions` SELECT permission strictly to `auth.uid() = referee_uid`.

### 7. Over-Engineered Clock-Offset Header Parsing
* **Affected Scope:** Section 5.2, Section 8.3 (`clock_offset_service.dart`)
* **Finding:** Parsing HTTP `Date` headers with regex to compute $\Delta_{\text{clock}}$ introduces jitter and sign-inversion bugs. On reconnect, the client only needs the remaining time from the server.
* **Remediation:** Delete `clock_offset_service.dart`. Let the server RPC return remaining duration on reconnect, and run visual countdowns locally during active turns with a 500ms server tolerance buffer.

### 8. Steal Reopen Pacing & Instant False Buzzes
* **Affected Scope:** Section 4.4, Section 5.1
* **Finding:** When Player 0 answers incorrectly, `judge_mark` immediately sets `phase = 'question_active'`. In the room, Player 1 is already mashing their column and steals before Player 2 hears the Referee declare the answer wrong.
* **Remediation:** Provide a "Reopen Buzzer" button on the Referee screen or apply a 1.5-second arming delay before columns accept input.

---

## 🟢 Nit Findings

### 9. Question Selection Helper Extraction
* **Finding:** Extract the repeated 5-line SQL block for question selection into a private helper function `_draw_random_question(p_room_id UUID, p_categories TEXT[])`.

### 10. Image Trivia Presentation Clarification
* **Finding:** Explicitly document the physical interaction model: the Referee presents image clues to the room (holding up the screen or mirroring to a TV). The Players Console remains an unadorned buzzer interface.
