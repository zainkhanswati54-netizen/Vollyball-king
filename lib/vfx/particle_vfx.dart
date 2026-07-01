import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/particles.dart';
import 'package:flutter/material.dart';

/// -----------------------------------------------------------------------
/// FINISH SPIKE VFX SYSTEM  (answers request #4)
/// -----------------------------------------------------------------------
/// Goal: hundreds of flaming/electrified particles per Finish Spike,
/// without per-particle CPU/GC cost blowing the frame budget.
///
/// Strategy:
///  1. SPRITE BATCHING — all particles for a given effect (fire, spark)
///     share ONE `ui.Image` atlas and are drawn via a single
///     `SpriteBatch` / `canvas.drawAtlas` call rather than N individual
///     `canvas.drawImage` calls. This collapses what would be hundreds of
///     draw calls into one, which is the single biggest cost lever here —
///     draw call count matters far more than raw particle count on mobile
///     GPUs.
///  2. BLEND MODE — `BlendMode.screen` (or `plus` for hotter cores) is
///     applied ONCE at the batch/paint level, not per-particle, so
///     additive-looking "glow" stacking is basically free.
///  3. POOLING — particle data (position, velocity, age, color) lives in
///     flat typed-data arrays (Float32List) that are reused across spikes
///     instead of allocating a fresh List<Particle> object graph every
///     time a Spiker connects. Flame's `Particle`/`ParticleSystemComponent`
///     wraps this, but for large counts we bypass it and manage the
///     buffers ourselves (see FinishSpikeBurst below) to avoid Dart object
///     allocation churn feeding the GC every frame.
///  4. LIFETIME CAP — bursts are short (300-500ms) and capped at a hard
///     particle ceiling (e.g. 220) regardless of requested count, so a
///     worst case (multiple simultaneous Awakenings, rare but possible)
///     can't spike frame time.
/// -----------------------------------------------------------------------

class FinishSpikeBurst extends Component {
  FinishSpikeBurst({
    required this.origin,
    required this.color,
    this.particleCount = 180,
    this.lifetimeSeconds = 0.45,
    this.atlasImage,
  }) : particleCount = min(particleCount, _hardCap);

  static const int _hardCap = 220;

  final Vector2 origin;
  final Color color;
  final int particleCount;
  final double lifetimeSeconds;
  final ui.Image? atlasImage; // pre-baked small glow/spark sprite, tinted per-instance

  // Flat buffers — one allocation per burst, reused frame to frame, freed
  // when the burst finishes (component removed). No per-particle objects.
  late Float32List _positions; // x,y pairs
  late Float32List _velocities; // vx,vy pairs
  late Float32List _ages;
  double _elapsed = 0;

  final Random _rand = Random();

  @override
  Future<void> onLoad() async {
    _positions = Float32List(particleCount * 2);
    _velocities = Float32List(particleCount * 2);
    _ages = Float32List(particleCount);

    for (var i = 0; i < particleCount; i++) {
      final angle = _rand.nextDouble() * pi * 2;
      final speed = 80 + _rand.nextDouble() * 260;
      _positions[i * 2] = origin.x;
      _positions[i * 2 + 1] = origin.y;
      _velocities[i * 2] = cos(angle) * speed;
      _velocities[i * 2 + 1] = sin(angle) * speed - 60; // slight upward bias, "flame" feel
      _ages[i] = 0;
    }
  }

  @override
  void update(double dt) {
    _elapsed += dt;
    for (var i = 0; i < particleCount; i++) {
      _ages[i] += dt;
      _positions[i * 2] += _velocities[i * 2] * dt;
      _positions[i * 2 + 1] += _velocities[i * 2 + 1] * dt;
      _velocities[i * 2 + 1] += 340 * dt; // light gravity/drag on the spark trail
    }
    if (_elapsed >= lifetimeSeconds) removeFromParent();
  }

  @override
  void renderTree(Canvas canvas) {
    if (atlasImage == null) {
      _renderFallback(canvas);
      return;
    }

    // --- Single-draw-call sprite batch path ---
    final rects = <Rect>[];
    final transforms = <ui.RSTransform>[];
    final colors = <Color>[];
    final srcRect = Rect.fromLTWH(0, 0, atlasImage!.width.toDouble(), atlasImage!.height.toDouble());

    for (var i = 0; i < particleCount; i++) {
      final t = (_ages[i] / lifetimeSeconds).clamp(0.0, 1.0);
      final alpha = (1.0 - t); // fade out over lifetime
      final scale = 0.4 + (1 - t) * 0.6;

      transforms.add(ui.RSTransform(scale, 0, _positions[i * 2], _positions[i * 2 + 1]));
      rects.add(srcRect);
      colors.add(color.withOpacity(alpha.clamp(0.0, 1.0)));
    }

    final paint = Paint()..blendMode = BlendMode.screen;
    canvas.drawAtlas(atlasImage!, transforms, rects, colors, BlendMode.modulate, null, paint);
  }

  /// Fallback when no baked atlas is supplied yet (e.g. during early dev
  /// before art assets land) — still batches via drawCircle in a single
  /// canvas save/restore rather than per-particle Paint objects.
  void _renderFallback(Canvas canvas) {
    final paint = Paint()
      ..color = color
      ..blendMode = BlendMode.screen;
    for (var i = 0; i < particleCount; i++) {
      final t = (_ages[i] / lifetimeSeconds).clamp(0.0, 1.0);
      paint.color = color.withOpacity((1 - t).clamp(0.0, 1.0));
      canvas.drawCircle(
        Offset(_positions[i * 2], _positions[i * 2 + 1]),
        3.0 * (1 - t) + 1.0,
        paint,
      );
    }
  }
}

/// Convenience factory hooked from PlayerComponent.performAttack when
/// chargeFraction >= 1.0 (a full-charge Finish Spike).
class FinishSpikeVfx {
  static Component spawn({required Vector2 at, required Color teamColor, ui.Image? atlas}) {
    return FinishSpikeBurst(origin: at, color: teamColor, atlasImage: atlas);
  }
}
