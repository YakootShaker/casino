# Stage 9: Implementation Readiness Test Report

**Target Document:** `docs/designs/quiz_buzzer_2device_architecture.md` (Lines 806..1042)  
**Reviewers:** Implementation Readiness (`egm-implementation-readiness`), Codebase Details (`egm-codebase-details`), Style Reviewer (`egm-style`)  
**Scope:** Execution Completeness, Migration Integrity, Package Contracts, Realtime Plumbing, and Verification Feasibility

---

## Executive Summary

The Detailed Implementation Plan is **not yet ready for immediate coding**. While the high-level file taxonomy is cleanly organized, critical implementation contracts are missing:
1. `start_game` and `next_question` RPCs are completely absent from both the database migration scripts and Dart `GameRepository`.
2. The PIN entry screen (`pin_entry_screen.dart` / `join_screen.dart`) is missing from the presentation file tree despite being mapped in GoRouter.
3. Supabase Realtime requires explicit PostgreSQL configuration (`ALTER PUBLICATION supabase_realtime ADD TABLE game_states;` and `ALTER TABLE game_states REPLICA IDENTITY FULL;`) without which WebSocket events will be dropped silently in production.
4. Score changes and console pairing updates are partitioned across `rooms` and `game_states`, leaving Realtime listeners completely blind to manual score adjustments and console pairing.
5. Inverted countdown math, reverse-order database lock deadlocks, missing test mock harnesses, and missing native platform permissions will cause developer stalls during Sprint 0.

---

## 🔴 Blocker Findings

### 1. Missing `start_game` / `next_question` in Migrations and Repository
* **Affected Scope:** Lines 834–838 (`20261115000001_create_quiz_buzzer_rpcs.sql`), Lines 915–919 (`game_repository.dart`), Lines 942–946 (`room_setup_screen.dart`)
* **Finding:** `create_room` initializes the session in `phase = 'lobby'`. Direct table writes are strictly prohibited by RLS. Neither migration 0001 nor `GameRepository` includes a `start_game` or `next_question` RPC. The match cannot leave `lobby` or select opening questions.
* **Remediation:** Add `start_game(p_room_id UUID, p_category TEXT)` and `next_question(p_room_id UUID, p_category TEXT)` to migration `20261115000001_create_quiz_buzzer_rpcs.sql` and `game_repository.dart`.

### 2. Missing PIN Entry Screen in Presentation Layer
* **Affected Scope:** Lines 893–897 (`app_router.dart`), Lines 925–981 (Section 6)
* **Finding:** Route `/join` is defined in `app_router.dart`, and CUJ 1 mandates that Device 2 enters the 6-digit PIN. However, Section 6 lists zero screen or widget files for PIN input.
* **Remediation:** Add `lib/features/console/presentation/pin_entry_screen.dart` with numeric input pad, 6-digit validation, error handling for `ROOM_NOT_FOUND` / `ROOM_ALREADY_CLAIMED`, and navigation to `/console/:roomId`.

### 3. Missing Realtime Publication & Replica Identity in Database Migrations
* **Affected Scope:** Lines 829–833 (`20261115000000_create_quiz_buzzer_schema.sql`), Lines 839–843 (`20261115000002_create_quiz_buzzer_rls.sql`), Lines 920–924 (`realtime_service.dart`)
* **Finding:** Supabase Realtime only broadcasts table changes when the table is explicitly added to the `supabase_realtime` publication, and RLS requires `REPLICA IDENTITY FULL` to avoid dropping update payloads for non-superusers. Neither statement is in the migration plan.
* **Remediation:** Include in migration 0000:
  ```sql
  ALTER TABLE game_states REPLICA IDENTITY FULL;
  ALTER PUBLICATION supabase_realtime ADD TABLE game_states;
  ```

### 4. Broken Realtime Sync: `rooms` vs. `game_states` Partition
* **Affected Scope:** Lines 900–909, Lines 920–924 (`realtime_service.dart`), Lines 927–931 (`game_state_provider.dart`)
* **Finding:** `player_scores` and `console_uid` reside in `rooms`, but `realtime_service.dart` subscribes exclusively to `game_states`. When `adjust_score` mutates `rooms`, `game_states` is untouched, and zero Realtime events fire. The Players Console scoreboard remains permanently desynchronized. Similarly, the Referee never receives a Realtime event when the console pairs.
* **Remediation:** Move `player_scores` and pairing status directly into `game_states` so every score change increments `state_version` and broadcasts over the existing channel.

### 5. Missing Question Content Delivery Pipeline in Presentation Layer
* **Affected Scope:** Lines 910–914 (`question.dart`), Lines 927–931 (`game_state_provider.dart`), Lines 947–956 (`referee_cockpit_screen.dart`, `question_display_card.dart`)
* **Finding:** `GameState` only holds `currentQuestionId` (UUID). The Referee Cockpit requires full question text, media URLs, reference answers, and notes, but the plan specifies no `question_provider.dart` or fetch orchestration when `currentQuestionId` changes.
* **Remediation:** Add a reactive `currentQuestionProvider` (or inline question fetching in `GameStateProvider`) that loads question content whenever `currentQuestionId` transitions.

### 6. Invalid RLS Table Column Reference in Migration 0002
* **Affected Scope:** Lines 839–843 (`20261115000002_create_quiz_buzzer_rls.sql`)
* **Finding:** The plan specifies RLS checking `auth.uid() = referee_uid` on `questions`. The `questions` table schema has no `referee_uid` column. Running this migration will cause PostgreSQL to abort with `ERROR: column "referee_uid" does not exist`.
* **Remediation:** Restrict direct access to `questions` and deliver clues/answers exclusively via authenticated RPC responses.

---

## 🟡 Major Findings

### 7. Unconditional Anonymous Sign-In Destroys Reconnection State
* **Affected Scope:** Lines 861–865 (`supabase_client.dart`)
* **Finding:** Calling `signInAnonymously()` unconditionally on app startup without checking `supabase.auth.currentUser == null` mints a new `auth.uid()` on every restart, breaking role-locked reconnection.
* **Remediation:** Only call `signInAnonymously()` if `supabase.auth.currentUser == null`.

### 8. Local Touch Arbiter Reset & Steal Lockout Leaks
* **Affected Scope:** Lines 927–931 (`game_state_provider.dart`), Lines 967–971 (`buzzer_column_widget.dart`)
* **Finding:** `BuzzerColumnWidget` acquires the local lock (`localActivePlayer.value = columnIndex`) without checking if the column is in `lockedPlayerIndices`, allowing disqualified players to sabotage steals. Furthermore, no listener clears `localActivePlayer.value = null` on steal reopen.
* **Remediation:** Verify `!lockedPlayerIndices.contains(columnIndex)` before setting `localActivePlayer.value`. Reset `localActivePlayer.value = null` whenever `activePlayerIndex == null` or on phase transition to `question_active`.

### 9. Test Infrastructure Neglect: Missing Mocks in `pubspec.yaml`
* **Affected Scope:** Lines 812–816 (`pubspec.yaml`), Lines 999–1003 (`game_loop_mock_test.dart`)
* **Finding:** `game_loop_mock_test.dart` simulates the entire lifecycle, but `pubspec.yaml` lists zero test mocking dependencies (`mocktail`, `mockito`) or mock helpers.
* **Remediation:** Add `mocktail: ^1.0.4` to `dev_dependencies` and add `test/helpers/mock_supabase.dart`.

### 10. Missing Platform Permissions and Manifests
* **Affected Scope:** Lines 812–816, Lines 866–880
* **Finding:** Network requests, local testing on cleartext loopback (`10.0.2.2`), and audio streaming require Android and iOS native manifest permissions that are absent from the file list.
* **Remediation:** Add target entries for `android/app/src/main/AndroidManifest.xml` (`INTERNET`, `usesCleartextTraffic`) and `ios/Runner/Info.plist`.

### 11. Missing Screen Sleep Prevention (`wakelock_plus`)
* **Affected Scope:** Lines 812–816 (`pubspec.yaml`), Lines 947–951, Lines 962–966
* **Finding:** Under default mobile OS power management, screens dim and sleep after 30–60 seconds, disconnecting WebSockets during clue reading.
* **Remediation:** Add `wakelock_plus` to `pubspec.yaml` and enable wake locks on active game screens.

### 12. Null Winner Crash on Question Exhaustion
* **Affected Scope:** Lines 905–909 (`game_state.dart`), Lines 977–981 (`game_over_dialog.dart`)
* **Finding:** When questions run out, `winner_player_index` is left as `NULL`. `game_over_dialog.dart` evaluating `playerNames[winnerPlayerIndex!]` will crash with a null check exception.
* **Remediation:** Calculate the highest-scoring player index upon exhaustion and assign it to `winner_player_index`.

---

## 🟢 Nit Findings

### 13. Premature Orientation Locking in `main.dart`
* **Finding:** Enforce landscape orientation inside `PlayersConsoleScreen.initState` / `dispose` rather than conditionally in `main.dart`.

### 14. Purge Ghost View `v_console_questions`
* **Finding:** Drop `v_console_questions` from migration 0002 to maintain strict Content Isolation.

### 15. Audio Playback Overlap on Buzz Activation
* **Finding:** In `question_display_card.dart`, listen to `gameStateProvider` and pause audio when `phase == 'buzzer_active'`.

### 16. Incomplete Coverage Verification Command
* **Finding:** Replace `flutter test` with `flutter test --coverage` and a coverage threshold checker.
