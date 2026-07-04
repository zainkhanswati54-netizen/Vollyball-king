import 'dart:math';
import 'package:flame/components.dart';

import 'action_state.dart';
import '../components/ball_component.dart';
import '../components/player_component.dart';
import '../game/game_state.dart';
import '../game/spike_zone_game.dart';
import '../camera/camera_config.dart';

/// What a resolved touch actually does to the ball — driven by the TEAM's
/// true touch count (see TouchState.registerTouch in game_state.dart),
/// which is the exact same source of truth the HUD's 1-2-3 lights read
/// from. This is deliberate: trajectory type is never allowed to drift
/// from what's on screen.
enum TouchOutcome { receive, set, spike, softAttack }

/// -----------------------------------------------------------------------
/// COLLISION RESOLUTION SYSTEM
/// -----------------------------------------------------------------------
/// This is the single source of truth for "what happens when the ball
/// touches a player." Input/AI code only sets the player's *intent* via
/// `startAction()` (idle/digging/setting/spiking); this resolver decides
/// the actual outcome at the moment real contact occurs.
///
/// Resolution order on every contact:
///   1. Ignore contact if the player has no active action (idle).
///   2. Read timing quality (Perfect/Good/Late).
///   3. Derive the TouchOutcome from `game.touch.touchCount` — NOT from
///      the declared ActionState alone:
///        - touchCount 0 -> Receive  (pop high + slow toward the setter)
///        - touchCount 1 -> Set      (loft near the net)
///        - touchCount 2 -> the team's LAST legal touch, so it must go
///          toward the opponent's court one way or another: a real Spike
///          if the player declared `spiking` (right-zone tap/AI attack
///          intent), or a weaker `softAttack` bump-over if they didn't —
///          mirroring real volleyball, where the 3rd touch can't just pop
///          back to a teammate, but doesn't have to be a full-power kill.
///   4. Compute velocity from Power/Accuracy/timing/charge, using a speed
///      profile specific to that TouchOutcome.
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
    final outcome = _resolveOutcome(game.touch.touchCount, player.currentAction);

    final aim = _resolveAimDirection(
      player: player,
      outcome: outcome,
      ballPosition: ball.position,
      game: game,
    );
    final chargeFraction = outcome == TouchOutcome.spike ? player.chargeFraction : 0.0;

    final velocity = _computeVelocity(
      aimDirection: aim,
      power: player.stats.power,
      accuracy: player.stats.accuracy,
      chargeFraction: chargeFraction,
      timing: timing,
      outcome: outcome,
    );

    ball.applyResolvedHit(velocity: velocity, hitter: player);
    _accrueTension(player, outcome, chargeFraction);

    player.clearAction(); // consume — this contact is spent
  }

  /// touchCount is the TEAM's own count for their current possession
  /// (reset to 0 the moment the ball switches sides — see TouchState),
  /// so this mapping is exactly "1st/2nd/3rd touch of this side's turn,"
  /// identical to what the HUD's lights show.
  static TouchOutcome _resolveOutcome(int touchCount, ActionState declared) {
    if (touchCount >= 2) {
      // Last legal touch — has to cross the net one way or another.
      return declared == ActionState.spiking ? TouchOutcome.spike : TouchOutcome.softAttack;
    }
    if (touchCount == 1) return TouchOutcome.set;
    return TouchOutcome.receive;
  }

  static Vector2 _resolveAimDirection({
    required PlayerComponent player,
    required TouchOutcome outcome,
    required Vector2 ballPosition,
    required SpikeZoneGame game,
  }) {
    final forward = player.side == TeamSide.home ? 1.0 : -1.0;

    switch (outcome) {
      case TouchOutcome.receive:
        {
          // Touch 1: pop it up toward this team's own Setter, not just
          // straight up — a real "receive" is a controlled pass, not a
          // random deflection.
          final team = player.side == TeamSide.home ? game.homeTeam : game.awayTeam;
          final setter = team.firstWhere(
            (p) => p.role == PlayerRole.setter,
            orElse: () => player,
          );
          final dx = (setter.position.x - ballPosition.x).clamp(-220.0, 220.0);
          return Vector2(dx, -300).normalized();
        }

      case TouchOutcome.set:
        {
          // Touch 2: loft it up and just short of the net, staying on this
          // team's own side so the attacker has a ball to actually attack.
          final netX = kDesignWidth / 2 - (forward * 90);
          final dx = (netX - ballPosition.x).clamp(-260.0, 260.0);
          return Vector2(dx, -320).normalized();
        }

      case TouchOutcome.spike:
        // Touch 3 (real spike): drive forward and down, hard, across the
        // net into the opponent's court.
        return Vector2(forward * 1.0, 0.30).normalized();

      case TouchOutcome.softAttack:
        // Touch 3 (no spike declared): still has to go over — a weak,
        // mostly-flat bump rather than a committed downward kill.
        return Vector2(forward * 0.9, -0.05).normalized();
    }
  }

  /// Speed profile is now per-TouchOutcome rather than one generic
  /// Power-driven formula — this is what makes Receive/Set feel like
  /// controlled, gentle touches and reserves full Power-stat scaling for
  /// the one moment that's supposed to feel powerful: the Spike.
  static Vector2 _computeVelocity({
    required Vector2 aimDirection,
    required int power,
    required int accuracy,
    required double chargeFraction,
    required TimingQuality timing,
    required TouchOutcome outcome,
  }) {
    double speed;
    switch (outcome) {
      case TouchOutcome.receive:
        // Deliberately gentle and only lightly Power-scaled — a receive
        // should pop the ball up softly for a teammate, never rocket it.
        speed = 260 + power * 9;
        break;
      case TouchOutcome.set:
        // Controlled loft — Accuracy matters far more than Power here,
        // matching the Setter's whole GDD identity (high Accuracy, low Power).
        speed = 300 + power * 8;
        break;
      case TouchOutcome.spike:
        speed = 420 + (power / 10) * 680; // full Power-stat scaling
        speed *= 1.0 + (0.35 * chargeFraction); // Finish Spike charge, up to +35%
        break;
      case TouchOutcome.softAttack:
        speed = 340 + power * 10; // clears the net, nowhere near a real spike
        break;
    }

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
    final bool isFlawlessFinish =
        outcome == TouchOutcome.spike && chargeFraction >= 1.0 && timing == TimingQuality.perfect;
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

  static void _accrueTension(PlayerComponent player, TouchOutcome outcome, double chargeFraction) {
    switch (outcome) {
      case TouchOutcome.receive:
        player.addTension(0.08);
        break;
      case TouchOutcome.set:
        player.addTension(0.10);
        break;
      case TouchOutcome.spike:
        player.addTension(chargeFraction >= 1.0 ? 0.6 : 0.15);
        break;
      case TouchOutcome.softAttack:
        player.addTension(0.05);
        break;
    }
  }
}
