import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import 'court_component.dart';
import 'ball_component.dart';
import '../game/game_state.dart';
import '../game/spike_zone_game.dart';
import '../systems/synergy_system.dart';

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
class PlayerComponent extends PositionComponent with HasGameReference<SpikeZoneGame> {
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

  @override
  Future<void> onLoad() async {
    hitbox = PlayerHitbox(owner: this, size: size);
    await add(hitbox);

    // Apply Active Synergy Traits once the full team is assembled.
    // (Team is passed in via buildTeam below, then resolved together.)
  }

  @override
  void render(Canvas canvas) {
    final paint = Paint()..color = _roleColor();
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, -size.y, size.x, size.y), const Radius.circular(8)),
      paint,
    );
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

  void performDig(BallComponent ball, Vector2 aimDirection) {
    ball.receiveHit(hitter: this, aimDirection: aimDirection);
    _accrueTension(0.08);
  }

  void performSet(BallComponent ball, Vector2 aimDirection) {
    // Setter's "Dime Set" — Accuracy stat already narrows deviation via
    // BallComponent.computeHitVelocity, no extra logic needed here beyond
    // giving the player an explicit aim vector instead of nearest-teammate
    // auto-targeting.
    ball.receiveHit(hitter: this, aimDirection: aimDirection);
    _accrueTension(0.10);
  }

  void performAttack(BallComponent ball, Vector2 aimDirection) {
    ball.receiveHit(hitter: this, aimDirection: aimDirection, chargeFraction: chargeFraction);
    if (chargeFraction >= 1.0) {
      _accrueTension(0.6); // large gain, per GDD 5.2
    } else {
      _accrueTension(0.15);
    }
    chargeFraction = 0.0;
    isCharging = false;
  }

  void performBlock(BallComponent ball, Vector2 aimDirection) {
    ball.receiveHit(hitter: this, aimDirection: aimDirection);
    _accrueTension(0.25); // blocks feed tension too — defense is rewarded
  }

  void startCharging() => isCharging = true;

  void updateCharge(double dt) {
    if (!isCharging || role != PlayerRole.spiker) return;
    chargeFraction = (chargeFraction + dt / 0.9).clamp(0.0, 1.0); // ~0.9s to full charge
  }

  void _accrueTension(double amount) {
    localTensionContribution += amount;
    if (localTensionContribution >= 1.0) {
      localTensionContribution = 0;
      game.triggerAwakening();
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
