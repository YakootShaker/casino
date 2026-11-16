# Stage 6: Comprehension Test Report

**Target Document:** `docs/designs/quiz_buzzer_2device_architecture.md`  
**Reviewer:** Naive Reader (`egm-comprehension`)  
**Standard:** Comprehension & Self-Containment (FeatureRange: lines 1..805, DetailedRange: lines 806..1042)

---

### Feature Spec Paraphrase (What the system does and why)
The system is a two-device trivia buzzer platform designed to eliminate network latency bias and setup friction by consolidating three competing players onto a single shared landscape tablet or phone, while a separate device acts as the referee's cockpit for question delivery and manual answer scoring. Game rooms are paired via a 6-digit PIN and backed by Supabase Postgres, where a server-authoritative 10-second turn deadline prevents client timer manipulation or background freezing. All question media (text, image, audio) and answers are isolated to the referee's screen, while the players' device uses zero-latency local hardware touch arbitration to immediately lock out opposing columns before committing the buzz to the server. When a player answers incorrectly or times out, a steal mechanic penalizes that player by one point and reopens the buzzer with a fresh 10-second countdown for the remaining unlocked players until someone answers correctly or all three fail.

### Implementation Plan Paraphrase (How the system will be built)
The implementation will be built with Flutter on the frontend (using Riverpod for state management, GoRouter for routing, raw Listener widgets for touch arbitration, and just_audio for sound) and Supabase on the backend (PostgreSQL tables, Row-Level Security, and Realtime WebSocket changes). All state transitions and scoring mutations are executed through transactional PL/pgSQL stored procedures (`create_room`, `join_room`, `buzz`, `judge_mark`, `expire_turn`, `adjust_score`, and `skip_question`) guarded by `FOR UPDATE` row locks, with client clock drift corrected against server HTTP headers. Anonymous authentication UIDs and SHA-256 hashed session tokens stored in platform-native secure storage govern room access and deterministic role-locked reconnection. Automated verification will combine Flutter unit, widget, and mock integration tests covering 80% of business logic, paired with physical two-device manual testing of multi-touch collisions, steal loops, and background recovery.

---

### Comprehension Test Findings

#### 1. 🔴 Blocker: Missing `start_game` RPC and Lifecycle Transition from `lobby`
* **Affected Scope:** Lines 77–82, 162–177, 274–664, 834–838, 915–919
* **Finding:** In CUJ 2 (line 77), the room begins in `lobby`, and the Referee taps "Start Game", causing the server to transition `phase` to `question_active` and draw an initial question. However, no `start_game` RPC exists anywhere in the PL/pgSQL function definitions, the repository (`game_repository.dart`), or the migration plan. Direct client updates on `game_states` are strictly forbidden by RLS. As specified, there is no API or mechanism to transition a room out of `lobby` or select the initial question. The application cannot start a match.
* **Remediation:** Implement an authoritative `start_game(p_room_id, p_category)` RPC that sets `phase = 'question_active'` and selects the first question.

#### 2. 🔴 Blocker: Inverted Sign Error in Server Clock-Offset Countdown Formula
* **Affected Scope:** Section 5.2, Lines 674–680
* **Finding:** The reactive countdown formula is defined as:
  $$t_{\text{remaining}} = \max\left(0, \left(T_{\text{buzz\_expires\_at}} + \Delta_{\text{clock}}\right) - T_{\text{local}}\right)$$
  where $\Delta_{\text{clock}} = T_{\text{server}} - T_{\text{local}}$.
  This formula contains an inverted sign for $\Delta_{\text{clock}}$. If a client device clock is 5 seconds slow ($T_{\text{local}} = 12:00:05$, $T_{\text{server}} = 12:00:10$), $\Delta_{\text{clock}} = +5\text{s}$. If the server turn expires at $T_{\text{buzz\_expires\_at}} = 12:00:20$, the true remaining time is 10 seconds. However, the documented formula calculates $(12:00:20 + 5\text{s}) - 12:00:05 = 20\text{ seconds}$—doubling the local clock error. Conversely, if a client clock is fast, the timer truncates to 0 immediately upon buzzing.
* **Remediation:** Correct the formula to:
  $$t_{\text{remaining}} = \max\left(0, T_{\text{buzz\_expires\_at}} - \left(T_{\text{local}} + \Delta_{\text{clock}}\right)\right)$$

#### 3. 🔴 Blocker: Schema Violation in RLS Policy on `questions` Table
* **Affected Scope:** Section 6, Lines 207–218, 697–698, 839–843
* **Finding:** Line 697 states that RLS on the `questions` table allows reads where `auth.uid() = referee_uid`. However, the `questions` table schema (lines 207–218) contains no `referee_uid` column (it is a global bank; `referee_uid` resides in `rooms`). Applying this policy in PostgreSQL migration `20261115000002_create_quiz_buzzer_rls.sql` will fail with `ERROR: column "referee_uid" does not exist`.
* **Remediation:** Enforce question security via RPCs or join against `rooms`: `EXISTS (SELECT 1 FROM rooms WHERE referee_uid = auth.uid())`.

#### 4. 🟡 Major: Disconnected Realtime Subscriptions for Score Changes (`rooms` vs `game_states`)
* **Affected Scope:** Lines 199–204, 228–241, 600–630, 920–924
* **Finding:** `player_scores` and `player_names` reside exclusively in the `rooms` table, while `RealtimeService` only subscribes to Postgres Changes on `game_states`. When the Referee adjusts a score via `adjust_score` without triggering game over, only `rooms` is updated. `game_states` is untouched, `trg_state_version` does not fire, and `RealtimeService` receives no event. The scoreboard on both devices remains stale.
* **Remediation:** Move `player_scores` and `player_names` into `game_states` or merge `rooms` and `game_states`.

#### 5. 🟡 Major: Missing Caller Authorization Checks in `SECURITY DEFINER` RPCs
* **Affected Scope:** Section 4, Lines 380–411, 413–530, 600–630, 631–664
* **Finding:** All mutation RPCs are declared `SECURITY DEFINER`, bypassing standard RLS checks. However, none of the procedures validate `auth.uid()` against `rooms.referee_uid` or `rooms.console_uid`. Any client with knowledge of `room_id` can arbitrarily award points, skip questions, or trigger buzzes.
* **Remediation:** Add caller verification in each RPC:
  - `judge_mark`, `skip_question`, `adjust_score`, `start_game`: `IF auth.uid() <> v_room.referee_uid THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;`
  - `buzz`: `IF auth.uid() <> v_room.console_uid THEN RAISE EXCEPTION 'UNAUTHORIZED'; END IF;`

#### 6. 🟡 Major: Contradiction on Content Isolation vs. Image Trivia & `v_console_questions` View
* **Affected Scope:** Section 1, Lines 12–14, 37–38, 697–698, 841
* **Finding:** The document mandates that no question content is shown on the Players Console, and all text, images, and reference answers appear exclusively on the Referee device. If the Players Console cannot display question content, how do players see images for image trivia questions? Also, if the console never displays questions, why does line 698 specify a view `v_console_questions`?
* **Remediation:** Clarify how players view image questions (either Referee holds up their screen, or Players Console displays the question media while hiding reference answers/notes). Remove `v_console_questions` if the console never queries it.

#### 7. 🟡 Major: Unspecified Invoker for Normal Turn Expiration (`expire_turn`)
* **Affected Scope:** Lines 35, 52, 99–108, 532–550, 683–685, 932–936
* **Finding:** The document specifies that no server-side cron exists and details `expire_turn` calls during disconnection recovery (CUJ 4). However, during normal gameplay when the 10-second countdown elapses naturally without an answer, the specification never explicitly states which client (Referee, Players Console, or both) fires `expire_turn()`.
* **Remediation:** Explicitly specify that `countdownProvider` on both clients triggers `expire_turn()` upon hitting zero (idempotent guard resolves the race).

#### 8. 🟡 Major: Undefined Winner Assignment on Question Exhaustion
* **Affected Scope:** Lines 464–467, 500–502, 570–573, 646–649, 977–981
* **Finding:** In `judge_mark`, `expire_turn`, and `skip_question`, if questions run out (`v_new_q IS NULL`), the RPC sets `phase = 'game_over'`, but leaves `winner_player_index` as `NULL`. `GameOverDialog` expects a winner. There is no logic to determine the player with the highest score or handle ties upon question exhaustion.
* **Remediation:** In `game_over` transitions, determine `winner_player_index` by finding the index with the maximum score in `player_scores`.

#### 9. 🟢 Nit: Phantom State `judge_evaluating` in State Machine
* **Affected Scope:** Section 2, Lines 162–175, 179–180, 230–233
* **Finding:** The state machine diagram includes `judge_evaluating`, but the PostgreSQL check constraint strictly permits only `('lobby', 'question_active', 'buzzer_active', 'game_over')`.
* **Remediation:** Align check constraint and state diagram.

#### 10. 🟢 Nit: SQL Array Indexing Discrepancy in CUJ 5
* **Affected Scope:** Lines 115–116
* **Finding:** Line 116 states `player_scores[2] >= 10` for Player 3. In PostgreSQL, array indices are 1-based by default (`player_scores[3]`).
* **Remediation:** Update prose to clarify 1-based SQL array vs 0-based client indices.

#### 11. 🟢 Nit: Premature Orientation Lock in `main.dart`
* **Affected Scope:** Section 4, Lines 883–887
* **Finding:** The plan notes that `lib/main.dart` conditionally enforces landscape orientation. At app bootstrap, role is unknown.
* **Remediation:** Apply orientation lock inside `players_console_screen.dart` initState/dispose.
