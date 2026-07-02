import 'dart:math';
import 'package:flame/components.dart';

import '../components/ball_component.dart';
import '../components/player_component.dart';
import '../game/game_state.dart';
import '../game/spike_zone_game.dart';
import '../systems/action_state.dart';

/// -----------------------------------------------------------------------
/// AI CONTROLLER  (answers request #6)
/// -----------------------------------------------------------------------
/// Two separate concerns, deliberately kept apart:
///
/// 1. PREDICTION (deterministic, "correct" math) — solving the ball's
///    projectile equation for where/when it crosses the floor plane.
///    This should always be accurate; it's what a real player's eyes+brain
///    do intuitively.
///
/// 2. EXECUTION (the "Intelligence" variable) — how well the AI *acts* on
///    that correct prediction. This is where imperfection is injected, so
///    the AI never looks robotic/perfect. Low intelligence = slower
///    reaction, larger positional error, worse decision-making about
///    which of the 1-2-3 touches to take. High intelligence = tighter
///    error bands, but never zero — a 0 error band is what reads as
///    "cheating" to human players.
/// -----------------------------------------------------------------------
class AIController {
  AIController({required this.team, required this.ball, required this.game});

  final List<PlayerComponent> team;
  final BallComponent ball;
  final SpikeZoneGame game;

  /// 0..1. Drives reaction delay, aim error, and movement speed multiplier.
  /// This would be set per-match from a difficulty selector or ramped
  /// dynamically based on score differential (rubber-banding).
  double intelligence = 0.6;

  final Random _rand = Random();
  double _reactionTimer = 0;
  Vector2? _predictedLanding;

  void update(double dt, MatchPhase phase) {
    if (phase != MatchPhase.rallying && phase != MatchPhase.awakening) return;

    _reactionTimer -= dt;
    if (_reactionTimer <= 0) {
      _predictedLanding = predictLandingSpot(ball);
      // Reaction delay: 0.05s (sharp) .. 0.45s (sluggish), inverse to intelligence.
      _reactionTimer = 0.45 - (0.40 * intelligence) + _rand.nextDouble() * 0.05;
    }

    if (_predictedLanding == null) return;
    _moveTowardTarget(dt);
    _considerAttack();
  }

  /// Solves y(t) = y0 + vy0*t + 0.5*g*t^2 for the time t at which the ball
  /// crosses the floor plane, then projects x(t) = x0 + vx0*t.
  /// This is exact for our constant-gravity projectile model.
  Vector2 predictLandingSpot(BallComponent b) {
    const g = BallComponent.gravity;
    final x0 = b.position.x;
    final y0 = b.position.y;
    final vx0 = b.velocity.x;
    final vy0 = b.velocity.y;
    const floorY = 640.0; // CourtComponent.floorY duplicated to avoid import cycle

    // 0.5*g*t^2 + vy0*t + (y0 - floorY) = 0
    final a = 0.5 * g;
    final bCoef = vy0;
    final c = y0 - floorY;
    final disc = bCoef * bCoef - 4 * a * c;
    double t;
    if (disc < 0 || a == 0) {
      t = 0.6; // fallback estimate if ball is moving unusually (e.g. just served)
    } else {
      final sqrtDisc = sqrt(disc);
      final t1 = (-bCoef + sqrtDisc) / (2 * a);
      final t2 = (-bCoef - sqrtDisc) / (2 * a);
      t = max(t1, t2);
      if (t <= 0) t = 0.3;
    }

    final predictedX = x0 + vx0 * t;

    // --- Intelligence-scaled imperfection injected into the PREDICTION
    // itself (not just movement) — lower intelligence AIs literally
    // misjudge the landing spot, which is what produces believably human
    // mistakes (arriving in the wrong spot) rather than always arriving
    // correctly but "deciding" to whiff, which reads as artificial.
    final errorMagnitude = (1 - intelligence) * 90; // px
    final error = (_rand.nextDouble() * 2 - 1) * errorMagnitude;

    return Vector2(predictedX + error, floorY);
  }

  void _moveTowardTarget(double dt) {
    if (_predictedLanding == null) return;
    final target = _predictedLanding!;

    // Pick whichever teammate is closest to the predicted spot AND hasn't
    // touched the ball last (respects the no-consecutive-touch rule).
    final candidates = team.where((p) => p.playerId != ball.lastToucherId).toList();
    if (candidates.isEmpty) return;

    candidates.sort((a, b) =>
        (a.position.x - target.x).abs().compareTo((b.position.x - target.x).abs()));
    final mover = candidates.first;

    // Movement speed: role Speed stat scaled by intelligence, so even a
    // fast Blocker on a "dumb" AI difficulty won't perfectly snap to spot.
    final baseSpeed = 140.0 + mover.stats.speed * 18.0;
    final speedMultiplier = 0.55 + 0.45 * intelligence; // 55%..100% of true speed
    final speed = baseSpeed * speedMultiplier;

    final dx = target.x - mover.position.x;
    final step = dx.sign * min(dx.abs(), speed * dt);
    mover.position.x += step;
  }

  void _considerAttack() {
    // The AI's job now is only to declare INTENT when it's about to be in
    // hitting range — actual resolution happens automatically the moment
    // Flame's collision system detects real hitbox overlap between the
    // ball and this player, via CollisionResolver (see
    // collision_resolution_system.dart). This mirrors exactly how a human
    // player's input would work: press the action button, then the
    // collision either does or doesn't land depending on timing.
    final ballX = ball.position.x;
    for (final p in team) {
      final approaching = (p.position.x - ballX).abs() < 90 &&
          (p.position.y - ball.position.y).abs() < 160;
      if (!approaching) continue;
      if (p.playerId == ball.lastToucherId) continue;
      if (p.currentAction != ActionState.idle) continue; // already committed to an action

      switch (game.touch.touchCount) {
        case 0:
          p.beginDig();
          break;
        case 1:
          p.beginSet();
          break;
        case 2:
          p.beginAttack();
          break;
      }
      break;
    }
  }
}
