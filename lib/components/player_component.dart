import 'dart:math';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'court_component.dart';
import 'ball_component.dart';
import '../game/game_state.dart';
import '../game/spike_zone_game.dart';
import '../systems/synergy_system.dart';
import '../systems/action_state.dart';

enum PlayerRole { setter, spiker, blocker }

/// Base (pre-synergy, pre-gacha-rarity) stats per GDD section 3.
class RoleStats {
  RoleStats({required this.power, required this.accuracy, required this.speed, required this.reach});
  int power;
  int accuracy;
  int speed;
  int reach;

  static RoleStats forRole(PlayerRole role) {
    switch (role) {
      case PlayerRole.setter:
        return RoleStats(power: 3, accuracy: 9, speed: 6, reach: 5);
      case PlayerRole.spiker:
        return RoleStats(power: 9, accuracy: 5, speed: 7, reach: 6);
      case PlayerRole.blocker:
        return RoleStats(power: 5, accuracy: 6, speed: 5, reach: 9);
    }
  }
}

/// -----------------------------------------------------------------------
/// PLAYER COMPONENT (touches on requests #3, #6, #7)
/// -----------------------------------------------------------------------
class PlayerComponent extends PositionComponent
    with HasGameReference<SpikeZoneGame>, HasActionState {
  PlayerComponent({
    required this.playerId,
    required this.role,
    required this.side,
    required this.court,
  })  : stats = RoleStats.forRole(role),
        super(size: Vector2(48, 96), anchor: Anchor.bottomCenter);

  final int playerId;
  final PlayerRole role;
  final TeamSide side;
  final CourtComponent court;
  final RoleStats stats;

  /// Charge fraction for the Spiker's Finish Spike (0..1). Unused by
  /// other roles but kept generic in case a role's kit expands later.
  double chargeFraction = 0.0;
  bool isCharging = false;

  /// Tension meter contribution tracked per-player for Awakening (GDD 5.2).
  double localTensionContribution = 0.0;

  late PlayerHitbox hitbox;

  /// Smooth movement target for tap input — set via `moveToward()`, consumed
  /// frame-by-frame in `update()` rather than snapping position instantly.
  /// This is what makes tap-to-move read as a dive/step rather than a
  /// teleport (see the "Tap Input Tuning" request).
  double? moveTargetX;

  @override
  Future<void> onLoad() async {
    // The COLLISION hitbox is intentionally much taller than the VISIBLE
    // sprite — it represents jump/reach range, not the character's static
    // silhouette. Without this, real contact (which only fires on genuine
    // Flame hitbox overlap, not on intent alone) could only ever happen in
    // the ~96px band right at floor level, meaning sets and spikes — which
    // happen well above head height — could never physically register.
    // This single change is what makes both human dig/set/spike attempts
    // AND AI interception actually work for balls in flight, not just
    // balls that have nearly landed.
    const reachPadding = 20.0; // extra width on each side, for dive forgiveness
    const reachHeight = 240.0; // extends detection well above head height

    hitbox = PlayerHitbox(
      owner: this,
      position: Vector2(-reachPadding, -reachHeight),
      size: Vector2(size.x + reachPadding * 2, size.y + reachHeight),
    );
    await add(hitbox);

    // Default facing: toward the net, so both teams start the rally
    // looking at each other instead of both defaulting to "facing right."
    facingRight = side == TeamSide.home;
    _lastX = position.x;

    // Apply Active Synergy Traits once the full team is assembled.
    // (Team is passed in via buildTeam below, then resolved together.)
  }

  /// Set a horizontal target for smooth, multi-frame movement — used by
  /// human tap input (move toward the ball's shadow) instead of snapping
  /// position instantly, which read as a teleport rather than a dive.
  void moveToward(double targetX) {
    moveTargetX = targetX;
  }

  void _updateMovement(double dt) {
    if (moveTargetX == null) return;
    final dx = moveTargetX! - position.x;
    if (dx.abs() < 2) {
      moveTargetX = null;
      return;
    }
    final speed = 170.0 + stats.speed * 22.0; // role Speed stat drives feel
    final step = dx.sign * min(dx.abs(), speed * dt);
    position.x += step;
  }

  /// Tracks movement direction so the sprite flips to face the way it's
  /// moving — a static default of "facing right" until the first move.
  bool facingRight = true;
  double _lastX = 0;

  @override
  void render(Canvas canvas) {
    canvas.save();

    // Flip horizontally around the component's own center when facing left.
    // This must happen before any drawing so every shape below flips with it.
    if (!facingRight) {
      canvas.translate(size.x, 0);
      canvas.scale(-1, 1);
    }

    _drawCharacter(canvas);

    canvas.restore();
  }

  void _drawCharacter(Canvas canvas) {
    final bodyColor = _roleColor();
    final outline = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final fill = Paint()..color = bodyColor;
    final shade = Paint()..color = bodyColor.withValues(alpha: 0.65);

    final w = size.x;
    final h = size.y;

    // Proportions (arcade-sprite style: slightly oversized head, compact
    // torso, simple limb shapes) — tuned for a 48x96 bounding box but
    // expressed as fractions so it scales if `size` ever changes.
    final headRadius = w * 0.26;
    final headCenter = Offset(w / 2, headRadius + 2);

    final torsoTop = headRadius * 2 + 2;
    final torsoHeight = h * 0.42;
    final torsoRect = Rect.fromLTWH(w * 0.22, torsoTop, w * 0.56, torsoHeight);
    final torsoRRect = RRect.fromRectAndRadius(torsoRect, Radius.circular(w * 0.14));

    final legTop = torsoTop + torsoHeight - 2;
    final legHeight = h - legTop - 2;
    final legWidth = w * 0.20;

    // Back leg (drawn first so the front leg overlaps it slightly — cheap
    // depth cue without real 3D).
    final backLeg = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.52, legTop, legWidth, legHeight),
      Radius.circular(legWidth * 0.4),
    );
    canvas.drawRRect(backLeg, shade);
    canvas.drawRRect(backLeg, outline);

    // Back arm — angled backward to suggest forward motion/reach.
    final backArmPath = Path()
      ..moveTo(w * 0.30, torsoTop + 6)
      ..lineTo(w * 0.06, torsoTop + torsoHeight * 0.55)
      ..lineTo(w * 0.14, torsoTop + torsoHeight * 0.7)
      ..lineTo(w * 0.34, torsoTop + 18)
      ..close();
    canvas.drawPath(backArmPath, shade);
    canvas.drawPath(backArmPath, outline);

    // Torso
    canvas.drawRRect(torsoRRect, fill);
    canvas.drawRRect(torsoRRect, outline);

    // Front leg
    final frontLeg = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.28, legTop, legWidth, legHeight),
      Radius.circular(legWidth * 0.4),
    );
    canvas.drawRRect(frontLeg, fill);
    canvas.drawRRect(frontLeg, outline);

    // Front arm — reaches slightly forward/up, reads well for a "ready
    // position" stance regardless of which action the player is in.
    final frontArmPath = Path()
      ..moveTo(w * 0.68, torsoTop + 6)
      ..lineTo(w * 0.92, torsoTop + torsoHeight * 0.35)
      ..lineTo(w * 0.84, torsoTop + torsoHeight * 0.5)
      ..lineTo(w * 0.66, torsoTop + 18)
      ..close();
    canvas.drawPath(frontArmPath, fill);
    canvas.drawPath(frontArmPath, outline);

    // Head
    canvas.drawCircle(headCenter, headRadius, fill);
    canvas.drawCircle(headCenter, headRadius, outline);

    // A simple role-marker chevron on the chest so the three roles stay
    // readable even before real jersey art exists.
    final markerPaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    final markerCenter = Offset(w / 2, torsoTop + torsoHeight * 0.4);
    canvas.drawCircle(markerCenter, w * 0.06, markerPaint);
  }

  Color _roleColor() {
    switch (role) {
      case PlayerRole.setter:
        return side == TeamSide.home ? const Color(0xFF3DAAF2) : const Color(0xFFF2A73D);
      case PlayerRole.spiker:
        return side == TeamSide.home ? const Color(0xFFE0473B) : const Color(0xFFB93DE0);
      case PlayerRole.blocker:
        return side == TeamSide.home ? const Color(0xFF3DE0A0) : const Color(0xFFE0DC3D);
    }
  }

  // --- Actions -----------------------------------------------------
  // These methods now express INTENT ONLY — they set the player's
  // ActionState and let CollisionResolver decide the actual outcome the
  // moment the ball physically contacts this player's hitbox. This is
  // what makes the collision system (not the input/AI layer) the single
  // source of truth for hit resolution.

  void beginDig() => startAction(ActionState.digging);
  void beginSet() => startAction(ActionState.setting);
  void beginAttack() => startAction(ActionState.spiking);
  void beginBlock() => startAction(ActionState.blocking);

  void startCharging() => isCharging = true;

  void updateCharge(double dt) {
    if (!isCharging || role != PlayerRole.spiker) return;
    chargeFraction = (chargeFraction + dt / 0.9).clamp(0.0, 1.0); // ~0.9s to full charge
  }

  @override
  void update(double dt) {
    super.update(dt);
    updateActionTimer(dt);
    updateCharge(dt);
    _updateMovement(dt);

    // Direction tracking for the sprite flip — only update facing when
    // there's meaningful horizontal movement, so standing still (e.g.
    // mid-action) doesn't cause flicker from tiny sub-pixel drift.
    final dx = position.x - _lastX;
    if (dx.abs() > 0.5) {
      facingRight = dx > 0;
    }
    _lastX = position.x;
  }

  /// Called by CollisionResolver once a touch is resolved — public so the
  /// resolver (a separate system, by design) can drive tension without
  /// PlayerComponent needing to know resolver internals.
  void addTension(double amount) {
    localTensionContribution += amount;
    if (localTensionContribution >= 1.0) {
      localTensionContribution = 0;
      game.triggerAwakening();
      if (role == PlayerRole.spiker) {
        chargeFraction = 0.0;
        isCharging = false;
      }
    }
  }

  // --- Team construction -------------------------------------------

  static List<PlayerComponent> buildTeam({required TeamSide side, required CourtComponent court}) {
    final baseId = side == TeamSide.home ? 0 : 100;
    final team = [
      PlayerComponent(playerId: baseId + 1, role: PlayerRole.setter, side: side, court: court),
      PlayerComponent(playerId: baseId + 2, role: PlayerRole.spiker, side: side, court: court),
      PlayerComponent(playerId: baseId + 3, role: PlayerRole.blocker, side: side, court: court),
    ];

    // Position them evenly on their half (Front/Mid/Back per GDD).
    final xs = side == TeamSide.home ? [180.0, 340.0, 500.0] : [780.0, 940.0, 1100.0];
    for (var i = 0; i < team.length; i++) {
      team[i].position = Vector2(xs[i], CourtComponent.floorY);
    }

    // Resolve Active Synergy Traits across the assembled team (request #7).
    SynergySystem.applyTeamSynergies(team);

    return team;
  }
}
