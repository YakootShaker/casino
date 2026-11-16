# ⚡ Quiz Buzzer — 2-Device Head-to-Head Trivia Arena

A production-grade, real-time multiplayer trivia buzzer application designed for **exactly two physical devices**:
1. **Device 1 (Referee Cockpit)**: Controls match flow, reveals clues, arms buzzers, adjudicates verbal answers (+1 / -1), and confirms timeouts.
2. **Device 2 (Players Console)**: Locked in landscape orientation and split into 3 equal-width touch columns for 3 players. Captures physical touch via raw hardware pointers (`Listener`) with sub-frame arbitration (< 16ms) and strict Content Isolation (zero clues or answers displayed).

---

## 🏛️ Architecture Overview

* **Frontend**: Flutter (Riverpod `AsyncNotifier`, GoRouter, JustAudio, WakelockPlus)
* **Backend**: Supabase (PostgreSQL 15+, Supabase Realtime, Anonymous Auth, Row-Level Security)
* **Touch Arbitration**: Hardware pointer events (`onPointerDown`) with synchronous `ValueNotifier` locks prevent network round-trip discrepancies between players.
* **Content Isolation**: PostgreSQL RLS ensures clue text, media streams, and reference answers are accessible strictly to the Referee device.

```
       [ Device 1: Referee Cockpit ]
                     │  (Calls arm_buzzer, judge_mark, skip_question)
                     ▼
  ┌─────────────────────────────────────────┐
  │         Supabase PostgreSQL & RPC       │
  │  - Single Mutable State: game_states    │
  │  - Row-Level Security Content Isolation │
  │  - Supabase Realtime WebSocket Stream   │
  └─────────────────────────────────────────┘
                     ▲
                     │  (Captures touch < 16ms, dispatches buzz RPC)
       [ Device 2: Shared 3-Player Console ]
       [ Player 1 ] [ Player 2 ] [ Player 3 ]
```

---

## 🚀 Quick Start & Setup

### 1. Prerequisites
* **Flutter SDK**: `^3.13.5` or later
* **Supabase Project**: Free-tier or local Supabase CLI instance

### 2. Configure Environment
Set your Supabase credentials in `lib/core/constants/app_constants.dart` or pass them via `--dart-define`:
```bash
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

### 3. Deploy Supabase Migrations
Apply the transactional migrations in order to your Supabase PostgreSQL database:
1. `supabase/migrations/20261115000000_create_quiz_buzzer_schema.sql` (Tables, Triggers, Realtime publication)
2. `supabase/migrations/20261115000001_create_quiz_buzzer_rpcs.sql` (Atomic PL/pgSQL RPCs with `FOR UPDATE` locks)
3. `supabase/migrations/20261115000002_create_quiz_buzzer_rls.sql` (Row-Level Security policies)
4. `supabase/seed.sql` (Sample trivia questions across Text, Image, and Audio categories)

---

## 📱 Gameplay Workflow (Two Devices)

1. **Host Match (Device 1)**:
   * Tap **"Host as Referee"**.
   * Configure player names and select categories.
   * Tap **"Generate Room PIN"** to obtain an active 6-digit PIN.
2. **Join Match (Device 2)**:
   * Tap **"Join as Players Console"**.
   * Enter the 6-digit PIN shown on the Referee screen.
   * Device 2 locks into landscape orientation showing 3 player columns.
3. **Gameplay**:
   * Referee taps **"Start Match"** → Clue appears on Referee screen.
   * Referee reads clue and taps **"Open Buzzers"** → Device 2 columns light up.
   * First player to touch claims turn (< 16ms) → 10-second server countdown begins.
   * Player speaks verbal answer → Referee marks **Correct (+1)** or **Wrong (-1)**.
   * If wrong, buzzers immediately reopen for the remaining 2 players (Steal mechanic).
   * First player to 5 points wins!

---

## 🧪 Testing & Verification

Run the comprehensive test suite (unit tests, widget tests, and full game loop integration simulations):

```bash
# Run all unit, widget, and integration tests
flutter test

# Run tests with code coverage report
flutter test --coverage

# Run static analysis
flutter analyze
```

---

## 📂 Project Structure

```
casino/                               ← project root (clean)
├── docs/                             ← ALL documentation
│   ├── Quiz_Buzzer_Game_Specification_AR_v2_0.docx
│   ├── spec_extracted.txt
│   ├── concepts_brief.md
│   ├── design_draft.md
│   └── reports/                      ← generated analysis reports
│       ├── comprehension_report.md
│       ├── consolidated_review_report.md
│       ├── critic_report.md
│       ├── implementation_readiness_report.md
│       ├── intermediate_zoom_out_report.md
│       └── zoom_out_report.md
├── assets/
│   └── audio/                        # buzz sound assets
├── lib/
│   ├── app.dart                      # MaterialApp.router & Dark theme setup
│   ├── main.dart                     # Bootstrap & Supabase initialization
│   ├── core/
│   │   ├── constants/
│   │   │   ├── app_colors.dart       # Player colors & palette definitions
│   │   │   └── app_constants.dart    # Game durations, TTL, and asset paths
│   │   ├── services/                 # Consolidates all services
│   │   │   ├── supabase_client.dart  # Supabase client & anonymous auth helper
│   │   │   ├── sound_service.dart    # SFX buzzer & trivia audio controller
│   │   │   └── clock_sync_service.dart # Sub-second RTT clock calibration
│   │   └── widgets/                  # Shared core widgets
│   │       ├── game_over_dialog.dart # Match conclusion dialog & share sheet
│   │       └── reconnecting_overlay.dart # Network resync modal overlay
│   ├── features/
│   │   ├── home/
│   │   │   └── presentation/landing_screen.dart # Device role selection screen
│   │   ├── game/
│   │   │   ├── data/
│   │   │   │   ├── game_repository.dart         # Atomic RPC client repository
│   │   │   │   └── realtime_service.dart        # Realtime WebSocket stream manager
│   │   │   ├── domain/
│   │   │   │   ├── game_state.dart              # Immutable state model
│   │   │   │   ├── question.dart                # Multi-modal question model
│   │   │   │   └── room.dart                    # Room metadata model
│   │   │   └── presentation/providers/          # Riverpod AsyncNotifier & stream providers
│   │   │       ├── countdown_provider.dart
│   │   │       ├── game_state_provider.dart
│   │   │       └── question_provider.dart
│   │   ├── console/
│   │   │   └── presentation/
│   │   │       ├── pin_entry_screen.dart        # 6-digit PIN pairing screen
│   │   │       ├── players_console_screen.dart  # Landscape 3-player touch console
│   │   │       └── widgets/buzzer_column_widget.dart # Raw pointer touch arbitration (<16ms)
│   │   └── referee/
│   │       └── presentation/
│   │           ├── referee_cockpit_screen.dart  # Referee match control cockpit
│   │           ├── room_setup_screen.dart       # Category selection & PIN display
│   │           └── widgets/
│   │               ├── question_display_card.dart # Clue display card & audio controller
│   │               └── scoring_action_bar.dart  # Answer evaluation & score controls
│   └── routes/app_router.dart        # GoRouter declarative route table
├── test/
│   ├── helpers/mock_supabase.dart    # Test fixtures & Mocktail doubles
│   ├── unit/                         # Unit tests (clock sync, touch arbitration)
│   ├── widget/                       # Widget tests (buzzer column widget)
│   └── integration/                  # Integration tests (full game loop simulation)
└── supabase/
    ├── migrations/                   # PostgreSQL DDL, atomic RPCs, and RLS
    └── seed.sql                      # Multi-modal trivia seed data
```
