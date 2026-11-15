# Consolidated Review Report: Quiz Buzzer (2-Device Architecture)

**Target Document:** [`docs/designs/quiz_buzzer_2device_architecture.md`](file:///d:/coding/casino/docs/designs/quiz_buzzer_2device_architecture.md)  
**Context:** [`concepts_brief.md`](file:///d:/coding/casino/concepts_brief.md)  
**Execution Mode:** Uninterrupted Full Flow (Stages 5, 6, 7, 8, and 9)  
**Reviewers:** Skeptical Architect, Inventive Catalyst, Naive Reader, Design Critic, Structural Validator, Technical Copy Editor, Codebase Details, Implementation Readiness

---

## Executive Summary

The multi-lens peer review confirms that the core architectural proposition—eliminating network latency bias by anchoring 3 players to a single shared physical device with local pointer arbitration (`Listener`), paired with a separate Referee cockpit over Supabase—is a sound and elegant foundation.

However, the uninterrupted 5-stage audit uncovered **8 critical blockers** that would have caused immediate runtime failure, transactional deadlocks, broken game loops, and desynchronized scoreboards if implemented as drafted. Across all stages, the reviewers converged on three architectural imperatives:
1. **Restore Human Pacing & Remove Destructive Automation**: Decouple question reveal from buzzer arming, and stop automated client timers from docking player points without Referee confirmation.
2. **Eliminate Relational Partitioning**: Storing scores in `rooms` while listening to `game_states` broke Realtime scoreboards and caused reverse-order transaction deadlocks (`40P01`). All mutable gameplay state must be consolidated into `game_states`.
3. **Purge Enterprise Security Theater & Speculative Views**: Drop 256-bit token hashing and Keystore storage in favor of standard Supabase anonymous `auth.uid()`, and delete unused speculative views (`v_console_questions`).

---

## Traceability Matrix

| Consolidated Action Item | Raw Finding Sources | Severity | Affected Scope |
|---|---|---|---|
| **ACT-01**: Implement `start_game` / `next_question` RPCs | ZoomOut-01, Comp-01, Design-01, Struct-01, Impl-01, Code-01 | 🔴 Blocker | Schema DDL, RPCs, `game_repository.dart` |
| **ACT-02**: Consolidate Mutable State into `game_states` | ZoomOut-02, Comp-04, Design-06, Struct-04, Impl-03, Code-04 | 🔴 Blocker | `rooms`, `game_states`, `RealtimeService` |
| **ACT-03**: Eliminate Reverse-Order Lock Deadlock (`40P01`) | Design-02, Struct-02, Impl-06, Code-03 | 🔴 Blocker | Section 4 (all RPC `FOR UPDATE` clauses) |
| **ACT-04**: Decouple Timer Expiry from Score Penalty | ZoomOut-03, Catalyst-03, InterZoom-03 | 🔴 Blocker | `expire_turn` RPC, Section 2, CUJ 4 |
| **ACT-05**: Decouple Question Delivery from Buzzer Arming | Catalyst-02, InterZoom-01, InterZoom-02 | 🔴 Blocker | Section 2 (State Machine), Section 4, 5.1 |
| **ACT-06**: Correct Clock Offset Math & Server Probe | Catalyst-01, Comp-02, Style-01, Code-06 | 🔴 Blocker | Section 5.2, `countdown_provider.dart` |
| **ACT-07**: Configure Realtime Publications & Replica Identity | Code-02, Impl-03 | 🔴 Blocker | Migration `20261115000000`, `20261115000002` |
| **ACT-08**: Add Missing PIN Entry Screen to Presentation Layer | Style-01 (St.9), Impl-02 | 🔴 Blocker | `app_router.dart`, Section 6 |
| **ACT-09**: Enforce Caller Identity in `SECURITY DEFINER` RPCs | Comp-05, Design-03, Struct-05, Impl-10 | 🟡 Major | Section 4 (all stored procedures) |
| **ACT-10**: Fix PIN Keyspace Collision with Partial Index | Design-04, Struct-12 | 🟡 Major | `rooms.room_pin` DDL & `create_room` |
| **ACT-11**: Add `FOR UPDATE` to `join_room` Concurrency | Design-05, Struct-06 | 🟡 Major | `join_room` RPC |
| **ACT-12**: Fix Local Touch Lockout Reset on Steal Reopen | Design-07, Design-08, Impl-08, Code-08, Code-10 | 🟡 Major | `BuzzerColumnWidget`, `GameStateProvider` |
| **ACT-13**: Strip Keystore Security Theater & Hashed Tokens | ZoomOut-05, InterZoom-05 | 🟡 Major | Section 1, 3, 4, `secure_storage_service` |
| **ACT-14**: Remove Ghost View `v_console_questions` | ZoomOut-06, Comp-06, Style-03, InterZoom-06, Impl-15 | 🟡 Major | Section 6, Migration `20261115000002` |
| **ACT-15**: Dynamic Winner Calculation on Question Exhaustion | Comp-08, Design-09, Struct-10, Impl-13 | 🟡 Major | Section 4, `GameOverDialog` |
| **ACT-16**: Add Question Content Delivery Pipeline | Code-05 | 🟡 Major | `GameStateProvider`, `QuestionDisplayCard` |
| **ACT-17**: Add Test Harness Mocks (`mocktail`) to `pubspec.yaml` | Impl-08, Code-09 | 🟡 Major | `pubspec.yaml`, `test/helpers/` |
| **ACT-18**: Add Platform Manifests and Native Permissions | Impl-10 | 🟡 Major | `AndroidManifest.xml`, `Info.plist` |
| **ACT-19**: Fix Phase Check Constraint vs. State Machine | ZoomOut-04, Comp-09, Style-02, Struct-03 | 🟢 Nit | `game_states.phase` DDL check constraint |
| **ACT-20**: Add Screen Sleep Prevention (`wakelock_plus`) | Catalyst-07, Impl-11, Code-15 | 🟢 Nit | `pubspec.yaml`, `RefereeCockpitScreen` |
| **ACT-21**: Audio Trivia Playback Ducking on Buzz | Design-13, Impl-16, Code-16 | 🟢 Nit | `SoundService`, `QuestionDisplayCard` |
| **ACT-22**: Calibrate Hyperbole ("Zero-Latency", "0ms") | Style-04, Style-06 | 🟢 Nit | Throughout text and verification plan |

---

## Consolidated Action Items by Priority

### 🔴 Critical Blockers (Must Remediate Before Coding)

#### ACT-01: Implement `start_game` and `next_question` RPCs
* **Problem:** The room is initialized in `phase = 'lobby'`. No RPC exists to transition to `'question_active'` or draw the opening question.
* **Resolution:** 
  Create `start_game(p_room_id UUID, p_category TEXT)` and `next_question(p_room_id UUID, p_category TEXT)` with referee authorization (`auth.uid() = referee_uid`), drawing an unused question from `questions`, inserting into `room_questions`, and setting `current_question_id`.

#### ACT-02: Consolidate Mutable State into `game_states`
* **Problem:** `player_scores` is stored in `rooms`, while Realtime listens exclusively on `game_states`. Score adjustments never trigger Realtime broadcasts, leaving the Players Console scoreboard permanently stale.
* **Resolution:** 
  Move `player_scores` and `player_names` into `game_states`. All operational gameplay RPCs will mutate only `game_states`, guaranteeing atomic state broadcasts.

#### ACT-03: Eliminate Reverse-Order Transaction Deadlock (`40P01`)
* **Problem:** `judge_mark` and `expire_turn` lock `game_states` then `rooms`, while `adjust_score` and `skip_question` lock `rooms` then `game_states`. Concurrent invocation crashes one transaction with PostgreSQL deadlock error `40P01`.
* **Resolution:** 
  By executing **ACT-02**, gameplay RPCs mutate only `game_states`, completely eliminating multi-table lock deadlocks by definition. If `rooms` must be referenced, enforce a strict universal lock hierarchy: always `rooms` then `game_states`.

#### ACT-04: Decouple Timer Expiration from Score Penalties
* **Problem:** An automated client timer firing `expire_turn` docks -1 point and locks the player. When a player speaks their answer at second 9.8 and the Referee taps "Correct (+1)" at second 10.1, the call is rejected, causing an unfair 2-point penalty swing.
* **Resolution:** 
  `expire_turn` must NOT deduct points automatically. When the countdown hits zero, transition `phase = 'judge_evaluating'` (or flag `time_expired = true`). The Referee alone decides whether to award +1, deduct -1 for timeout, or skip.

#### ACT-05: Decouple Question Delivery from Buzzer Arming (Intermission Pacing)
* **Problem:** Advancing a question immediately opens all buzzers on the console while the Referee's device is still fetching text, downloading images, or buffering audio clips over the network.
* **Resolution:** 
  Introduce an intermission phase (`question_revealed`). The Referee screen displays the clue and plays media; buzzers remain locked until the Referee taps "Open Buzzer" or audio completes.

#### ACT-06: Correct Clock Offset Math and Server Probe
* **Problem:** The countdown formula added $\Delta_{\text{clock}}$ to an already-absolute server timestamp, doubling local clock error. Furthermore, HTTP `Date` headers have only 1-second resolution.
* **Resolution:** 
  1. Fix formula: $t_{\text{remaining}} = \max\left(0, T_{\text{buzz\_expires\_at}} - \left(T_{\text{local}} + \Delta_{\text{clock}}\right)\right)$.
  2. Measure $\Delta_{\text{clock}}$ via a dedicated lightweight RPC probe (`SELECT clock_timestamp()`) during pairing.

#### ACT-07: Configure Realtime Publication & Replica Identity
* **Problem:** Supabase Realtime drops WebSocket updates on tables with RLS unless added to the publication and configured with full replica identity.
* **Resolution:** 
  Add to migration 0000:
  ```sql
  ALTER TABLE game_states REPLICA IDENTITY FULL;
  ALTER PUBLICATION supabase_realtime ADD TABLE game_states;
  ```

#### ACT-08: Add Missing PIN Entry Screen to Presentation Layer
* **Problem:** GoRouter defines `/join`, but Section 6 omits any screen file for PIN input.
* **Resolution:** 
  Add `lib/features/console/presentation/pin_entry_screen.dart` with 6-digit numeric input, error handling for `ROOM_NOT_FOUND` / `ROOM_ALREADY_CLAIMED`, and navigation to `/console/:roomId`.

---

### 🟡 Major Deficiencies (Must Remediate for Production Quality)

#### ACT-09: Enforce Caller Identity Verification in `SECURITY DEFINER` RPCs
* **Resolution:** Add caller checks at the head of every stored procedure:
  - Referee procedures (`start_game`, `judge_mark`, `adjust_score`, `skip_question`): `IF auth.uid() <> v_room.referee_uid THEN RAISE EXCEPTION 'UNAUTHORIZED_REFEREE'; END IF;`
  - Console procedures (`buzz`): `IF auth.uid() <> v_room.console_uid THEN RAISE EXCEPTION 'UNAUTHORIZED_CONSOLE'; END IF;`

#### ACT-10: Replace Global PIN Unique Constraint with Partial Index
* **Resolution:** Replace table constraint with:
  ```sql
  CREATE UNIQUE INDEX idx_rooms_active_pin ON rooms(room_pin) WHERE room_expires_at > clock_timestamp();
  ```

#### ACT-11: Add `FOR UPDATE` to `join_room` Room Lookup
* **Resolution:** Lock room row during console join to prevent concurrent claim collisions:
  `SELECT * INTO v_room FROM rooms WHERE room_pin = p_pin AND room_expires_at > clock_timestamp() FOR UPDATE;`

#### ACT-12: Fix Local Touch Lockout State Management on Steal Reopen
* **Resolution:** 
  1. In `BuzzerColumnWidget`, check `!lockedPlayerIndices.contains(columnIndex)` *before* setting `localActivePlayer.value`.
  2. In `GameStateProvider`, reset `localActivePlayer.value = null` on every phase transition.

#### ACT-13: Strip Keystore Security Theater & Hashed Tokens
* **Resolution:** Remove 32-byte custom token generation, SHA-256 database hashing, and `flutter_secure_storage`. Rely on Supabase's built-in anonymous `auth.uid()` bound to `referee_uid` / `console_uid`, storing `roomId` and `role` in standard `shared_preferences`.

#### ACT-14: Purge Ghost View `v_console_questions`
* **Resolution:** Delete `v_console_questions` from the schema migration to honor strict Content Isolation.

#### ACT-15: Dynamic Winner Assignment on Question Exhaustion
* **Resolution:** In `judge_mark`, `expire_turn`, and `skip_question`, when questions run out, determine `winner_player_index` by evaluating `array_position(player_scores, max(player_scores))` before setting `phase = 'game_over'`.

#### ACT-16: Add Question Content Delivery Pipeline
* **Resolution:** Add a reactive `currentQuestionProvider` (or inline question fetching in `GameStateProvider`) to load question text, media, and reference answers whenever `currentQuestionId` changes.

#### ACT-17: Add Test Mocks to `pubspec.yaml`
* **Resolution:** Add `mocktail: ^1.0.4` to `dev_dependencies` and add test helper `test/helpers/mock_supabase.dart`.

#### ACT-18: Add Platform Manifests and Native Permissions
* **Resolution:** Add `android/app/src/main/AndroidManifest.xml` (`INTERNET`, `usesCleartextTraffic`) and `ios/Runner/Info.plist` to Target Files.

---

### 🟢 Quality & Ergonomic Polish

#### ACT-19: Harmonize Phase Check Constraint with State Machine
* **Resolution:** Add `'judge_evaluating'` to the database `phase` check constraint.

#### ACT-20: Prevent Mobile Screen Sleep (`wakelock_plus`)
* **Resolution:** Add `wakelock_plus` to `pubspec.yaml` and enable wake locks during active match screens.

#### ACT-21: Duck/Pause Audio Playback on Buzz
* **Resolution:** Trigger `audioPlayer.pause()` immediately when `phase` transitions to `buzzer_active`.

#### ACT-22: Calibrate Hyperbole in Prose
* **Resolution:** Replace "Zero-Latency" and "0ms" with "Sub-frame local touch arbitration (< 16ms)".

---

## Stage Reports Index

All five individual review artifacts have been delivered to the project root:
1. 📄 [Stage 5: Initial Zoom Out & Inventive Catalyst Report](file:///d:/coding/casino/zoom_out_report.md)
2. 📄 [Stage 6: Comprehension Test Report](file:///d:/coding/casino/comprehension_report.md)
3. 📄 [Stage 7: Critic Review Report](file:///d:/coding/casino/critic_report.md)
4. 📄 [Stage 8: Intermediate Zoom Out Report](file:///d:/coding/casino/intermediate_zoom_out_report.md)
5. 📄 [Stage 9: Implementation Readiness Report](file:///d:/coding/casino/implementation_readiness_report.md)
