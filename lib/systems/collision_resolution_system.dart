import 'dart:math';
import 'package:flame/components.dart';

import 'action_state.dart';
import '../components/ball_component.dart';
import '../components/player_component.dart';
import '../game/game_state.dart';
import '../game/spike_zone_game.dart';

/// -----------------------------------------------------------------------
/// COLLISION RESOLUTION SYSTEM
/// -----------------------------------------------------------------------
/// This is the single source of truth for "what happens when the ball
/// touches a player." It replaces ad-hoc calls like `player.performAttack()`
/// being invoked directly by input code — instead, input/AI code only sets
/// the player's *intent* via `startAction()`, and this resolver decides
/// the actual outcome at the moment real contact occurs. That keeps input
/// handling, AI decision-making, and physics resolution as three separate
/// concerns that don't need to know about each other's internals.
///
/// Called from `BallComponent.onCollisionStart` — see the wiring at the
/// bottom of ball_component.dart.
///
/// Resolution order on every contact:
///   1. Ignore contact if the player has no active action (idle) — bumping
///      into a ball you didn't attempt to play is not a touch.
///   2. Read timing quality (Perfect/Good/Late) from how long the action
///      has been active relative to its window (see action_state.dart).
///   3. STATE CHECK: a `spiking` action only produces a Spike trajectory
///      if `game.touch.touchCount == 2` at the moment of contact — i.e.
///      this collision would legally be the team's 3rd touch, meaning a
///      teammate set it. Any earlier attempt to "spike" (touchCount 0 or 1)
///      is not a game-rule violation by itself (you're still allowed to
///      attack early), it just doesn't get spike-tier trajectory — it
///      resolves as a normal bump instead, matching real volleyball where
///      an early hard swing on your own dig just isn't a real "spike."
///   4. Compute the resulting velocity from Power/Accuracy/timing/charge.
///   5. Hand the resolved velocity to the ball and consume the player's
///      action state so the same contact can't double-fire.
/// -----------------------------------------------------------------------
class CollisionResolver {
  CollisionResolver._(); // static-only, no instances

  static final Random _rand = Random();

  static void resolve({
    required BallComponent ball,
    required PlayerComponent player,
    required SpikeZoneGame game,
  }) {
    // 1. No active action -> not a touch attempt, ignore silently.
    if (player.currentAction == ActionState.idle) return;

    final timing = player.timingQuality;

    // 3. STATE CHECK — spike legality gate.
    ActionState effectiveAction = player.currentAction;
    final bool spikeIsLegal = game.touch.touchCount == 2;
    if (effectiveAction == ActionState.spiking && !spikeIsLegal) {
      effectiveAction = ActionState.digging; // downgrade: swing landed, but as a soft touch, not a kill
    }

    final aim = _resolveAimDirection(player);
    final chargeFraction = effectiveAction == ActionState.spiking ? player.chargeFraction : 0.0;

    final velocity = _computeVelocity(
      aimDirection: aim,
      power: player.stats.power,
      accuracy: player.stats.accuracy,
      chargeFraction: chargeFraction,
      timing: timing,
    );

    ball.applyResolvedHit(velocity: velocity, hitter: player);

    // Tension/Awakening accrual stays keyed off the *effective* action, not
    // the raw intent — an illegally-early "spike" that got downgraded to a
    // dig should build tension like a dig, not like a finisher.
    _accrueTension(player, effectiveAction, chargeFraction);

    player.clearAction(); // consume — this contact is spent
  }

  static Vector2 _resolveAimDirection(PlayerComponent player) {
    final forward = player.side == TeamSide.home ? 1.0 : -1.0;
    return Vector2(forward, -0.6);
  }

  /// Core velocity formula — Power/Accuracy from the player's stats, plus
  /// the timing-quality modifiers requested: Perfect tightens the aim cone
  /// and grants a small speed bonus; Late widens the cone and saps power,
  /// so a sloppily-timed touch is still legal but visibly worse.
  static Vector2 _computeVelocity({
    required Vector2 aimDirection,
    required int power,
    required int accuracy,
    required double chargeFraction,
    required TimingQuality timing,
  }) {
    double speed = 420 + (power / 10) * 680; // base: power 1..10 -> 420..1100 px/s
    speed *= 1.0 + (0.35 * chargeFraction); // Finish Spike charge bonus, up to +35%

    final double timingDeviationMultiplier;
    final double timingSpeedMultiplier;
    switch (timing) {
      case TimingQuality.perfect:
        timingDeviationMultiplier = 0.15;
        timingSpeedMultiplier = 1.10;
        break;
      case TimingQuality.good:
        timingDeviationMultiplier = 0.55;
        timingSpeedMultiplier = 1.0;
        break;
      case TimingQuality.late:
        timingDeviationMultiplier = 1.4;
        timingSpeedMultiplier = 0.75;
        break;
    }
    speed *= timingSpeedMultiplier;

    // Accuracy narrows the base cone; timing then widens/tightens it further.
    final baseMaxDeviation = (1 - (accuracy / 10)) * 0.35;
    final maxDeviation = baseMaxDeviation * timingDeviationMultiplier;
    final deviation = (_rand.nextDouble() * 2 - 1) * maxDeviation;

    // A full-charge Finish Spike hit on a Perfect window is the one
    // "guaranteed clean" outcome in the whole system — no deviation at all.
    final bool isFlawlessFinish = chargeFraction >= 1.0 && timing == TimingQuality.perfect;
    final effectiveDeviation = isFlawlessFinish ? 0.0 : deviation;

    final cosA = cos(effectiveDeviation);
    final sinA = sin(effectiveDeviation);
    final dir = aimDirection.normalized();
    final rotated = Vector2(
      dir.x * cosA - dir.y * sinA,
      dir.x * sinA + dir.y * cosA,
    );
    return rotated..scale(speed);
  }

  static void _accrueTension(PlayerComponent player, ActionState effectiveAction, double chargeFraction) {
    switch (effectiveAction) {
      case ActionState.digging:
        player.addTension(0.08);
        break;
      case ActionState.setting:
        player.addTension(0.10);
        break;
      case ActionState.blocking:
        player.addTension(0.25);
        break;
      case ActionState.spiking:
        player.addTension(chargeFraction >= 1.0 ? 0.6 : 0.15);
        break;
      case ActionState.idle:
        break;
    }
  }
}
