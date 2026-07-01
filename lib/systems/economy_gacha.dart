import 'dart:math';
import '../components/player_component.dart';
import '../persistence/persistence_service.dart';

/// -----------------------------------------------------------------------
/// ECONOMY & GACHA BALANCE  (answers request #9)
/// -----------------------------------------------------------------------

/// --- WIN-STREAK GOLD FORMULA ---
/// Design goals:
///  - Base reward per win should feel meaningful even at streak 0.
///  - Streak bonus should be front-loaded (streak 1->2 matters a lot,
///    streak 8->9 much less) so it rewards momentum without letting a
///    single very long streak trivialize the whole economy.
///  - Hard cap to keep whale/no-life farming from breaking balance.
///
/// Formula:  gold = base + floor(bonusPerWin * log2(streak + 1))
/// capped at `maxStreakGold`.
class EconomyFormulas {
  static const int baseWinGold = 40;
  static const double bonusPerWin = 22.0;
  static const int maxStreakGold = 220;

  static int goldForWin({required int winStreakAfterThisWin}) {
    final bonus = (bonusPerWin * log2(winStreakAfterThisWin + 1)).floor();
    return min(baseWinGold + bonus, maxStreakGold);
  }

  static double log2(num x) => log(x) / log(2);

  /// Losses still grant a small consolation amount so new/losing players
  /// aren't fully locked out of the gacha loop — standard retention lever.
  static const int consolationGoldOnLoss = 12;
}

/// --- GACHA RARITY TIERS ---
/// Design intent (per brief): favor ROLE units (Setter/Spiker/Blocker
/// specific characters) over generic flat "level-up" materials, since
/// role identity is the core fantasy (see GDD section 3) — a pull that
/// just gives a stat-stick would undercut that.
enum Rarity { common, rare, epic, legendary }

class GachaPool {
  static const Map<Rarity, double> baseWeights = {
    Rarity.common: 0.55,
    Rarity.rare: 0.30,
    Rarity.epic: 0.125,
    Rarity.legendary: 0.025,
  };

  /// Cost in gold per pull, single-pull vs 10-pull (with the standard
  /// "10-pull discount + guaranteed rare-or-better" gacha convention).
  static const int singlePullCost = 100;
  static const int tenPullCost = 900; // ~1 pull discount
  static const Rarity tenPullGuaranteedFloor = Rarity.rare;

  /// Of the gacha "slots," role-specific character units are weighted
  /// heavily over generic level-up shards, per design brief:
  ///   - 70% of any successful roll resolves to a ROLE CHARACTER
  ///   - 30% resolves to a generic material/shard
  /// This ratio is intentionally lopsided toward characters — the shard
  /// pool exists mainly as a "soft pity" filler, not the main event.
  static const double roleCharacterChance = 0.70;

  final Random _rand = Random();

  Rarity rollRarity() {
    final roll = _rand.nextDouble();
    double cumulative = 0;
    for (final entry in baseWeights.entries) {
      cumulative += entry.value;
      if (roll <= cumulative) return entry.key;
    }
    return Rarity.common;
  }

  /// Returns either a role-character id (favoring Setter/Spiker/Blocker
  /// pulls per the brief) or a generic shard id.
  GachaResult rollResult() {
    final rarity = rollRarity();
    final isRoleCharacter = _rand.nextDouble() < roleCharacterChance;

    if (isRoleCharacter) {
      final role = PlayerRole.values[_rand.nextInt(PlayerRole.values.length)];
      return GachaResult(
        rarity: rarity,
        isCharacter: true,
        role: role,
        id: '${role.name}_${rarity.name}_${_rand.nextInt(999)}',
      );
    }

    return GachaResult(
      rarity: rarity,
      isCharacter: false,
      role: null,
      id: 'shard_${rarity.name}',
    );
  }

  /// 10-pull with pity: re-rolls the lowest result up to `tenPullGuaranteedFloor`
  /// if none of the 10 met that bar, standard gacha player-goodwill mechanic.
  List<GachaResult> rollTenPull() {
    final results = List.generate(10, (_) => rollResult());
    final hasFloorOrBetter = results.any((r) => r.rarity.index >= tenPullGuaranteedFloor.index);
    if (!hasFloorOrBetter) {
      results[results.length - 1] = GachaResult(
        rarity: tenPullGuaranteedFloor,
        isCharacter: true,
        role: PlayerRole.values[_rand.nextInt(PlayerRole.values.length)],
        id: 'pity_guaranteed_${_rand.nextInt(999)}',
      );
    }
    return results;
  }
}

class GachaResult {
  GachaResult({required this.rarity, required this.isCharacter, required this.role, required this.id});
  final Rarity rarity;
  final bool isCharacter;
  final PlayerRole? role;
  final String id;
}

/// Ties gold rewards + gacha pulls to the persistence layer.
class EconomyController {
  EconomyController(this.persistence);
  final PersistenceService persistence;
  final GachaPool pool = GachaPool();

  Future<void> grantWinReward() async {
    final streak = persistence.winStreak; // already incremented by recordMatchResult
    final gold = EconomyFormulas.goldForWin(winStreakAfterThisWin: streak);
    await persistence.addCurrency(gold);
  }

  Future<void> grantLossConsolation() async {
    await persistence.addCurrency(EconomyFormulas.consolationGoldOnLoss);
  }

  Future<GachaResult?> singlePull() async {
    final ok = await persistence.spendCurrency(GachaPool.singlePullCost);
    if (!ok) return null;
    final result = pool.rollResult();
    if (result.isCharacter) await persistence.unlockCharacter(result.id);
    return result;
  }

  Future<List<GachaResult>?> tenPull() async {
    final ok = await persistence.spendCurrency(GachaPool.tenPullCost);
    if (!ok) return null;
    final results = pool.rollTenPull();
    for (final r in results) {
      if (r.isCharacter) await persistence.unlockCharacter(r.id);
    }
    return results;
  }
}
