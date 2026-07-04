import 'dart:async';
import 'dart:ui';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flame/effects.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/animation.dart' show Curves;

import 'game_state.dart';
import '../components/ball_component.dart';
import '../components/player_component.dart';
import '../components/court_component.dart';
import '../ai/ai_controller.dart';
import '../juice/juice_effects.dart';
import '../camera/camera_config.dart';
import '../persistence/persistence_service.dart';
import '../ui/hud_data.dart';
import '../systems/action_state.dart';

class SpikeZoneGame extends FlameGame with HasCollisionDetection, TapCallbacks {
  SpikeZoneGame({required this.persistence});

  final PersistenceService persistence;

  // --- Core state ---
  MatchPhase phase = MatchPhase.serving;
  final TouchState touch = TouchState();
  final ScoreState score = ScoreState();
  TeamSide serving = TeamSide.home;

  // --- Time-scale support for Awakening (Zone Perception) ---
  double _timeScale = 1.0;
  double get timeScale => _timeScale;

  // --- Entities ---
  late BallComponent ball;
  final List<PlayerComponent> homeTeam = [];
  final List<PlayerComponent> awayTeam = [];
  late AIController aiController;
  late JuiceEffects juice;

  final ValueNotifier<HudData> hud = ValueNotifier(HudData.initial);

  double _phaseTimer = 0;

  @override
  Color backgroundColor() => const Color(0xFF0B1622);

  @override
  Future<void> onLoad() async {
    await configureCamera(this);

    final court = CourtComponent();
    await add(court);

    ball = BallComponent(court: court);
    await add(ball);

    homeTeam.addAll(PlayerComponent.buildTeam(side: TeamSide.home, court: court));
    awayTeam.addAll(PlayerComponent.buildTeam(side: TeamSide.away, court: court));
    await addAll([...homeTeam, ...awayTeam]);

    aiController = AIController(team: awayTeam, ball: ball, game: this);
    juice = JuiceEffects(game: this);

    _enterPhase(MatchPhase.serving);
  }

  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);

    if (kDebugMode) {
      debugPrint('[SpikeZoneGame] onTapDown at ${event.localPosition}, phase=$phase');
    }

    if (phase == MatchPhase.serving) {
      _launchServeFromTap();
      return;
    }
    if (phase != MatchPhase.rallying && phase != MatchPhase.awakening) return;

    final isLeftZone = event.localPosition.x < size.x / 2;
    if (isLeftZone) {
      _handleMoveOrDive();
    } else {
      _handleJumpOrSpike();
    }
  }

  void _launchServeFromTap() {
    final dir = Vector2(serving == TeamSide.home ? 1 : -1, -1.1);
    ball.launchServe(dir, 640);
    _enterPhase(MatchPhase.rallying);
  }

  PlayerComponent? _nextEligibleHumanPlayer() {
    final candidates = homeTeam.where((p) => p.playerId != ball.lastToucherId).toList();
    if (candidates.isEmpty) return null;
    candidates.sort(
      (a, b) => (a.position.x - ball.position.x).abs().compareTo((b.position.x - ball.position.x).abs()),
    );
    return candidates.first;
  }

  void _handleMoveOrDive() {
    final player = _nextEligibleHumanPlayer();
    if (player == null) return;
    if (player.currentAction != ActionState.idle) return;

    player.moveToward(ball.position.x);
    player.beginDig();
  }

  void _handleJumpOrSpike() {
    final player = _nextEligibleHumanPlayer();
    if (player == null) return;
    if (player.currentAction != ActionState.idle) return;

    player.add(
      MoveByEffect(
        Vector2(0, -18),
        EffectController(duration: 0.16, reverseDuration: 0.16, curve: Curves.easeOut),
      ),
    );

    player.beginAttack();
  }

  @override
  void update(double dt) {
    final worldDt = dt * _timeScale;

    super.update(dt);
    aiController.update(worldDt, phase);

    _phaseTimer += dt;

    switch (phase) {
      case MatchPhase.serving:
        _updateServing(worldDt);
        break;
      case MatchPhase.rallying:
        _updateRallying(worldDt);
        break;
      case MatchPhase.awakening:
        _updateAwakening(worldDt);
        break;
      case MatchPhase.scoring:
        _updateScoring(worldDt);
        break;
      case MatchPhase.setPoint:
        _updateSetPoint(worldDt);
        break;
      case MatchPhase.matchOver:
        break;
    }
  }

  void _enterPhase(MatchPhase next) {
    phase = next;
    _phaseTimer = 0;
    switch (next) {
      case MatchPhase.serving:
        touch.reset();
        ball.resetForServe(serving);
        break;
      case MatchPhase.rallying:
        break;
      case MatchPhase.awakening:
        _timeScale = 0.18;
        juice.onAwakeningEnter();
        break;
      case MatchPhase.scoring:
        _timeScale = 1.0;
        break;
      case MatchPhase.setPoint:
        persistence.recordSetResult(score);
        break;
      case MatchPhase.matchOver:
        persistence.recordMatchResult(score);
        break;
    }
    _syncHud();
  }

  void _updateServing(double dt) {}

  void _updateRallying(double dt) {
    if (touch.isFault) {
      _awardPoint(touch.possessingTeam == TeamSide.home ? TeamSide.away : TeamSide.home);
      return;
    }
  }

  void _updateAwakening(double dt) {
    if (_phaseTimer > 2.2) {
      _timeScale = 1.0;
      _enterPhase(MatchPhase.rallying);
      juice.hitStop(durationMs: 90);
    }
  }

  void _updateScoring(double dt) {
    if (_phaseTimer > 1.2) {
      if (score.setIsOver()) {
        _enterPhase(MatchPhase.setPoint);
      } else {
        serving = touch.possessingTeam ?? serving;
        _enterPhase(MatchPhase.serving);
      }
    }
  }

  void _updateSetPoint(double dt) {
    if (_phaseTimer > 3.0) {
      if (score.matchIsOver()) {
        _enterPhase(MatchPhase.matchOver);
      } else {
        _enterPhase(MatchPhase.serving);
      }
    }
  }

  void registerTouch(int playerId, TeamSide side) {
    if (phase != MatchPhase.rallying && phase != MatchPhase.awakening) return;
    final legal = touch.registerTouch(playerId, side);
    if (!legal) {
      _awardPoint(side == TeamSide.home ? TeamSide.away : TeamSide.home);
      return;
    }
    _syncHud();
  }

  void _syncHud() {
    hud.value = HudData(
      homeScore: score.homePoints,
      awayScore: score.awayPoints,
      touchCount: touch.touchCount,
      phase: phase,
    );
  }

  void triggerAwakening() {
    if (phase == MatchPhase.rallying) {
      _enterPhase(MatchPhase.awakening);
    }
  }

  void _awardPoint(TeamSide winner) {
    if (winner == TeamSide.home) {
      score.homePoints++;
    } else {
      score.awayPoints++;
    }
    juice.onPointScored(winner);
    _enterPhase(MatchPhase.scoring);
  }

  void ballLandedOutOfBounds(TeamSide lastToTouch) {
    _awardPoint(lastToTouch == TeamSide.home ? TeamSide.away : TeamSide.home);
  }

  void ballLandedInCourt(TeamSide courtOwner) {
    _awardPoint(courtOwner == TeamSide.home ? TeamSide.away : TeamSide.home);
  }
}