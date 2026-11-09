# Quiz Buzzer Game (2-Device Architecture)

* **Author:** YakootShaker
* **Date:** 2026-11-09

## Overview

Quiz Buzzer is a real-time party trivia game running on Flutter with a Supabase cloud backend (Postgres, Realtime, and Storage). The game operates strictly on a **2-device topology per room**:
1. **Device 1 (Judge / Referee):** Controls room creation, displays reference answers, selects question categories, triggers audio playback, and scores answers (+1 / -1).
2. **Device 2 (Shared Players Console):** A single physical phone or tablet shared by 3 players, with the display split into 3 dedicated touch zones (one per player).

The server enforces game state, question delivery, and turn deadlines.

## Analysis

### Mechanical & Architectural Trade-offs

1. **Touch Arbitration & Screen Constraints**:
   - **Advantage:** Because all 3 players share a single screen, buzzer race conditions are resolved locally on the device with zero network latency variance. The first touch registered by the Flutter gesture recognizer instantly locks the other two zones.
   - **Risk (Hardware & Ergonomics):** Splitting a standard smartphone screen (e.g., 6.1 to 6.7 inches) into 3 interactive touch zones creates high friction for 3 adult hands tapping concurrently. Multitouch hardware drivers on lower-end devices can drop or misfire simultaneous touch events. A tablet layout is ideal, but a phone layout requires strict touch padding and palm-rejection logic.

2. **Timer Continuity & Server Deadline**:
   - The user requires the 10-second timer to start immediately upon touch and continue running uninterrupted even if Device 2 is backgrounded or temporarily drops connection.
   - **Technical Mechanism:** When Device 2 registers a valid touch, it sends a `buzz` RPC with the player ID. The server atomically records `expires_at = clock_timestamp() + interval '10 seconds'` and broadcasts the active turn.
   - If Device 2 is backgrounded, operating system process suspension will halt local UI timers. However, the server's deadline remains unchanged. When Device 2 returns to foreground or reconnects, it queries the server state. If `clock_timestamp() >= expires_at`, the turn is treated as expired with -1 applied immediately.
   - **Edge Case:** If the Judge also disconnects during this 10-second window, turn resolution requires an idempotent pump call or scheduled expiration in Postgres so the game does not stall.

3. **Strict 2-Device Room Security & Session Binding**:
   - Each room strictly permits two connections:
     - `role = judge`
     - `role = players_console`
   - **Technical Mechanism:** Upon room creation, Device 1 receives and stores a cryptographically random `judge_token`. Upon entering the 6-digit room PIN, Device 2 receives and stores a `players_token`.
   - The server rejects any further join attempts once both roles are claimed. If either device disconnects, reconnection is permitted only by presenting the stored token matching that room's role.

4. **Media Copyright & Store Distribution**:
   - Question categories include Arabic pop music snippets, movie titles, and celebrity portraits. If distributed on public app stores (Google Play, Apple App Store), copyrighted audio and media will trigger store rejection or DMCA takedowns unless the media is royalty-free, licensed, or generated without copyright encumbrances.

## Goals vs. Non-Goals

### In-Scope Goals
* **2-Device Room Topology:** Exactly 2 active clients connected per room (1 Judge, 1 Player Console).
* **3-Player Split-Screen Console:** Dedicated 3-zone touch layout on Device 2 with immediate local touch lock and visual feedback.
* **Non-Stop Deadline Enforcement:** Turn timers run against server timestamps (`expires_at`), making backgrounding or network drops incapable of freezing or delaying countdown expiry.
* **Deterministic Role Reconnection:** Token-based device locking so only the original 2 devices can reconnect to an in-progress match.
* **Authoritative Cloud State:** Supabase Postgres RPCs manage score mutations, rounds, and question banks.

### Out-of-Scope Non-Goals
* **N-Device / BYOD Model:** Individual phones for each player are excluded; 3 players must share Device 2.
* **Offline / Peer-to-Peer Play:** No local hotspot or Wi-Fi Direct networking; all interactions flow through the cloud.
* **Automated Audio Answer Evaluation:** The Judge manually determines whether a spoken answer is correct or incorrect.

## Alternatives Weighed

* **One Phone Per Player (v2.0 Spec Document):**
  - *Status:* Rejected by author. The system must use 1 shared device split into 3 touch areas for the 3 players.
* **Local Hotspot / Local Network (v1.0 Spec):**
  - *Status:* Rejected. Cloud serverless backend (Supabase) remains the single source of truth.
* **Client-Authoritative Timers:**
  - *Status:* Rejected. Timers are anchored to server `clock_timestamp()`.

## Key Decisions & Staging for Next Steps

1. **Screen Layout Definition:** Establish UI boundaries and orientation (landscape vs. portrait) for the 3-player split layout on phones vs. tablets.
2. **Timer Expiration Pump:** Finalize the fallback mechanism for resolving `expires_at` when both devices drop connectivity simultaneously.
3. **Question Media Policy:** Determine whether media assets are strictly for personal/local testing or formatted for public store distribution.
