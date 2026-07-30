# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

iOS app — open `Those-Who-24.xcodeproj` (in repo root, one level above this file) in Xcode and build/run normally. There are no tests, no lint config, and no CLI build script.

- Target name: `Those Who 24` (note spaces) · Bundle ID: `priscillaye.Those-Who-24`
- iOS deployment target: 26.2 · Swift 5 · Universal (iPhone + iPad)
- SwiftPM dependencies: `supabase-swift`, `SwiftDotenv` (resolved by Xcode)

CLI build (rarely needed):
```
xcodebuild -project Those-Who-24.xcodeproj -scheme "Those Who 24" -destination 'generic/platform=iOS Simulator' build
```

### Secrets / `.env`

`Those-Who-24/.env` must contain `PROJECT_URL` and `PUBLISHABLE_API_KEY` (Supabase). `SupabaseConfig.swift` loads it via `Dotenv.configure(atPath:)` and **fatalErrors at launch if missing** — the file must be in the target's *Copy Bundle Resources* phase, not just on disk.

## Architecture

The app has two distinct gameplay paths driven by a top-level `AppMode` switch in `RootView`:

```
Game24App (ThoseWho24App.swift)
    └── RootView                  switches on AppMode
         ├── ContentView          single-player (mode = .singlePlayer)
         ├── StatsView            local stats (mode = .stats)
         ├── SettingsView         theme picker (mode = .settings)
         └── MultiplayerRootView  switches on MultiplayerViewModel.state
              ├── LobbyView          .nameEntry / .loading
              ├── WaitingRoomView    .waitingRoom
              ├── MultiplayerGameView .playing / .roundOver
              └── DissolvedView      .dissolved
```

### Single-player (`ContentView.swift`)

Self-contained: `Fraction` (rational arithmetic with GCD reduction), `findAllSolutions(values:)` (recursive brute-force enumerator returning every operator tree that hits 24), and `GameViewModel` (`@Published` board state, undo stack of `BoardSnapshot`s, Combine timer, hint reveal). On win, calls `StatsManager.shared.recordSolve`.

### Multiplayer (`MultiplayerViewModel.swift` + `Supabase*.swift`)

`MultiplayerViewModel` is `@Observable @MainActor` and owns the lobby state machine plus a *child* `GameViewModel` reused for the in-round UI (via `setupMultiplayerRound(numbers:)`, which skips puzzle generation and timer-on-reset).

Backend is Supabase Postgres + Realtime. **Game-state mutations go through Postgres RPCs**, never direct table writes:
- `start_round(p_room_id, p_host_player_id, p_numbers)` — host deals a puzzle
- `claim_round_win(p_room_id, p_player_id, p_round, p_solution)` — first-write-wins arbitration; returns `Bool`
- `dissolve_room(p_room_id, p_host_id)` — host leaves → room ends

Three tables: `rooms` (status: `waiting`/`playing`/`finished`, current `numbers`, `round`), `players` (per-room, with `last_ping`), `submissions` (winning solves; insert triggers round-over for everyone).

`SupabaseService.subscribe(roomId:...)` opens a single Realtime channel with three Postgres-change listeners (rooms UPDATE, players AnyAction, submissions INSERT) inside a `withTaskGroup`. The returned `Task` is the unsubscribe handle — cancel it on leave. A separate 15-second heartbeat task pings `last_ping` for liveness.

Round flow: host calls `startRound` → all clients see `rooms.status = playing` via `onRoomUpdate` → each builds a local `GameViewModel` → first solver writes a `submissions` row → everyone (including host) reacts via `onSubmission`, scores update locally, host schedules next round after 2.8s.

### Models / Swift 6 concurrency

`SupabaseModels.swift` defines DB row types (`RoomRow`, `PlayerRow`, `SubmissionRow`) and RPC param structs. **All RPC param `Encodable` conformances use explicit `nonisolated func encode(to:)`** — this is intentional to prevent Swift 6 from inferring `@MainActor` on synthesized conformances (which would break `Sendable`). Preserve this pattern when adding new RPC params.

CodingKeys map camelCase Swift fields to snake_case columns (`hostId` ↔ `host_id`, etc.). Room codes use a 32-char alphabet (no `0/O/1/I`) and creation retries on unique-constraint conflicts.

### Theming (`Theme.swift`)

`ColorPalette` (struct of ~25 named colors) × 5 built-ins (`nature`, `ocean`, `berry`, `midnight`, `sunset`). `ThemeManager.shared` is the `ObservableObject` source of truth; it persists the selected palette name to `UserDefaults` under key `"selectedTheme"`. Views read colors via static `Theme.brown`, `Theme.cardSurface`, etc., which proxy to the current palette — **don't hardcode `Color(...)` literals in views**, add a slot to `ColorPalette` if a new semantic color is needed.

### Local persistence

Two singletons, both `UserDefaults`-backed:
- `ThemeManager.shared` — selected palette name (string)
- `StatsManager.shared` — `[SolveRecord]` JSON-encoded under `"solveRecords"` (date, seconds, numbers)

### Haptics

`enum Haptics` in `ContentView.swift` wraps `UIImpactFeedbackGenerator`. Use `Haptics.light/medium/heavy/selection/successDoubleTap/extendedError` instead of instantiating generators inline.
