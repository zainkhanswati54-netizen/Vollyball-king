import '../game/game_state.dart';

/// Immutable snapshot of everything the HUD overlay needs to redraw.
/// Kept deliberately tiny and separate from SpikeZoneGame itself so the
/// Flutter widget layer never has to reach into game internals — it only
/// ever sees this plain data object via a ValueNotifier.
class HudData {
  const HudData({
    required this.homeScore,
    required this.awayScore,
    required this.touchCount,
    required this.phase,
    this.message,
  });

  final int homeScore;
  final int awayScore;
  final int touchCount;
  final MatchPhase phase;

  /// Transient reason + outcome text for the most recent point (e.g.
  /// "NET FAULT — YOU SCORE!"), shown while `phase` is Scoring. Null once
  /// the next serve begins.
  final String? message;

  static const initial = HudData(
    homeScore: 0,
    awayScore: 0,
    touchCount: 0,
    phase: MatchPhase.serving,
  );
}
