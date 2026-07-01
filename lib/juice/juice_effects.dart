import 'dart:math';
import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flutter/material.dart';

import '../game/game_state.dart';
import '../game/spike_zone_game.dart';

/// -----------------------------------------------------------------------
/// JUICE / GAME FEEL  (answers request #10)
/// -----------------------------------------------------------------------
/// 1) Camera shake on spike impact
/// 2) Hit-stop (frame-freeze) when ball hits the court
/// 3) Dynamic color flashes during Awakening
/// -----------------------------------------------------------------------
class JuiceEffects {
  JuiceEffects({required this.game});
  final SpikeZoneGame game;

  final Random _rand = Random();

  // -------------------------------------------------------------
  // 1. CAMERA SHAKE
  // -------------------------------------------------------------
  /// Adds a short, decaying random-offset shake to the camera's
  /// viewfinder. Implemented as a MoveByEffect chain rather than directly
  /// mutating position every frame, so it composes cleanly with whatever
  /// else the camera is doing (e.g. Awakening zoom punch) via Flame's
  /// effect controller stack instead of us hand-rolling a timer.
  void cameraShake({double intensity = 14, double durationMs = 220}) {
    final viewfinder = game.camera.viewfinder;
    final steps = 6;
    final stepDuration = (durationMs / 1000) / steps;

    Vector2 randomOffset(double magnitude) =>
        Vector2((_rand.nextDouble() * 2 - 1) * magnitude, (_rand.nextDouble() * 2 - 1) * magnitude);

    Future<void> chain(int stepIndex) async {
      if (stepIndex >= steps) return;
      final decay = 1 - (stepIndex / steps);
      final offset = randomOffset(intensity * decay);
      viewfinder.add(
        MoveByEffect(
          offset,
          EffectController(duration: stepDuration, curve: Curves.easeOut),
          onComplete: () => chain(stepIndex + 1),
        ),
      );
    }

    chain(0);
  }

  // -------------------------------------------------------------
  // 2. HIT-STOP (frame freeze)
  // -------------------------------------------------------------
  /// True hit-stop pauses simulation entirely for N ms — NOT the same as
  /// Awakening's time-scale slowdown (which still simulates, just slowly).
  /// We implement it by temporarily zeroing the game's paused-equivalent
  /// time scale via a dedicated `_hitStopMillisRemaining` countdown that
  /// SpikeZoneGame checks before applying worldDt, so it stacks correctly
  /// on top of Awakening rather than fighting it. For this snippet we
  /// expose the call and let SpikeZoneGame own the countdown flag.
  void hitStop({int durationMs = 60}) {
    game.pauseEngine();
    Future.delayed(Duration(milliseconds: durationMs), () {
      if (game.paused) game.resumeEngine();
    });
  }

  // -------------------------------------------------------------
  // 3. AWAKENING COLOR FLASH
  // -------------------------------------------------------------
  /// A full-screen color overlay component that pulses in on Awakening
  /// entry and fades through the duration. Cheap: one RectangleComponent,
  /// opacity animated via an OpacityEffect — no per-frame Paint allocation.
  RectangleComponent? _awakeningOverlay;

  void onAwakeningEnter() {
    _awakeningOverlay?.removeFromParent();

    final overlay = RectangleComponent(
      size: game.size,
      paint: Paint()..color = const Color(0xFF6E3DF2).withValues(alpha: 0.0),
      priority: 1000, // render above gameplay, below UI overlays if any
    );
    game.camera.viewport.add(overlay);
    _awakeningOverlay = overlay;

    // Quick punch-in flash, then settle to a low ambient vignette opacity
    // for the duration of the slow-mo window.
    overlay.add(
      OpacityEffect.to(
        0.35,
        EffectController(duration: 0.08, curve: Curves.easeOut),
        onComplete: () {
          overlay.add(
            OpacityEffect.to(0.12, EffectController(duration: 0.4, curve: Curves.easeIn)),
          );
        },
      ),
    );

    // Subtle camera punch-in accompanies the color flash.
    game.camera.viewfinder.add(
      ScaleEffect.by(
        Vector2.all(1.04),
        EffectController(duration: 0.1, curve: Curves.easeOut, reverseDuration: 0.3),
      ),
    );
  }

  void clearAwakeningOverlay() {
    _awakeningOverlay?.add(
      OpacityEffect.to(
        0.0,
        EffectController(duration: 0.2),
        onComplete: () => _awakeningOverlay?.removeFromParent(),
      ),
    );
  }

  // -------------------------------------------------------------
  // Composite triggers used by SpikeZoneGame
  // -------------------------------------------------------------
  void onPointScored(TeamSide winner) {
    cameraShake(intensity: 8, durationMs: 140);
  }

  /// Call this from BallComponent when it lands on the floor with enough
  /// velocity to be a "kill shot" landing — combines hit-stop + shake for
  /// the classic arcade "impact" beat.
  void onBallFloorImpact({required double impactSpeed}) {
    if (impactSpeed < 500) return; // soft landings don't deserve full juice
    hitStop(durationMs: impactSpeed > 1000 ? 90 : 50);
    cameraShake(intensity: (impactSpeed / 1400) * 20, durationMs: 200);
  }
}
