import '../components/player_component.dart';

/// -----------------------------------------------------------------------
/// ACTIVE SYNERGY TRAITS  (answers request #7)
/// -----------------------------------------------------------------------
/// A trait is a data-driven rule: "if roles A and B are both present on a
/// team (optionally from specific character IDs, for gacha specificity),
/// apply buff X to role B."
///
/// This is intentionally decoupled from PlayerComponent — traits are
/// resolved once, at team-assembly time, by mutating RoleStats directly.
/// That keeps the per-frame hot path (BallComponent.computeHitVelocity)
/// completely unaware that synergies exist; it just reads final stats.
/// -----------------------------------------------------------------------

enum StatKind { power, accuracy, speed, reach }

class SynergyTrait {
  const SynergyTrait({
    required this.name,
    required this.requiredRoles,
    required this.buffedRole,
    required this.stat,
    required this.percentBonus,
  });

  final String name;
  final Set<PlayerRole> requiredRoles; // roles that must ALL be present
  final PlayerRole buffedRole; // which role's stat gets buffed
  final StatKind stat;
  final double percentBonus; // e.g. 0.10 = +10%

  bool isSatisfiedBy(Set<PlayerRole> teamRoles) => requiredRoles.every(teamRoles.contains);
}

class SynergySystem {
  /// Example baseline trait roster. In production these would likely be
  /// loaded from JSON/remote config so they can be tuned/expanded without
  /// a client release, and each character (gacha unit) could carry its own
  /// bonus trait IDs — this class only needs the *resolution* logic below
  /// to stay stable.
  static const List<SynergyTrait> traitPool = [
    SynergyTrait(
      name: 'Perfect Set',
      requiredRoles: {PlayerRole.setter, PlayerRole.spiker},
      buffedRole: PlayerRole.spiker,
      stat: StatKind.accuracy,
      percentBonus: 0.10,
    ),
    SynergyTrait(
      name: 'Iron Wall',
      requiredRoles: {PlayerRole.blocker, PlayerRole.setter},
      buffedRole: PlayerRole.blocker,
      stat: StatKind.reach,
      percentBonus: 0.08,
    ),
    SynergyTrait(
      name: 'Fast Break',
      requiredRoles: {PlayerRole.setter, PlayerRole.spiker, PlayerRole.blocker},
      buffedRole: PlayerRole.spiker,
      stat: StatKind.speed,
      percentBonus: 0.12,
    ),
  ];

  static void applyTeamSynergies(List<PlayerComponent> team) {
    final rolesPresent = team.map((p) => p.role).toSet();

    for (final trait in traitPool) {
      if (!trait.isSatisfiedBy(rolesPresent)) continue;

      for (final player in team.where((p) => p.role == trait.buffedRole)) {
        _applyBuff(player, trait);
      }
    }
  }

  static void _applyBuff(PlayerComponent player, SynergyTrait trait) {
    final stats = player.stats;
    switch (trait.stat) {
      case StatKind.power:
        stats.power = (stats.power * (1 + trait.percentBonus)).round();
        break;
      case StatKind.accuracy:
        stats.accuracy = (stats.accuracy * (1 + trait.percentBonus)).round();
        break;
      case StatKind.speed:
        stats.speed = (stats.speed * (1 + trait.percentBonus)).round();
        break;
      case StatKind.reach:
        stats.reach = (stats.reach * (1 + trait.percentBonus)).round();
        break;
    }
  }
}
