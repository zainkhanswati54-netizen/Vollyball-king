import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flutter/material.dart';

import 'court_component.dart';
import 'player_component.dart';
import '../game/game_state.dart';
import '../game/spike_zone_game.dart';
import '../camera/camera_config.dart';
import '../systems/collision_resolution_system.dart';

/// -----------------------------------------------------------------------
/// BALL COMPONENT  (answers request #3)
/// -----------------------------------------------------------------------
/// Physics model: simple projectile motion under constant gravity, which
/// reads visually as a "parabolic arc" — this is the classic arcade sports
/// approach (Mario Tennis/Volleyball-likes use the same trick) rather than
/// full rigid-body simulation, because it's cheap, deterministic, and easy
/// to reason about for AI landing-spot prediction (see ai_controller.dart).
///
/// State: position (Vector2), velocity (Vector2). Each frame:
///   velocity.y += gravity * dt
///   position += velocity * dt
///
/// Collision responses (floor / net / player hitbox) are all velocity
/// reflections/overrides rather than physics-engine impulse resolution —
/// again, deliberate: arcade feel wants *predictable* bounces, not
/// "realistic" but chaotic ones.
/// -----------------------------------------------------------------------
class BallComponent extends CircleComponent
    with CollisionCallbacks, HasGameReference<SpikeZoneGame> {
  BallComponent({required this.court}) : super(radius: 14, anchor: Anchor.center);

  final CourtComponent court;

  static const double gravity = 980.0; // px/s^2, tuned for a ~0.9s apex-to-apex arc
  static const double maxSpeed = 1400.0;

  final Vector2 velocity = Vector2.zero();
  int? lastToucherId;
  TeamSide? lastToucherSide;

  bool _inPlay = false;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    paint = Paint()..color = Colors.white;
    add(CircleHitbox()..collisionType = CollisionType.active);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!_inPlay) return;

    velocity.y += gravity * dt;
    if (velocity.length > maxSpeed) {
      velocity.scaleTo(maxSpeed);
    }
    position += velocity * dt;

    _checkOutOfBounds();
  }

  void resetForServe(TeamSide server) {
    _inPlay = false;
    lastToucherId = null;
    lastToucherSide = null;
    final x = server == TeamSide.home ? 120.0 : kDesignWidth - 120.0;
    position = Vector2(x, CourtComponent.floorY - 260);
    velocity.setValues(0, 0);
  }

  void launchServe(Vector2 dir, double power) {
    _inPlay = true;
    velocity.setFrom(dir.normalized()..scale(power));
  }

  /// Core formula for request #3: velocity modifier based on a player's
  /// Power and Accuracy stats, plus (optionally) a charge fraction for
  /// the Spiker's Finish Spike.
  ///
  /// - Power drives raw magnitude (how hard the ball goes).
  /// - Accuracy narrows the random angle deviation applied to aim —
  ///   low-accuracy hits get a wider random cone, so the *intended*
  ///   direction and the *actual* direction diverge more.
  /// - chargeFraction (0..1) is Spiker-only; at 1.0 it grants a flat
  ///   speed multiplier and removes angle deviation entirely (a "clean"
  ///   Finish Spike), rewarding the risk of holding the charge.
  static Vector2 computeHitVelocity({
    required Vector2 aimDirection,
    required int power, // 1..10
    required int accuracy, // 1..10
    double chargeFraction = 0.0,
  }) {
    final rand = Random();

    // Base speed: power maps 1..10 -> 420..1100 px/s
    double speed = 420 + (power / 10) * 680;

    // Charge bonus (Finish Spike only): up to +35% speed at full charge.
    speed *= 1.0 + (0.35 * chargeFraction);

    // Accuracy -> max angle deviation in radians.
    // accuracy 10 => ~0 deviation; accuracy 1 => up to ~0.35 rad (~20deg).
    final maxDeviation = (1 - (accuracy / 10)) * 0.35;
    final deviation = (rand.nextDouble() * 2 - 1) * maxDeviation;
    // Full charge on a spike "locks in" the aim — no deviation.
    final effectiveDeviation = chargeFraction >= 1.0 ? 0.0 : deviation;

    final cosA = cos(effectiveDeviation);
    final sinA = sin(effectiveDeviation);
    final dir = aimDirection.normalized();
    final rotated = Vector2(
      dir.x * cosA - dir.y * sinA,
      dir.x * sinA + dir.y * cosA,
    );

    return rotated..scale(speed);
  }

  /// Called ONLY by `CollisionResolver` once it has decided the outcome of
  /// a ball/player contact. BallComponent itself no longer computes hit
  /// velocity — that logic now lives in CollisionResolver so timing
  /// quality and the spike-legality check can be factored in before the
  /// velocity formula runs. This method's job is just to apply the result
  /// and update bookkeeping (last toucher, in-play flag, touch count).
  void applyResolvedHit({required Vector2 velocity, required PlayerComponent hitter}) {
    this.velocity.setFrom(velocity);
    lastToucherId = hitter.playerId;
    lastToucherSide = hitter.side;
    _inPlay = true;

    game.registerTouch(hitter.playerId, hitter.side);
  }

  @override
  void onCollisionStart(Set<Vector2> points, PositionComponent other) {
    super.onCollisionStart(points, other);
    if (!_inPlay) return;

    if (other == court.netHitbox) {
      // Net touch: kill horizontal velocity and let it drop — classic
      // "into the net" fault feel.
      velocity.x = 0;
      velocity.y = velocity.y.abs() * 0.2;
    } else if (other is PlayerHitbox) {
      // Real contact — hand off to the collision resolution system, which
      // reads the player's ActionState/timing and the team's touch count
      // to decide the outcome. See collision_resolution_system.dart.
      CollisionResolver.resolve(ball: this, player: other.owner, game: game);
    }
  }

  void _checkOutOfBounds() {
    if (position.y >= CourtComponent.floorY) {
      final onHomeSide = court.isHomeSide(position.x);
      final side = onHomeSide ? TeamSide.home : TeamSide.away;
      _inPlay = false;
      game.ballLandedInCourt(side);
    } else if (position.x < 0 || position.x > kDesignWidth) {
      final side = lastToucherSide ?? TeamSide.home;
      _inPlay = false;
      game.ballLandedOutOfBounds(side);
    }
  }
}

/// Marker subclass so BallComponent's collision handler can distinguish
/// player hitboxes from court geometry without a runtime type check chain.
class PlayerHitbox extends RectangleHitbox {
  PlayerHitbox({required this.owner, super.position, super.size});
  final PlayerComponent owner;
}
