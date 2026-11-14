# Quiz Buzzer — 2-Device Architecture

* **Author:** YakootShaker
* **Date:** 2026-11-14

## Overview

Quiz Buzzer is a real-time trivia buzzer game built with Flutter (Android & iOS, phone & tablet) backed by Supabase (Postgres, Realtime, Storage). The game runs on exactly two devices per room: Device 1 is the Referee screen showing all questions, reference answers, and scoring controls; Device 2 is a shared landscape-orientation screen split into three equal horizontal touch zones, one per player. Players see no question content — only their buzzer zone. All questions, timers, scores, and game state live on the server. The Referee evaluates every spoken answer manually.

## Confirmed Constraints

- **2 devices per room, fixed roles:** Referee and Players Console. No other device may join.
- **Players Console layout:** Landscape, 3 equal vertical columns on one screen, each is a full-height tap target for one player. No question text or media shown on this screen.
- **All content on Referee screen only:** Questions (text, image, audio), reference answers, judge notes.
- **Timer behavior:** Starts the moment a valid buzz is confirmed by the server. Keeps running even if the Players Console is backgrounded or temporarily disconnects. The server holds the absolute deadline (`expires_at`). When the device reconnects it re-syncs to that deadline.
- **Turn reset authority:** The Referee can reset/skip a question, which cancels the active turn without automatic point deduction.
- **Media assets:** Royalty-free and free assets only. No copyright concern for private play. App Store publication is a future concern, not v1.
- **Reconnection:** Only the two original devices (carrying their session tokens) may reconnect to an in-progress room.

## Key Technical Decisions

1. **Touch arbitration is local, not networked.** Because all 3 players share one physical screen, the first touch is resolved by Flutter's gesture system on-device before anything is sent to the server. No network race condition between players exists; the Players Console sends one `buzz` RPC with the winning player ID.

2. **Server-authoritative deadline, client-driven expiration pump.** When a buzz is accepted, Supabase records `expires_at = clock_timestamp() + interval '10 seconds'`. Any connected device (Referee or Players Console) can call `expire_turn` after `expires_at` has passed. This means turn expiry does not depend on either device staying continuously online during the countdown.

3. **Fallback expiration when both devices disconnect.** If neither device calls `expire_turn` before reconnecting (e.g., both briefly drop), the first device to reconnect will read stale state and immediately fire the pump call if `clock_timestamp() > expires_at`. No server-side cron or Edge Function is needed for v1 because sessions are private and low-frequency.

4. **Token-based device locking.** On room creation, the server issues two one-time tokens: one for the Referee role, one for the Players Console role. These are stored in device-local secure storage. The server rejects any new join once both roles are claimed, and reconnection requires presenting the matching role token.

5. **Supabase Realtime for state broadcast.** Both devices subscribe to a room-specific Realtime channel. The server broadcasts state snapshots with an incrementing `state_version`; stale updates are discarded on the client.

## Open Risks Identified

- **3-player multitouch on a single screen:** Simultaneous palm placement from three people on a standard 6-inch phone screen is physically crowded. If two players tap within the same Flutter gesture frame (typically 16ms), the gesture recognizer must reliably pick exactly one. This needs testing on low-end Android devices with older touch drivers.
- **OS background suspension vs. timer display:** When Device 2 (Players Console) is backgrounded, the OS halts the Flutter UI loop. The countdown display freezes locally, but the server deadline advances. On return to foreground the display will jump forward. **Resolution (confirmed by author):** Show a "Reconnecting..." overlay immediately on return to foreground, silently re-sync to the server's current state, then remove the overlay and resume the display at the correct remaining time — no elapsed-time explanation shown to players.
- **Reconnect token storage durability:** If a player uninstalls and reinstalls the app mid-session, the stored token is gone. That device can no longer rejoin. For private play this is acceptable but should be documented.

## Goals vs. Non-Goals

**In-Scope Goals:**
- Exactly 2 devices per room (Referee + Players Console)
- Landscape split-screen with 3 equal touch zones, no content shown on players' screen
- Server-authoritative turn timer that survives device backgrounding or brief disconnection
- Referee can reset/skip a question without automatic score penalty
- Role-locked reconnection via per-device session tokens
- Cloud question bank (10 categories, text/image/audio) managed via external admin tool
- Score events logged per turn with manual adjustment support

**Out-of-Scope Non-Goals:**
- One phone per player (BYOD model)
- Offline or local Wi-Fi play
- Automated speech recognition for answer evaluation
- In-app question editing by the Referee
- Tournament systems, accounts, or leaderboards
- Network latency compensation between players (no NTP delta adjustment)
- Copyright media — only royalty-free assets in v1

## Alternatives Weighed

- **One device per player:** Rejected by author. Physical setup simplicity and avoiding per-player BYOD friction outweigh the ergonomic constraints of a shared screen.
- **Server-side timer (pg_cron or Edge Function):** Rejected for v1. Adds infrastructure complexity; client-driven pump is sufficient for private low-frequency sessions.
- **Local hotspot architecture (v1.0):** Rejected. Cloud server is the single source of truth for fairness and state persistence.
- **Portrait orientation for Players Console:** Rejected by author. Landscape orientation gives each player a taller buzzer column and reduces accidental cross-player touches.
