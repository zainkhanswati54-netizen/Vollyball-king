import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/spike_zone_game.dart';
import 'hud_data.dart';

/// -----------------------------------------------------------------------
/// HUD OVERLAY  (answers the Scoreboard & Touch HUD request)
/// -----------------------------------------------------------------------
/// A standard Flame overlay: a plain Flutter widget drawn on top of the
/// GameWidget, wired in via `overlayBuilderMap` in main.dart. It never
/// touches game internals directly — it only listens to `game.hud`, a
/// ValueNotifier<HudData> that SpikeZoneGame updates whenever score, touch
/// count, or phase changes (see `_syncHud()` in spike_zone_game.dart).
/// This keeps the HUD fully decoupled: SpikeZoneGame doesn't know Flutter
/// widgets exist, and this widget doesn't know how the game engine works.
/// -----------------------------------------------------------------------
class HudOverlay extends StatelessWidget {
  const HudOverlay({super.key, required this.game});
  final SpikeZoneGame game;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HudData>(
      valueListenable: game.hud,
      builder: (context, data, _) {
        return Stack(
          children: [
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ScoreBar(homeScore: data.homeScore, awayScore: data.awayScore, phase: data.phase),
                      const SizedBox(height: 8),
                      _TouchLights(touchCount: data.touchCount),
                    ],
                  ),
                ),
              ),
            ),
            if (data.message != null)
              Align(
                alignment: const Alignment(0, -0.15),
                child: _PointBanner(key: ValueKey(data.message), message: data.message!),
              ),
          ],
        );
      },
    );
  }
}

/// Center-screen banner announcing how the last point was won (or lost) —
/// e.g. "NET FAULT — YOU SCORE!". Uses its message text as a Key so
/// Flutter treats each new point as a distinct widget instance, which is
/// what makes the pop-in animation replay for every new point rather than
/// only playing once.
class _PointBanner extends StatelessWidget {
  const _PointBanner({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.6, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.homeScore, required this.awayScore, required this.phase});
  final int homeScore;
  final int awayScore;
  final MatchPhase phase;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TeamScore(label: 'YOU', score: homeScore, color: const Color(0xFF3DAAF2)),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('—', style: TextStyle(color: Colors.white54, fontSize: 20)),
          ),
          _TeamScore(label: 'CPU', score: awayScore, color: const Color(0xFFF2A73D)),
          const SizedBox(width: 18),
          Text(
            _phaseLabel(phase),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  String _phaseLabel(MatchPhase phase) {
    switch (phase) {
      case MatchPhase.serving:
        return 'TAP TO SERVE';
      case MatchPhase.rallying:
        return 'RALLY';
      case MatchPhase.awakening:
        return 'ZONE!';
      case MatchPhase.scoring:
        return 'POINT';
      case MatchPhase.setPoint:
        return 'SET';
      case MatchPhase.matchOver:
        return 'MATCH OVER';
    }
  }
}

class _TeamScore extends StatelessWidget {
  const _TeamScore({required this.label, required this.score, required this.color});
  final String label;
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        Text(
          '$score',
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

/// The "1-2-3 light" indicator — three dots that light up in sequence as
/// the current rally's touch count advances, and reset together the
/// moment `HudData.touchCount` drops back to 0 (new serve).
class _TouchLights extends StatelessWidget {
  const _TouchLights({required this.touchCount});
  final int touchCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final lit = i < touchCount;
          const litColor = Color(0xFF3DE0A0);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lit ? litColor : Colors.white24,
              boxShadow: lit
                  ? [BoxShadow(color: litColor.withValues(alpha: 0.65), blurRadius: 6, spreadRadius: 1)]
                  : null,
            ),
          );
        }),
      ),
    );
  }
}
