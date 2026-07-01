import 'package:flutter_test/flutter_test.dart';
import 'package:spike_zone/game/game_state.dart';
import 'package:spike_zone/systems/economy_gacha.dart';

/// -----------------------------------------------------------------------
/// SMOKE TESTS
/// -----------------------------------------------------------------------
/// These deliberately test pure game-logic classes (ScoreState, TouchState,
/// EconomyFormulas) rather than pumping the full Flame GameWidget. Widget-
/// level/golden tests for the actual rendered game are a good follow-up
/// once art assets and a font are in place — testing a Flame game's canvas
/// output needs real assets loaded, which isn't set up in this scaffold
/// yet (see README "Known caveats").
/// -----------------------------------------------------------------------
void main() {
  group('TouchState', () {
    test('allows up to 3 legal touches', () {
      final touch = TouchState();
      expect(touch.registerTouch(1, TeamSide.home), isTrue);
      expect(touch.registerTouch(2, TeamSide.home), isTrue);
      expect(touch.registerTouch(3, TeamSide.home), isTrue);
      expect(touch.touchCount, 3);
    });

    test('rejects the same player touching twice in a row', () {
      final touch = TouchState();
      touch.registerTouch(1, TeamSide.home);
      final legal = touch.registerTouch(1, TeamSide.home);
      expect(legal, isFalse);
    });

    test('a 4th touch is a fault', () {
      final touch = TouchState();
      touch.registerTouch(1, TeamSide.home);
      touch.registerTouch(2, TeamSide.home);
      touch.registerTouch(3, TeamSide.home);
      touch.registerTouch(1, TeamSide.home); // different player than touch 3, still a 4th touch
      expect(touch.isFault, isTrue);
    });

    test('reset clears touch count and last toucher', () {
      final touch = TouchState();
      touch.registerTouch(1, TeamSide.home);
      touch.reset();
      expect(touch.touchCount, 0);
      expect(touch.lastToucherId, isNull);
    });
  });

  group('ScoreState', () {
    test('set is not over below 15 points', () {
      final score = ScoreState()
        ..homePoints = 10
        ..awayPoints = 8;
      expect(score.setIsOver(), isFalse);
    });

    test('set is over at 15 with a 2-point lead', () {
      final score = ScoreState()
        ..homePoints = 15
        ..awayPoints = 12;
      expect(score.setIsOver(), isTrue);
    });

    test('set is NOT over at 15 with only a 1-point lead (deuce rule)', () {
      final score = ScoreState()
        ..homePoints = 15
        ..awayPoints = 14;
      expect(score.setIsOver(), isFalse);
    });

    test('point cap ends the set regardless of margin', () {
      final score = ScoreState()
        ..homePoints = 21
        ..awayPoints = 20;
      expect(score.setIsOver(), isTrue);
    });

    test('match is over once a team reaches 2 sets', () {
      final score = ScoreState()..homeSets = 2;
      expect(score.matchIsOver(), isTrue);
    });
  });

  group('EconomyFormulas', () {
    test('gold increases with win streak but never exceeds the cap', () {
      final low = EconomyFormulas.goldForWin(winStreakAfterThisWin: 1);
      final high = EconomyFormulas.goldForWin(winStreakAfterThisWin: 50);
      expect(high, greaterThan(low));
      expect(high, lessThanOrEqualTo(EconomyFormulas.maxStreakGold));
    });

    test('base win gold is always at least the configured minimum', () {
      final gold = EconomyFormulas.goldForWin(winStreakAfterThisWin: 0);
      expect(gold, greaterThanOrEqualTo(EconomyFormulas.baseWinGold));
    });
  });
}
