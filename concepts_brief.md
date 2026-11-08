# Quiz Buzzer Game (v2.0)

* **Author:** YakootShaker
* **Date:** 2026-11-08

## Overview

Quiz Buzzer is a real-time multiplayer buzzer trivia application built with Flutter and backed by a serverless cloud backend (Supabase Postgres, Realtime, and Storage). One user acts as the Judge/Host to create a room, share a 6-digit numerical PIN, select question categories, and evaluate spoken answers. Between 2 and 6 players join simultaneously via their smartphones without account registration.

Unlike local hotspot-based trivia buzzers, Quiz Buzzer routes all room state, question distribution, and buzzer presses through authoritative server transactions to resolve race conditions and enforce 10-second answer countdowns.

## Analysis

### Critical Vulnerabilities & Contradictions Identified

1. **Client-Driven Timer Pump vs. Disconnection Deadlock**:
   - The specification requires server-authoritative turn timing (10s answering window, 2s winner banner) but specifies that the backend does not run active timers. Instead, any connected client invokes `expire_turn` or `advance_question` after the deadline.
   - **Failure Mode:** If the active player disconnects or turns off connectivity during their turn, and the Judge's connection drops simultaneously, the room enters a frozen state unless another player's device sends the pump call. If clients desynchronize or experience clock drift, race conditions around turn expiration increase server load.

2. **Supabase Realtime Free Tier & Quotas vs. Room Scaling**:
   - The design assumes Supabase Realtime handles state broadcasts, media readiness signaling, and presence.
   - Under Supabase free tier limits (200 concurrent connections, message rate caps), a small number of active 7-person sessions (e.g., ~25 concurrent rooms) can exhaust available connection pools or throttle broadcasts.

3. **Media Sync Fairness vs. Network Latency Inequality**:
   - The specification introduces a `Loading` state with a 5-second maximum barrier to prevent players with faster connections from buzzing before slower devices download media.
   - However, once the `Ready` state triggers, players on low-latency 5G/fiber connections retain an inherent 50–150ms network round-trip advantage over cellular 3G/4G players when sending the `buzz` command. The specification explicitly disclaims latency compensation in v2.0, accepting geographic/carrier bias as an inherent trade-off.

4. **Media Copyright & Content Liability**:
   - Categories including "Songs", "Reversed Songs", "Movies", and "Portrait Picture" rely on copyrighted audio snippets and celebrity photographs. Distributing these assets via public CDN or app stores exposes the project to copyright strikes and platform rejection.

5. **Anonymous Identity Hijacking & Reconnection**:
   - Players join anonymously without credentials, recognized only by room code and screen name.
   - If an anonymous session token is cleared (e.g., app restart or browser cache flush on Flutter Web), an imposter can claim the disconnected player's name and slot unless cryptographically tied to a persistent device UUID.

## Goals vs. Non-Goals

### In-Scope Goals
* **Cross-Platform Flutter Client:** Unified codebase supporting Android, iOS, and future web player clients.
* **Server-Authoritative Concurrency:** Atomic Postgres RPC transactions to adjudicate first-to-buzz events, prevent double scoring, and serialize state versions.
* **Anonymous Access Model:** Zero-friction room creation and player entry via 6-digit numeric PINs.
* **Multi-Modal Cloud Question Bank:** 10 categories spanning text, optimized JPGs (<300KB), and pre-processed reversed MP3 clips (<=10s).
* **Fairness Loading Barrier:** `Loading` synchronization phase waiting for player media readiness reports (or a 5-second fallback ceiling) before opening buzzers.
* **Manual Score Correction & Audit Trail:** Judge-controlled score adjustments (+1 / -1) with real-time notification broadcasts and persistent event logs.

### Out-of-Scope Non-Goals (v2.0)
* **Client-Side Latency Compensation:** No NTP ping time-delta subtraction; first packet received by the server wins.
* **Automated Speech/Song Recognition:** The Judge evaluates all spoken responses manually.
* **In-App Question Authoring:** Questions are maintained exclusively via external database administration or import scripts.
* **Offline / Peer-to-Peer Play:** Local Wi-Fi / Hotspot mesh functionality from v1.0 is deprecated and fully removed.
* **Tournament Ladders & User Authentication:** Persistent accounts, Elo ratings, and multi-stage tournaments are deferred to future releases.

## Alternatives Weighed

* **WebSockets / Dedicated Node.js Server:**
  - *Evaluation:* Offers continuous server-side event loop timers and raw TCP performance.
  - *Status:* Rejected in spec in favor of Supabase Postgres RPC + Realtime to avoid managing VPS infrastructure, though it forces client-driven timer pumping.
* **Local Hotspot / Wi-Fi Mesh (v1.0 Architecture):**
  - *Evaluation:* Zero cloud hosting cost and zero external latency.
  - *Status:* Rejected by author due to high user friction in tethering devices and severe OS network permission restrictions on modern Android/iOS.
* **Client-Authoritative Buzzer Timestamps:**
  - *Evaluation:* Phones report local touch timestamps.
  - *Status:* Rejected due to trivial cheating (tampering with system clock) and lack of trusted client execution.

## Key Decisions & Staging for Next Steps

1. **Timer Expiration Architecture:** Determine whether to keep client-driven `expire_turn` / `advance_question` RPCs with client polling or introduce Supabase Edge Functions / webhooks.
2. **Reconnection Security:** Define device-stored persistent session tokens to bind player slots during network drops.
3. **Room Lifecycle & Auto-Cleanup:** Establish a TTL policy in Postgres to purge abandoned rooms, dead codes, and ephemeral media reports.
4. **Content Strategy:** Clarify how copyrighted media will be licensed, mocked, or restricted during beta and store submission.
