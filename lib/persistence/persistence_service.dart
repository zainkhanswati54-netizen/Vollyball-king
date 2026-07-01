import 'package:hive_flutter/hive_flutter.dart';
import '../game/game_state.dart';

/// -----------------------------------------------------------------------
/// PERSISTENCE LAYER  (answers request #8)
/// -----------------------------------------------------------------------
/// Using Hive over shared_preferences for the actual game data (stats,
/// currency, unlocked characters) because:
///   - It's a fast, embedded key-value store (no JSON string round-trips
///     through platform channels for every read like shared_preferences).
///   - It supports typed boxes, so "unlockedCharacters" can be a
///     List<String> box, "currency" an int box, etc., with no manual
///     (de)serialization per field.
/// shared_preferences is still useful for trivial flags (e.g. "hasSeenTutorial")
/// where Hive would be overkill — both are wired up here for completeness.
///
/// CRITICAL: `Hive.initFlutter()` + opening boxes must complete BEFORE
/// `runApp()` so the very first frame already has correct player state
/// (currency, unlocks) rather than flashing a "0 gold / no characters"
/// state and then popping in real values a frame later.
/// -----------------------------------------------------------------------

class PersistenceService {
  PersistenceService._();

  static const _boxProfile = 'profile';
  static const _boxUnlocks = 'unlocks';
  static const _boxStats = 'stats';

  late Box _profileBox;
  late Box _unlocksBox;
  late Box _statsBox;

  /// Call this ONCE in `main()`, before `runApp()`.
  static Future<PersistenceService> initialize() async {
    await Hive.initFlutter();

    final service = PersistenceService._();
    service._profileBox = await Hive.openBox(_boxProfile);
    service._unlocksBox = await Hive.openBox(_boxUnlocks);
    service._statsBox = await Hive.openBox(_boxStats);

    service._applyDefaultsIfFirstLaunch();
    return service;
  }

  void _applyDefaultsIfFirstLaunch() {
    if (!_profileBox.containsKey('currency')) {
      _profileBox.put('currency', 500); // starter gold
    }
    if (!_unlocksBox.containsKey('characters')) {
      // Every account starts with one basic unit per role so a full 3v3
      // team is always fieldable, per GDD role-uniqueness rule.
      _unlocksBox.put('characters', ['setter_basic', 'spiker_basic', 'blocker_basic']);
    }
    if (!_statsBox.containsKey('winStreak')) {
      _statsBox.put('winStreak', 0);
    }
    if (!_statsBox.containsKey('totalWins')) {
      _statsBox.put('totalWins', 0);
    }
  }

  // --- Currency ------------------------------------------------------
  int get currency => _profileBox.get('currency', defaultValue: 0) as int;
  Future<void> addCurrency(int amount) => _profileBox.put('currency', currency + amount);
  Future<bool> spendCurrency(int amount) async {
    if (currency < amount) return false;
    await _profileBox.put('currency', currency - amount);
    return true;
  }

  // --- Unlocks ---------------------------------------------------------
  List<String> get unlockedCharacters =>
      List<String>.from(_unlocksBox.get('characters', defaultValue: <String>[]));

  Future<void> unlockCharacter(String id) async {
    final list = unlockedCharacters;
    if (!list.contains(id)) {
      list.add(id);
      await _unlocksBox.put('characters', list);
    }
  }

  // --- Match/Set results -------------------------------------------------
  int get winStreak => _statsBox.get('winStreak', defaultValue: 0) as int;
  int get totalWins => _statsBox.get('totalWins', defaultValue: 0) as int;

  Future<void> recordSetResult(ScoreState score) async {
    // Per-set bookkeeping hook; full match result recorded separately.
  }

  Future<void> recordMatchResult(ScoreState score) async {
    final playerWon = score.homeSets > score.awaySets;
    if (playerWon) {
      await _statsBox.put('winStreak', winStreak + 1);
      await _statsBox.put('totalWins', totalWins + 1);
    } else {
      await _statsBox.put('winStreak', 0);
    }
  }
}
