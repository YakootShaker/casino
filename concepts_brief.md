# Quiz Buzzer — 2-Device Trivia Buzzer Game (Flutter + Supabase)
* **Author:** YakootShaker
* **Date:** 2026-11-14

---

## Overview

Quiz Buzzer is a local-network, two-device trivia game built in Flutter with Supabase as its real-time backend. A single **Referee device** (Device 1) hosts question content, reference answers, and score controls; a single **Players Console device** (Device 2) presents a trisected landscape screen — one buzzer column per player. Players buzz by touching their column; the first touch wins the slot, the Referee evaluates the spoken answer aloud, and awards or deducts a point. First player to 10 points wins.

All seven analytical lenses — Skeptical Architect, Codebase Details, Zoom-Out, Comprehension, Implementation Readiness, Structural, and Inventive Catalyst — were applied to this concept. The synthesis below captures every significant finding, risk, gap, and opportunity, deduplicated and prioritized.

---

## Analysis

### 🔴 Critical Risks & Blockers

#### 1. Client-Driven `expire_turn` Is a Distributed Consensus Problem
*Lens: Skeptical Architect + Structural*

The design relies on "any connected device" to fire `expire_turn` once the client-local countdown hits zero. This creates a **split-brain hazard**:
- If the Referee device is backgrounded/offline, only the Players Console fires. If the Players Console is backgrounded, only the Referee fires. If both are online they race: whichever wins first writes the state transition; the other must silently discard or accept.
- There is no idempotency guard on `expire_turn` in the stated design. Without a Postgres check such as `WHERE game_states.phase = 'buzzer_active' AND buzz_expires_at <= now()` inside an RPC, two concurrent `expire_turn` calls can double-transition state and corrupt `state_version`.
- **Resolution required before Sprint 1:** The `expire_turn` RPC must be written as a conditional `UPDATE … RETURNING` guarded by `phase = 'buzzer_active'` and `buzz_expires_at <= clock_timestamp()`. Both clients should fire it; the first one wins; the second gets a no-op RETURNING. No app-level de-dup is needed if the SQL is idempotent.

#### 2. No Server-Side Expiry Fallback Creates a Zombie State Risk
*Lens: Skeptical Architect + Zoom-Out*

If **both** devices are disconnected simultaneously (e.g. router drops), neither client fires `expire_turn`. When they reconnect, they will each call `expire_turn` — but the reconnect path fetches current state first. If `buzz_expires_at < now()` at reconnect time, the reconnection handler **must** auto-fire `expire_turn` before resuming display. This logic path is not stated in the spec and must be explicitly designed: on `fetchCurrentState()`, if `phase == 'buzzer_active' && buzz_expires_at < now()` → auto-call `expire_turn` RPC immediately.

#### 3. Token-Based Role Locking Has No Revocation or TTL Mechanism
*Lens: Skeptical Architect + Comprehension*

Tokens stored in `flutter_secure_storage` are one-time-join credentials. Failure modes:
- If the Referee device is physically lost or its secure storage is cleared (iOS wipe, Android uninstall), **no one can reclaim the Referee role for that room**. The room becomes permanently locked unless there is a TTL/cleanup strategy.
- Tokens stored as plaintext in the database (not stated as hashed) allow any DB leak to forge roles.
- **Resolution:** Store tokens as `sha256(token)` via `pgcrypto.digest()`. Add a `room_expires_at TIMESTAMPTZ DEFAULT now() + INTERVAL '4 hours'` column; a lazy cleanup RPC deletes expired rooms on next-join attempts.

#### 4. `state_version` Stale-Discard Without Mid-Session Miss Detection
*Lens: Skeptical Architect + Codebase Details*

Supabase Realtime WebSockets can silently drop messages during network blips **without** triggering a disconnect event. If a client misses versions N+1 and N+2 and then receives N+3, it discards N+3 as apparently non-sequential. The spec covers explicit reconnects but not **silent message loss**. The app must respond to Supabase Realtime's `system` channel status events (CHANNEL_ERROR, TIMED_OUT) to trigger a REST refetch when the WebSocket is degraded. Alternatively, compare the Realtime payload's `state_version` to the last-known value; if the gap is > 1, force a REST refetch.

#### 5. Touch Arbitration Fairness on Low-End Hardware
*Lens: Skeptical Architect + Codebase Details*

Flutter's gesture system processes pointer events on the UI thread. On low-end devices with heavy rendering loads, the UI thread can lag, creating uneven touch-event processing across the three columns. Adjacent column boundary multi-touches can produce ambiguous hit-testing.

**Resolution:** Use `Listener` with `onPointerDown` (raw pointer events) rather than `GestureDetector`. Lock out all other columns immediately in a local `ValueNotifier<int?>` (not Riverpod, to avoid full provider tree rebuilds in the critical path) on first `PointerDownEvent`, then send the RPC. Use `HitTestBehavior.opaque` to prevent pointer event bleed-through.

---

### 🟡 Major Gaps & Design Decisions Required

#### 6. Game State Machine Is Underspecified
*Lens: Comprehension + Structural*

The spec references `game_state` phases but never enumerates them. The following state machine is implied by the described behaviors and **must be formally defined before any code is written**:

```
lobby
  → question_active        (Referee reveals question)
      → buzzer_active      (player buzzes in)
          → question_active  (correct answer → score +1 → next question)
          → question_active  (timeout/skip → no points → next question)
          → buzzer_active    (wrong answer → locked_player_index set → reopen for others)  [Decision D1]
          → game_over        (score reaches 10)
```

Key undefined transitions:
- **Wrong answer after buzz**: Does the buzzer reopen for the other two? Or does the question immediately reset? This is the most common physical quiz format gap. *(Decision D1)*
- **Question exhaustion**: What happens when all questions in selected categories are shown? *(Decision D5)*
- **No-buzz scenario**: Is there an auto-timeout for no buzz, or does the Referee manually skip? *(Decision D3)*

#### 7. Player Identity & Name Assignment Underspecified
*Lens: Comprehension + Zoom-Out*

No player account system exists. The spec says "3 columns" but never specifies how players are named on the Referee's score display. The `score_log` table needs stable `player_index` (0–2) plus a `player_name` string. *(Decision D2)*

#### 8. Question Ordering & Category Exhaustion Strategy
*Lens: Comprehension + Zoom-Out*

The spec mentions 10 categories but does not specify:
- How the Referee selects the next question (random draw, sequential, Referee picks category)
- Whether asked questions are marked used per room (requires `room_questions` join table)
- What happens when a category is exhausted mid-game

**Recommended minimum:** A `room_questions(room_id, question_id, asked_at)` join table tracks used questions per room. Referee picks category; server draws a random unused question from that category. *(Decision D4)*

#### 9. Incorrect Answer / Second Chance Mechanic
*Lens: Zoom-Out + Comprehension*

The spec allows Referee to deduct a point (−1) but does not define what state follows: does the buzzer reopen for the other two players, or does the question reset? This is the most common physical quiz format gap.

**Recommended:** After awarding −1, the Referee sees three options: **"Reopen Buzzer"** (other two players can buzz; `locked_player_index` excludes the penalized player), **"Skip Question"**, or **"Award +1 Anyway"** (Referee reverses decision). This requires a `locked_player_index INT` field on `game_states`.

#### 10. Audio Clip Handling & Reveal Timing
*Lens: Codebase Details + Zoom-Out*

`just_audio` (v0.10.6, 150 pub points, 4,152 likes) is the stronger choice over `audioplayers`: better stream-based `PlayerState`, richer error handling, no background-audio configuration needed.

Key concerns:
- Audio clips ≤10s could still be playing when a player buzzes. The Referee UI needs an audio progress indicator separate from the buzz countdown timer.
- `just_audio` does not cache URL sources by default. For repeated replays, bytes must be pre-fetched.
- **Resolution:** Pre-load audio in `question_active` state entry (before question is revealed): `await player.setUrl(url); await player.load();`. Audio plays instantly when the Referee taps play.
- **Decision D7:** Auto-play on question reveal is risky (network latency). Referee presses play manually.

#### 11. Clock Skew on Budget Android Devices
*Lens: Codebase Details + Zoom-Out*

Reconnect derives remaining countdown as `buzz_expires_at - DateTime.now().toUtc()`. On devices with wrong system clocks (common on budget Android), the displayed timer will be wrong by the clock delta.

**Mitigation:** Supabase responses include a server `Date` header. Compute `clockOffset = serverTime - localTime` on initial join and store it. Apply the offset to all `buzz_expires_at` comparisons: `remaining = buzzExpiresAt.add(clockOffset).difference(DateTime.now().toUtc())`.

#### 12. Riverpod Provider Architecture for a Two-Role App
*Lens: Codebase Details*

```
Providers:
  roleTokenProvider (AsyncNotifierProvider) — reads from flutter_secure_storage
  roomProvider (StreamNotifierProvider)     — Supabase Realtime subscription
  gameStateProvider (derived)               — exposes GameState model
  countdownProvider (StreamProvider)        — derived from gameState.buzzExpiresAt + clockOffset

Routing (go_router):
  /             → role selection / room creation
  /referee      → RefereeShell (guarded: role == Role.referee)
  /console      → PlayersConsoleShell (guarded: role == Role.console)
```

**Critical Riverpod pitfall:** `StreamNotifierProvider` with `autoDispose` tears down the Supabase Realtime channel on every widget rebuild. Use `keepAlive` or manage the channel at a `RoomRepository` layer outside Riverpod lifecycle.

#### 13. RLS Policy Design for Anonymous Auth + Token Locking
*Lens: Structural*

Supabase anonymous Auth means every client gets a unique `auth.uid()`. RLS must:
- Allow any anonymous user to `INSERT` a room (gets tokens back via RETURNING)
- Allow only the token-holder (uid-matched) to read Referee-scoped columns (`reference_answer`, question content)
- Allow only the Console token-holder to call `buzz`
- Prevent `reference_answer` from being read by Console role

The token exchange (present raw token → server hashes and stores uid against role) must happen in the join RPC, not in raw table access. Store `referee_uid` and `console_uid` on the room row; check `auth.uid() = referee_uid` or `= console_uid` in RLS policies.

#### 14. Missing Formal Schema Definition
*Lens: Structural + Comprehension*

Proposed minimal schema (must be migrated before Sprint 1 Flutter code runs):

```sql
-- Rooms
CREATE TABLE rooms (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referee_token_hash  TEXT NOT NULL,            -- sha256 of issued token
  console_token_hash  TEXT NOT NULL,
  referee_uid         UUID REFERENCES auth.users(id),
  console_uid         UUID REFERENCES auth.users(id),
  player_names        TEXT[]  NOT NULL DEFAULT ARRAY['Player 1','Player 2','Player 3'],
  player_scores       INT[]   NOT NULL DEFAULT ARRAY[0,0,0],
  created_at          TIMESTAMPTZ DEFAULT now(),
  room_expires_at     TIMESTAMPTZ DEFAULT now() + INTERVAL '4 hours'
);

-- Game State (1:1 with room, lives and dies with room)
CREATE TABLE game_states (
  room_id             UUID PRIMARY KEY REFERENCES rooms(id) ON DELETE CASCADE,
  phase               TEXT NOT NULL DEFAULT 'lobby',
  -- phases: lobby | question_active | buzzer_active | game_over
  state_version       BIGINT NOT NULL DEFAULT 0,
  current_question_id UUID REFERENCES questions(id),
  active_player_index INT,          -- 0,1,2 — who buzzed
  locked_player_index INT,          -- excluded after wrong answer; NULL = nobody locked
  buzz_expires_at     TIMESTAMPTZ,
  updated_at          TIMESTAMPTZ DEFAULT now()
);
-- Auto-increment trigger:
CREATE OR REPLACE FUNCTION increment_state_version()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.state_version := OLD.state_version + 1;
  NEW.updated_at    := clock_timestamp();
  RETURN NEW;
END; $$;
CREATE TRIGGER trg_state_version
  BEFORE UPDATE ON game_states
  FOR EACH ROW EXECUTE FUNCTION increment_state_version();

-- Questions (managed via external admin panel)
CREATE TABLE questions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category         TEXT NOT NULL,
  question_type    TEXT NOT NULL CHECK (question_type IN ('text','image','audio')),
  question_text    TEXT,
  image_url        TEXT,
  audio_url        TEXT,
  reference_answer TEXT NOT NULL,
  created_at       TIMESTAMPTZ DEFAULT now()
);

-- Room-Question usage log (prevents repeat questions per room)
CREATE TABLE room_questions (
  room_id     UUID REFERENCES rooms(id) ON DELETE CASCADE,
  question_id UUID REFERENCES questions(id),
  asked_at    TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (room_id, question_id)
);

-- Score Log
CREATE TABLE score_log (
  id           BIGSERIAL PRIMARY KEY,
  room_id      UUID REFERENCES rooms(id) ON DELETE CASCADE,
  question_id  UUID REFERENCES questions(id),
  player_index INT  NOT NULL,
  delta        INT  NOT NULL,     -- +1 or -1
  reason       TEXT NOT NULL,     -- 'correct' | 'incorrect' | 'manual_adjust' | 'skip'
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX idx_room_questions_room ON room_questions(room_id);
CREATE INDEX idx_score_log_room ON score_log(room_id);
CREATE INDEX idx_questions_category ON questions(category);
```

#### 15. `buzz` RPC Race Condition Guard
*Lens: Structural*

```sql
CREATE OR REPLACE FUNCTION buzz(p_room_id UUID, p_player_index INT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_state game_states;
BEGIN
  SELECT * INTO v_state FROM game_states
  WHERE room_id = p_room_id FOR UPDATE;        -- row-level lock prevents race

  IF v_state.phase <> 'question_active' THEN
    RETURN jsonb_build_object('accepted', false, 'reason', 'wrong_phase');
  END IF;

  IF v_state.locked_player_index = p_player_index THEN
    RETURN jsonb_build_object('accepted', false, 'reason', 'player_locked');
  END IF;

  UPDATE game_states SET
    phase               = 'buzzer_active',
    active_player_index = p_player_index,
    locked_player_index = NULL,
    buzz_expires_at     = clock_timestamp() + INTERVAL '10 seconds'
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object('accepted', true,
    'expires_at', (clock_timestamp() + INTERVAL '10 seconds'));
END; $$;
```

The `FOR UPDATE` row lock prevents two simultaneous buzz calls from both transitioning state.

#### 16. `expire_turn` Must Be Idempotent
*Lens: Structural*

```sql
CREATE OR REPLACE FUNCTION expire_turn(p_room_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_state game_states;
BEGIN
  SELECT * INTO v_state FROM game_states
  WHERE room_id = p_room_id FOR UPDATE;

  -- Guard: only transition if actually in buzzer_active AND timer has elapsed
  IF v_state.phase <> 'buzzer_active'
     OR v_state.buzz_expires_at > clock_timestamp() THEN
    RETURN jsonb_build_object('transitioned', false);
  END IF;

  UPDATE game_states SET
    phase               = 'question_active',
    active_player_index = NULL,
    locked_player_index = NULL,
    buzz_expires_at     = NULL
  WHERE room_id = p_room_id;

  RETURN jsonb_build_object('transitioned', true);
END; $$;
```

Both clients can fire this concurrently — only the first caller within the guard window produces a real transition.

#### 17. Storage Bucket Organization for Question Assets
*Lens: Structural*

```
supabase/storage/
  questions/           (public bucket — read-only for all; write via service role key only)
    images/
      {question_id}.jpg
    audio/
      {question_id}.mp3
```

All `image_url` and `audio_url` columns store the Supabase Storage public CDN URL. No signed URLs are needed since content is not sensitive (royalty-free). The external admin panel uploads via service role key. `cached_network_image` handles HTTP caching for image questions automatically.

---

### 🟢 Opportunities, Polish & Inventive Ideas

#### 18. Haptic + Audio Buzz Feedback
*Lens: Inventive Catalyst*

- On buzz: `HapticFeedback.heavyImpact()` **immediately** on `PointerDownEvent` (before RPC returns) so the response feels instantaneous.
- Play a short local asset buzzer SFX (bundled in `assets/audio/buzz.mp3`, not from network) simultaneously.
- The winning column flashes with a 200ms pulse animation; the two losing columns crossfade to 20% opacity.
- On timeout with no answer: all three columns briefly flash red, then reset to idle.
- On correct answer: winning column bursts with a confetti particle effect (using `flutter_confetti` or a custom `CustomPainter`).

#### 19. Players Console Visual Design Beyond Plain Columns
*Lens: Inventive Catalyst*

- Each column has a unique bold theme color (electric blue / coral red / lime green), not a plain background.
- Player name shown in large bottom-centered type in their column.
- Compact score badge in the top corner of each column.
- When a player's score crosses 7 (approaching win), their column pulses with a subtle golden glow — a warning to opponents.
- Idle state: a subtle animated gradient shimmer in each column background (cheap AnimatedContainer or a 2-color gradient loop) to signal the app is live and listening.

#### 20. Post-Game Shareable Summary via `share_plus`
*Lens: Inventive Catalyst*

After game-over, generate a shareable card:
```
🏆 Quiz Buzzer — Game Summary
Winner: [Name] with 10 points!
Final Scores: [Name1] 10 | [Name2] 7 | [Name3] 5
Questions answered: 22
Played on: 2026-11-14
#QuizBuzzer
```

Render to PNG via `RenderRepaintBoundary.toImage()` → `Share.shareXFiles([XFile(pngPath)])`. This is a zero-cost marketing surface that grows the user base organically.

#### 21. Game Variant Modifiers (v1.5 scope, low backend cost)
*Lens: Inventive Catalyst*

- **Double Points Round**: Referee marks a question as "double" before reveal; `adjust_score` RPC uses delta = ±2. No schema change needed.
- **Steal Mechanic**: After an incorrect buzz, other two players get 5 seconds to steal. Already supported by the `locked_player_index` field if implemented under Decision D1.
- **Hot Streak Indicator**: Client-side only — if a player gets 3 correct in a row (tracked in local `streak_counts` map), their column shows a flame emoji streak counter. Zero backend cost.
- **Sudden Death**: Win condition temporarily drops to current leader + 1; Referee toggles this. One boolean field on `game_states`.

#### 22. Countdown Timer Implementation
*Lens: Codebase Details*

```dart
final countdownProvider = StreamProvider<Duration>((ref) {
  final buzzExpiresAt = ref.watch(gameStateProvider).buzzExpiresAt;
  if (buzzExpiresAt == null) return const Stream.empty();
  final clockOffset = ref.read(clockOffsetProvider);

  return Stream.periodic(const Duration(milliseconds: 100), (_) {
    final remaining = buzzExpiresAt
        .add(clockOffset)
        .difference(DateTime.now().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }).distinct();
});
```

The `countdownProvider` consumer triggers `expire_turn` when the emitted value hits `Duration.zero`.

#### 23. Supabase Realtime Channel Strategy
*Lens: Structural + Codebase Details*

Use a **single Postgres Changes channel per room** listening on the `game_states` table:

```dart
supabase.channel('room:$roomId')
  .onPostgresChanges(
    event: PostgresChangeEvent.update,
    schema: 'public',
    table: 'game_states',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'room_id',
      value: roomId,
    ),
    callback: _handleStateUpdate,
  ).subscribe((status, [error]) {
    if (status == RealtimeSubscribeStatus.channelError) {
      // Force REST refetch — silent message loss mitigation
      _fetchCurrentState();
    }
  });
```

Do **not** subscribe to `rooms` and `score_log` with separate channels in the hot game path — use REST polling for `score_log` only after game-over for the summary screen.

#### 24. `just_audio` Pre-Caching Pattern
*Lens: Codebase Details*

```dart
// In question_active state entry handler, before question is displayed:
await _audioPlayer.setUrl(question.audioUrl);  // loads & buffers over network
await _audioPlayer.load();                      // primes the decode pipeline
// Now reveal question — Referee presses play — response is instant
await _audioPlayer.play();
```

Pre-cache in `question_active` before the Referee sees the question card. The 1–3s network buffering is absorbed invisibly while the Referee is reading the question.

#### 25. Flutter Project Structure & Routing
*Lens: Implementation Readiness*

```
lib/
  main.dart
  app.dart                      # MaterialApp.router + GoRouter
  core/
    supabase_client.dart
    secure_storage.dart
    clock_offset.dart
  features/
    room/
      data/room_repository.dart
      domain/room_model.dart
      presentation/room_creation_screen.dart
      presentation/role_join_screen.dart
    referee/
      data/referee_repository.dart
      presentation/referee_shell.dart
      presentation/question_card.dart
      presentation/scoring_controls.dart
    console/
      presentation/console_shell.dart
      presentation/buzzer_column.dart
    game_state/
      domain/game_state_model.dart
      providers/game_state_provider.dart
      providers/countdown_provider.dart
      providers/clock_offset_provider.dart
```

GoRouter `redirect` guards check `roleTokenProvider` state to gate `/referee` and `/console` routes. Invalid/missing tokens redirect to `/join`.

#### 26. `flutter_secure_storage` iOS Gotcha
*Lens: Codebase Details*

On iOS, `flutter_secure_storage` persists tokens to Keychain and they **survive app reinstall** by default, which is desirable here (device retains its role after reinstall). But tokens also sync to iCloud Keychain by default, potentially appearing on other devices. Set:

```dart
const iosOptions = IOSOptions(
  synchronizable: false,
  accessibility: KeychainAccessibility.whenUnlocked,
);
await secureStorage.write(key: 'role_token', value: token, iOptions: iosOptions);
```

On Android, `EncryptedSharedPreferences` (minSdkVersion 23) backs the storage. If the user clears app data, the token is lost — the room role becomes unclaimable unless a room TTL cleanup is in place.

---

## Goals vs. Non-Goals

### Goals (v1)

| Goal | Notes |
|---|---|
| Two-device local trivia game | Referee + Players Console roles, one room per session |
| Client-side touch arbitration on Players Console | First `PointerDownEvent` wins; one `buzz` RPC sent |
| Server-authoritative 10-second buzz timer | `buzz_expires_at` stored in DB; derived on clients with clock-offset correction |
| Token-based role locking (hashed) | sha256-hashed tokens; uid-binding on join via RPC |
| Realtime state sync via Supabase Postgres Changes | Single channel per room on `game_states`; `state_version` guards stale delivery |
| Cloud question bank, 10 categories, 3 media types | External admin panel manages content; Storage CDN serves assets |
| Score logging and manual ±1 Referee controls | Full `score_log` audit trail per turn |
| First to 10 points wins | Win detection inside `adjust_score` RPC |
| Post-game shareable summary | `share_plus` text card or rendered PNG |
| Reconnection with correct timer resume | Clock-offset correction applied; zombie-state auto-expiry on reconnect |

### Non-Goals (v1)

| Non-Goal | Deferral Rationale |
|---|---|
| Player accounts or persistent profiles | Adds auth complexity with no game value for v1 |
| Tournament brackets or league tables | Out of scope for single-room casual play |
| BYOD (>2 devices) | Architecture is explicitly two-device |
| Offline play | Supabase Realtime requires connectivity |
| In-app question management / admin panel | Managed externally |
| Server-side cron for expiry | v2 addition; client-driven + idempotent RPC suffices for v1 |
| Spectator mode | No third role in token system |
| Background audio playback | App is foreground-only during play |
| Automatic tie-breaking rules | Referee is sole arbiter; simultaneous 10-point scenario is structurally impossible |

---

## Alternatives Weighed

### A. Server-Side Expiry (pg_cron) vs. Client-Driven `expire_turn`
- **Server-side (pg_cron):** Guarantees expiry even when both devices are offline; zero split-brain risk. Adds `pg_cron` extension dependency and a cron job per room (resource concern at scale).
- **Client-driven (chosen for v1):** Simpler; no extension needed. Risk mitigated by: (a) idempotent RPC with `FOR UPDATE` guard, (b) reconnect path auto-fires expiry if `buzz_expires_at` is in the past. **Verdict: acceptable for v1 given the 2-device constraint — a room with zero connected clients is an edge case, not the common path.**

### B. `just_audio` vs. `audioplayers`
- **`just_audio`** (pub score 150, 4,152 likes, Apache-2.0): Stream-based `PlayerState`, better error propagation, easy `setUrl()` → `load()` pre-caching pattern.
- **`audioplayers`** (simpler API, slightly lower setup friction): Historically more platform bugs on iOS; weaker stream-based state.
- **Verdict: `just_audio` is preferred.** The pre-caching pattern is essential for audio questions to feel instant.

### C. Supabase Realtime Broadcast vs. Postgres Changes
- **Broadcast:** Low latency, no DB writes per event, ephemeral. Cannot be reliably triggered by RPC results on the server side.
- **Postgres Changes (chosen):** Automatically fires on any DB mutation from any RPC. Clients get the authoritative post-mutation state. Slight latency (~50–150ms) is acceptable for a turn-based game.
- **Verdict: Postgres Changes is correct.** Broadcast could complement it as a low-latency pre-notification for haptic feedback on buzz, before the authoritative Postgres Change arrives.

### D. `Listener` (raw pointer) vs. `GestureDetector` for Buzzer Columns
- **`GestureDetector`:** Higher-level API; gesture arena adds delay; resolves ambiguity (useful for scrollables, bad for instant tap).
- **`Listener` with `onPointerDown` (chosen):** Zero arena delay; fires on first contact. Explicitly designed for "first touch wins" use cases.
- **Verdict: `Listener` with `HitTestBehavior.opaque` is the correct primitive.**

### E. Single Mutable `game_states` Row vs. Event-Sourced Log
- **Event-sourced:** Full audit trail, time-travel debugging. Much more complex to implement and query in real time.
- **Single mutable row (chosen):** One `UPDATE` per transition; trivially subscribed via Realtime Postgres Changes. `score_log` table provides sufficient audit trail for scoring.
- **Verdict: Single mutable row is correct for v1.**

### F. `flutter_secure_storage` vs. `shared_preferences` for Role Tokens
- **`shared_preferences`:** Readable by other apps on rooted Android; plaintext XML. Unacceptable for role-auth tokens.
- **`flutter_secure_storage` (chosen):** Android Keystore / iOS Keychain backed. Set `synchronizable: false` on iOS to prevent iCloud Keychain sync.
- **Verdict: `flutter_secure_storage` is mandatory.**

---

## Key Decisions & Staging for Next Steps

### Decisions Required Before Sprint 1 Begins

| # | Decision | Options | Recommended |
|---|---|---|---|
| D1 | Wrong-answer behavior | (a) Reopen buzzer for other two players, (b) Reset question immediately | **(a) Reopen buzzer** — adds `locked_player_index`; more exciting gameplay; steal mechanic becomes natural |
| D2 | Player name assignment | (a) Referee pre-game entry, (b) Console pre-game entry, (c) Fixed labels | **(a) Referee pre-game entry** — simplest UX; Referee knows the players |
| D3 | No-buzz timeout | (a) Referee manually skips, (b) Automatic timer (e.g. 30s) | **(a) Manual skip** — v1 simplicity; Referee controls pacing |
| D4 | Question ordering | (a) Referee picks category → random draw, (b) Fully random, (c) Sequential | **(a) Referee picks category** — gives game-night pacing control |
| D5 | Question exhaustion | (a) Reshuffle and replay used questions, (b) Declare game-over | **(b) Game-over** — edge case in real play; real games end by score, not exhaustion |
| D6 | Token storage | (a) Plaintext in DB, (b) sha256 hash in DB | **(b) sha256** — minimal security hardening at no meaningful cost |
| D7 | Audio reveal | (a) Auto-play on question reveal, (b) Referee presses play | **(b) Referee presses play** — prevents network race conditions; Referee controls pacing |

### Sprint 0: Infrastructure & Schema (Week 1)

- [ ] Initialize Flutter project; configure Supabase client, `go_router`, Riverpod
- [ ] Run all Supabase migrations: tables, triggers, indexes, RLS policies
- [ ] Implement and integration-test all 5 RPCs: `join_room`, `buzz`, `expire_turn`, `adjust_score`, `skip_question`
- [ ] Verify Supabase Realtime Postgres Changes works through RLS in Supabase local dev
- [ ] **Spike:** Realtime + anonymous Auth + RLS interplay (high risk — Realtime SELECT permission must be granted explicitly)
- [ ] **Spike:** `Listener`-based touch arbitration on a low-end Android device; measure first-touch-to-RPC latency

### Sprint 1: Core Game Loop (Weeks 2–3)

- [ ] Room creation flow + token issuance
- [ ] Role join screen (enter room code + token → stored in `flutter_secure_storage`)
- [ ] Referee: Question selection UI (category picker → random draw → question card)
- [ ] Players Console: 3-column buzzer UI with `Listener`, local lock-out, haptic feedback
- [ ] Real-time `game_states` subscription + `state_version` guard + degradation handler
- [ ] 10-second countdown with clock-offset correction
- [ ] Reconnection overlay + auto-expiry of zombie buzzer state on reconnect

### Sprint 2: Scoring, Win & Polish (Week 4)

- [ ] Referee: Score controls (+1 / −1) + `adjust_score` RPC
- [ ] Wrong-answer reopen flow (`locked_player_index` logic) per Decision D1
- [ ] Win detection → game-over screen with `score_log` summary
- [ ] `share_plus` post-game card (text + optional PNG via `RenderRepaintBoundary`)
- [ ] Haptic feedback on buzz; buzzer SFX asset integration (`just_audio`)
- [ ] `just_audio` pre-cache pattern for audio questions
- [ ] Column approaching-win pulse animation (≥7 points threshold)

### Sprint 3: Content & Launch (Week 5)

- [ ] Populate question bank: 10 categories, mix of text / image / audio questions
- [ ] Storage bucket setup + CDN URLs in `questions` table rows
- [ ] `cached_network_image` pre-warming for image questions on question reveal
- [ ] End-to-end playtest on two physical devices on a real WiFi network
- [ ] Edge case testing: simultaneous disconnect, Android clock skew, token cleared mid-game
- [ ] Release build + app store submission prep
