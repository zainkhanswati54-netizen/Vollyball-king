import 'dart:async';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';

import 'game_state.dart';
import '../components/ball_component.dart';
import '../components/player_component.dart';
import '../components/court_component.dart';
import '../ai/ai_controller.dart';
import '../juice/juice_effects.dart';
import '../camera/camera_config.dart';
import '../persistence/persistence_service.dart';

/// -----------------------------------------------------------------------
/// MAIN GAME CLASS  (answers request #2)
/// -----------------------------------------------------------------------
/// Performance notes for 60fps on mobile:
///  1. We use `update(dt)` everywhere and NEVER do per-frame allocations
///     (no `List.generate`, no new Vector2() in hot loops — components
///     mutate in place via `.setFrom` / `..x =` etc).
///  2. The state machine below is a single switch on an enum — cheap to
///     branch, no polymorphic dispatch overhead per frame.
///  3. Heavy one-off work (score screen construction, gacha animations)
///     is deferred to `scoring`/`setPoint` phases, which are low-frequency
///     transitions, not per-frame paths.
///  4. `FixedResolutionViewport` (see camera_config.dart) means we never
///     recompute layout mid-rally — layout cost is paid once on resize.
/// -----------------------------------------------------------------------
class SpikeZoneGame extends FlameGame
    with HasCollisionDetection, TapCallbacks, DragCallbacks {
  SpikeZoneGame({required this.persistence});

  final PersistenceService persistence;

  // --- Core state ---
  MatchPhase phase = MatchPhase.serving;
  final TouchState touch = TouchState();
  final ScoreState score = ScoreState();
  TeamSide serving = TeamSide.home;

  // --- Time-scale support for Awakening (Zone Perception) ---
  double _timeScale = 1.0;
  double get timeScale => _timeScale;

  // --- Entities ---
  late BallComponent ball;
  final List<PlayerComponent> homeTeam = [];
  final List<PlayerComponent> awayTeam = [];
  late AIController aiController;
  late JuiceEffects juice;

  double _phaseTimer = 0;

  @override
  Color backgroundColor() => const Color(0xFF0B1622);

  @override
  Future<void> onLoad() async {
    // Camera / viewport setup — see camera_config.dart for the
    // withFixedResolution rationale (request #5).
    await configureCamera(this);

    final court = CourtComponent();
    await add(court);

    ball = BallComponent(court: court);
    await add(ball);

    homeTeam.addAll(PlayerComponent.buildTeam(side: TeamSide.home, court: court));
    awayTeam.addAll(PlayerComponent.buildTeam(side: TeamSide.away, court: court));
    await addAll([...homeTeam, ...awayTeam]);

    aiController = AIController(
      team: awayTeam,
      ball: ball,
      game: this,
    );

    juice = JuiceEffects(game: this);

    _enterPhase(MatchPhase.serving);
  }

  // -----------------------------------------------------------------
  // MAIN LOOP
  // -----------------------------------------------------------------
  @override
  void update(double dt) {
    // Apply Awakening time-scale ONLY to world simulation dt, not to the
    // dt Flame uses for its own bookkeeping — this is what lets player
    // *input* feel unslowed relative to the world (see GDD 5.3).
    final worldDt = dt * _timeScale;

    super.update(dt); // engine bookkeeping (animations, particles) at real dt
    aiController.update(worldDt, phase);

    _phaseTimer += dt; // phase timers always run at real time, not slowed

    switch (phase) {
      case MatchPhase.serving:
        _updateServing(worldDt);
        break;
      case MatchPhase.rallying:
        _updateRallying(worldDt);
        break;
      case MatchPhase.awakening:
        _updateAwakening(worldDt);
        break;
      case MatchPhase.scoring:
        _updateScoring(worldDt);
        break;
      case MatchPhase.setPoint:
        _updateSetPoint(worldDt);
        break;
      case MatchPhase.matchOver:
        break;
    }
  }

  // -----------------------------------------------------------------
  // STATE HANDLERS
  // -----------------------------------------------------------------
  void _enterPhase(MatchPhase next) {
    phase = next;
    _phaseTimer = 0;
    switch (next) {
      case MatchPhase.serving:
        touch.reset();
        ball.resetForServe(serving);
        break;
      case MatchPhase.rallying:
        break;
      case MatchPhase.awakening:
        _timeScale = 0.18; // ~18% speed — tune per GDD 5.3
        juice.onAwakeningEnter();
        break;
      case MatchPhase.scoring:
        _timeScale = 1.0;
        break;
      case MatchPhase.setPoint:
        persistence.recordSetResult(score);
        break;
      case MatchPhase.matchOver:
        persistence.recordMatchResult(score);
        break;
    }
  }

  void _updateServing(double dt) {
    // Wait for serve input; handled via tap/drag callbacks below.
  }

  void _updateRallying(double dt) {
    if (touch.isFault) {
      _awardPoint(touch.possessingTeam == TeamSide.home ? TeamSide.away : TeamSide.home);
      return;
    }
    // Tension meter accrual lives on AwakeningTracker inside AIController/
    // player input handlers when a touch resolves successfully — kept out
    // of the main loop to avoid recomputing every frame.
  }

  void _updateAwakening(double dt) {
    // World simulation still runs (ball still moves) but at `_timeScale`.
    // The attacking player's extended aim-input window is handled by the
    // PlayerComponent itself while phase == awakening.
    if (_phaseTimer > 2.2) {
      _timeScale = 1.0;
      _enterPhase(MatchPhase.rallying);
      juice.hitStop(durationMs: 90); // punctuation on exiting slow-mo
    }
  }

  void _updateScoring(double dt) {
    if (_phaseTimer > 1.2) {
      if (score.setIsOver()) {
        _enterPhase(MatchPhase.setPoint);
      } else {
        serving = touch.possessingTeam ?? serving;
        _enterPhase(MatchPhase.serving);
      }
    }
  }

  void _updateSetPoint(double dt) {
    if (_phaseTimer > 3.0) {
      if (score.matchIsOver()) {
        _enterPhase(MatchPhase.matchOver);
      } else {
        _enterPhase(MatchPhase.serving);
      }
    }
  }

  // -----------------------------------------------------------------
  // PUBLIC API called by BallComponent / PlayerComponent / AIController
  // -----------------------------------------------------------------

  /// Called by PlayerComponent when a touch is legally resolved.
  void registerTouch(int playerId, TeamSide side) {
    if (phase != MatchPhase.rallying && phase != MatchPhase.awakening) return;
    final legal = touch.registerTouch(playerId, side);
    if (!legal) {
      _awardPoint(side == TeamSide.home ? TeamSide.away : TeamSide.home);
    }
  }

  /// Called by an attacking PlayerComponent whose Tension Meter is full.
  void triggerAwakening() {
    if (phase == MatchPhase.rallying) {
      _enterPhase(MatchPhase.awakening);
    }
  }

  void _awardPoint(TeamSide winner) {
    if (winner == TeamSide.home) {
      score.homePoints++;
    } else {
      score.awayPoints++;
    }
    juice.onPointScored(winner);
    _enterPhase(MatchPhase.scoring);
  }

  void ballLandedOutOfBounds(TeamSide lastToTouch) {
    _awardPoint(lastToTouch == TeamSide.home ? TeamSide.away : TeamSide.home);
  }

  void ballLandedInCourt(TeamSide courtOwner) {
    // If the ball lands in a court and that team never got 3 legal
    // touches in, it's already handled via touch.isFault; a clean landing
    // simply means the opposing team failed to return it.
    _awardPoint(courtOwner == TeamSide.home ? TeamSide.away : TeamSide.home);
  }
}
