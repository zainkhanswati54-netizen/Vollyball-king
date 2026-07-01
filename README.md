# Spike Zone — 2D Arcade Volleyball (3v3)

Flutter + Flame implementation scaffold, built directly from the design
document (`GDD_Arcade_Volleyball_3v3.md`) and the 9 follow-up architecture
requests. This is a **structural reference implementation** — it's written
to be correct Dart/Flame API usage and complete in its logic, but it has
NOT been run through `flutter pub get` / `flutter run` in this environment
(no Flutter SDK or network access here), so treat it as a strong starting
scaffold to drop into a real Flutter project and iterate on, not a
guaranteed zero-error build on first try. Most likely friction points on
first run are noted at the bottom.

## Setup

**Running locally** (requires the Flutter SDK installed):
```bash
flutter create . --platforms=web,android   # generates platform folders this repo doesn't include
flutter pub get
flutter run
```

**Running via GitHub Actions / CI** — no local Flutter install needed.
The workflow at `.github/workflows/build.yml` runs `flutter create . --platforms=web`
(or `--platforms=android`) itself, on every run, before building — so the
platform folders (`web/`, `android/`) are generated fresh in CI rather than
committed to the repo. This is deliberate: it keeps the repo to just the
game's source code, and avoids committing large, mostly-boilerplate platform
scaffolding that regenerates identically every time anyway.

If you ever want the platform folders committed to the repo instead (e.g.
to customize native Android/iOS config, add an app icon, etc.), run
`flutter create . --platforms=web,android` locally once, remove the
`Generate missing ... platform files` steps from the workflow, and commit
the generated folders.

## File map (design doc → code)

| Request | File(s) |
|---|---|
| #1 GDD | `GDD_Arcade_Volleyball_3v3.md` |
| #2 Game loop / state machine | `lib/game/spike_zone_game.dart`, `lib/game/game_state.dart` |
| #3 BallComponent physics | `lib/components/ball_component.dart` |
| #4 VFX / Finish Spike particles | `lib/vfx/particle_vfx.dart` |
| #5 Camera / fixed resolution | `lib/camera/camera_config.dart` |
| #6 AI opponent | `lib/ai/ai_controller.dart` |
| #7 Active Synergy Traits | `lib/systems/synergy_system.dart`, used in `lib/components/player_component.dart` |
| #8 Persistence (Hive, pre-runApp) | `lib/persistence/persistence_service.dart`, `lib/main.dart` |
| #9 Economy & Gacha balance | `lib/systems/economy_gacha.dart` |
| #10 Juice (shake / hit-stop / flash) | `lib/juice/juice_effects.dart` |

Supporting: `lib/components/court_component.dart` (net/floor geometry),
`lib/components/player_component.dart` (roles, stats, touch actions).

## Known caveats / things to verify once you build it for real

- **Flame API version drift**: this targets Flame `^1.18.0` conventions
  (`FixedResolutionViewport`, `CircleHitbox`, `RectangleHitbox`,
  `OpacityEffect`/`ScaleEffect`/`MoveByEffect`). If your `pubspec.yaml`
  resolves a different minor version, a few constructor signatures may
  have shifted — check `flutter pub outdated` if you hit constructor
  errors.
- **`ai_controller.dart` duplicates `CourtComponent.floorY`** as a literal
  (`640.0`) to avoid a circular import between `ball_component.dart` and
  `court_component.dart`. Before shipping, refactor this into a shared
  constants file (e.g. `lib/court_constants.dart`) so the two can't drift
  out of sync.
- **`juice_effects.dart` hit-stop** uses `game.pauseEngine()` /
  `resumeEngine()` with a `Future.delayed`. This is the simplest correct
  implementation, but if you later add a pause menu, you'll want a
  reference-counted pause flag so a hit-stop firing during a menu-pause
  (or vice versa) doesn't resume the engine early.
- **`particle_vfx.dart`** assumes you'll supply a small pre-baked glow/spark
  `ui.Image` atlas for the `drawAtlas` batched path; until art lands, it
  automatically falls back to a still-reasonably-cheap `drawCircle` loop.
- **Gacha odds** (`economy_gacha.dart`) are placeholder numbers meant to
  demonstrate the role-favoring structure the brief asked for — actual
  rates should go through your live-ops/monetization review before
  shipping, especially in regions with gacha disclosure regulations.
- **No asset files included** — `pubspec.yaml` references
  `assets/images/` and `assets/audio/` directories that don't exist yet
  in this scaffold; create them (even empty with a `.gitkeep`) or remove
  the asset block before your first `pub get`, or it may fail.
