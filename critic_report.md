# Stage 7: Critic Review Report (Design, Structural & Style Audit)

**Target Document:** `docs/designs/quiz_buzzer_2device_architecture.md` (Lines 1..805)  
**Reviewers:** Design Critic (`egm-design`), Structural Validator (`egm-structural`), Style Editor (`egm-style`)  
**Scope:** Architecture, Database Integrity, State Contracts, Security, and Technical Precision

---

## Executive Summary

The Critic Review identified critical flaws that would cause runtime failures, database deadlocks, security bypasses, and state desynchronization if implemented as currently specified:
1. **The Game Cannot Start**: There is no authoritative RPC to transition the room from `lobby` to `question_active` and draw the initial question.
2. **Database Deadlock Hazard**: `judge_mark` and `expire_turn` lock `game_states` then `rooms`, whereas `adjust_score` and `skip_question` lock `rooms` then update `game_states`. Concurrent invocation triggers PostgreSQL deadlock error `40P01`.
3. **Zero Caller Authorization**: Every `SECURITY DEFINER` RPC executes without validating `auth.uid()`. Any client can trigger referee scoring, skip questions, or inject buzzes.
4. **Realtime Score Desynchronization**: Scores reside in `rooms`, while Realtime listens on `game_states`. `adjust_score` mutates `rooms` without touching `game_states`, leaving the Players Console scoreboard completely stale.
5. **Phase & Schema Contradictions**: The state machine diagram specifies `[judge_evaluating]`, but the DDL check constraint restricts `phase` strictly to four phases, causing runtime check constraint violations.
6. **Clock Offset Inversion & Formula Error**: The countdown formula adds $\Delta_{\text{clock}}$ to an already-absolute server timestamp, doubling local clock errors instead of compensating for them.

---

## 🔴 Blocker Findings

### 1. Missing `start_game` RPC — Lifecycle Stalls in `lobby`
* **Affected Scope:** Lines 75–88 (CUJ 2), Lines 274–665 (Section 4)
* **Finding:** `create_room` initializes the room in `phase = 'lobby'`. CUJ 2 specifies that the Referee selects categories and taps "Start Game". However, no `start_game` RPC exists in the architecture. Because direct client writes are forbidden by RLS, there is no API or mechanism to transition a room out of `lobby` or select the initial question.
* **Remediation:** Implement `start_game(p_room_id UUID, p_category TEXT)` with referee authorization, verifying category selection, drawing a question from `questions`, inserting into `room_questions`, and setting `game_states.phase = 'question_active'`.

### 2. Reverse-Order Deadlock Hazard Across PL/pgSQL Stored Procedures
* **Affected Scope:** Lines 428–430 (`judge_mark`), Lines 544–552 (`expire_turn`), Lines 612–624 (`adjust_score`), Lines 639–659 (`skip_question`)
* **Finding:** Stored procedures acquire row locks in conflicting order:
  * `judge_mark` and `expire_turn` lock `game_states` first, then `rooms`.
  * `adjust_score` and `skip_question` lock `rooms` first, then update `game_states`.
  Concurrent execution (e.g. Referee manual score adjustment during a countdown expiration) triggers PostgreSQL transaction deadlock (`40P01`).
* **Remediation:** Standardize a strict deterministic lock hierarchy across all RPCs: always lock `rooms` first, followed by `game_states`.

### 3. Total Lack of Caller Authorization on `SECURITY DEFINER` RPCs
* **Affected Scope:** Lines 380–665 (Section 4)
* **Finding:** All mutation RPCs are declared `SECURITY DEFINER`, bypassing RLS. However, none of the procedures check `auth.uid()`. Any anonymous client with `room_id` can call `judge_mark`, `adjust_score(room_id, 0, 10)` to instantly win, `skip_question`, or inject buzzes.
* **Remediation:** Enforce caller identity verification inside every RPC body:
  * Referee functions (`start_game`, `judge_mark`, `adjust_score`, `skip_question`): `IF auth.uid() <> v_room.referee_uid THEN RAISE EXCEPTION 'UNAUTHORIZED_REFEREE'; END IF;`
  * Console functions (`buzz`): `IF auth.uid() <> v_room.console_uid THEN RAISE EXCEPTION 'UNAUTHORIZED_CONSOLE'; END IF;`

### 4. Realtime Score Desynchronization: `player_scores` in `rooms` vs. `game_states` Subscription
* **Affected Scope:** Lines 154–155, Line 200, Lines 229–240, Lines 602–629
* **Finding:** `player_scores` is stored in `rooms`. Clients subscribe exclusively to WebSocket events on `game_states`. When `adjust_score` updates scores without triggering game over, it updates `rooms` but leaves `game_states` untouched. `trg_state_version` does not fire, and no Realtime event is emitted. The Players Console displays stale scores until the next question transition.
* **Remediation:** Move `player_scores` directly into `game_states` so every score mutation increments `state_version` and broadcasts immediately.

### 5. Phase Constraint Contradiction (`judge_evaluating`)
* **Affected Scope:** Lines 162–181 (State Machine), Lines 231–232 (DDL Check Constraint), Line 431 (`judge_mark`)
* **Finding:** The state machine diagram and lifecycle description define `judge_evaluating` as a formal transition state. However, the database check constraint strictly permits only `('lobby', 'question_active', 'buzzer_active', 'game_over')`. Transitioning to `judge_evaluating` causes an immediate database check constraint violation.
* **Remediation:** Add `'judge_evaluating'` to the database `phase` check constraint or remove it from the state diagram and treat evaluation as client-side interaction during `buzzer_active`.

### 6. Mathematical Inversion in Clock-Offset Formula
* **Affected Scope:** Section 5.2 (Lines 674–680)
* **Finding:** $\Delta_{\text{clock}} = T_{\text{server}} - T_{\text{local}}$. The formula $t_{\text{remaining}} = \max\left(0, \left(T_{\text{buzz\_expires\_at}} + \Delta_{\text{clock}}\right) - T_{\text{local}}\right)$ adds $\Delta_{\text{clock}}$ to an already-absolute server timestamp, doubling local clock error.
* **Remediation:** Correct the formula to:
  $$t_{\text{remaining}} = \max\left(0, T_{\text{buzz\_expires\_at}} - \left(T_{\text{local}} + \Delta_{\text{clock}}\right)\right)$$
  and drop the uncalibrated claim of "exact millisecond-accurate" synchronization from 1-second HTTP headers.

---

## 🟡 Major Findings

### 7. Unlocked Concurrency Race in `join_room` Allowing Console Hijacking
* **Affected Scope:** Lines 333–366
* **Finding:** `join_room` queries `rooms` without a `FOR UPDATE` lock. Concurrent join attempts read `console_token_hash IS NULL`, both generate tokens, and overwrite each other, breaking the 2-device topology.
* **Remediation:** Add `FOR UPDATE` to the room lookup in `join_room`.

### 8. PIN Collision Loop Against Expired Rooms
* **Affected Scope:** Line 194, Lines 292–297
* **Finding:** `rooms.room_pin` has a table-wide UNIQUE constraint, but `create_room` checks availability only against active rooms. If a PIN matches an expired room, the subsequent `INSERT` throws an unhandled duplicate key exception.
* **Remediation:** Replace the table constraint with a partial unique index:
  `CREATE UNIQUE INDEX idx_rooms_active_pin ON rooms(room_pin) WHERE room_expires_at > clock_timestamp();`

### 9. Local Touch Lockout State (`localActivePlayer`) Never Cleared on Steal
* **Affected Scope:** Lines 668–675
* **Finding:** If Player 0 buzzes and answers incorrectly, the server transitions back to `question_active` with `locked_player_indices = [0]`. If `localActivePlayer.value` is not cleared on the client, Columns 1 and 2 discard all subsequent touches.
* **Remediation:** Explicitly reset `localActivePlayer.value = null` on phase change to `question_active` or when `active_player_index == null`.

### 10. Locked Player Can Sabotage Steal Board
* **Affected Scope:** Lines 668–675
* **Finding:** The touch arbiter sets `localActivePlayer.value = columnIndex` before checking `locked_player_indices`. A locked player can tap their column to temporarily block opponents while an RPC round-trip is in flight.
* **Remediation:** Check `!locked_player_indices.contains(columnIndex)` locally before setting `localActivePlayer.value`.

### 11. Undefined Victor on Question Exhaustion
* **Affected Scope:** Lines 464–467, 500–502, 570–573, 646–649
* **Finding:** When questions are exhausted, `winner_player_index` is left as `NULL`, causing `GameOverDialog` null-pointer crashes.
* **Remediation:** Calculate the highest-scoring player index upon exhaustion and assign it to `winner_player_index`.

### 12. Ghost View Reference & Conflicting Data Exposure (`v_console_questions`)
* **Affected Scope:** Line 13, Line 37, Line 698
* **Finding:** Creating `v_console_questions` contradicts stated Content Isolation non-goals and exposes trivia metadata to the console device.
* **Remediation:** Remove `v_console_questions`. Restrict `questions` SELECT strictly to `referee_uid`.

---

## 🟢 Nit Findings

### 13. Elimination of "Zero-Latency" and "0ms" Hyperbole
* **Affected Scope:** Lines 34, 84, 670, 727, 766
* **Finding:** Replace engineering hyperbole ("Zero-Latency", "0ms") with calibrated technical terms ("sub-frame local touch arbitration (< 16ms)").

### 14. Error Code Inconsistency (`room_full` vs `ROOM_ALREADY_CLAIMED`)
* **Affected Scope:** Line 73 vs Line 357
* **Finding:** Align prose in CUJ 1 to match the returned SQL error code `ROOM_ALREADY_CLAIMED`.

### 15. Audio Playback Overlap on Buzz
* **Affected Scope:** Section 5.4
* **Finding:** When a player buzzes during an audio clip, pause or stop audio immediately so the spoken answer is audible over the countdown.

### 16. Missing Search Path Hardening in Stored Procedures
* **Affected Scope:** Section 4
* **Finding:** Add `SET search_path = public, pg_temp;` to all `SECURITY DEFINER` functions to comply with PostgreSQL security best practices.
