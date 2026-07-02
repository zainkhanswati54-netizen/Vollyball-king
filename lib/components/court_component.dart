import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/collisions.dart';
import 'package:flutter/material.dart';
import '../camera/camera_config.dart';

/// Static geometry the BallComponent collides against: floor (both sides),
/// the net, and out-of-bounds side walls. Kept as simple RectangleHitboxes
/// since court geometry never moves — cheapest possible collision shape.
class CourtComponent extends PositionComponent {
  late RectangleHitbox netHitbox;
  late RectangleHitbox homeFloor;
  late RectangleHitbox awayFloor;
  late RectangleHitbox leftWall;
  late RectangleHitbox rightWall;

  static const double floorY = kDesignHeight - 80;
  static const double netHeight = 160;
  static const double netThickness = 12;

  @override
  Future<void> onLoad() async {
    size = Vector2(kDesignWidth, kDesignHeight);

    netHitbox = RectangleHitbox(
      position: Vector2(kDesignWidth / 2 - netThickness / 2, floorY - netHeight),
      size: Vector2(netThickness, netHeight),
    )..isSolid = true;

    homeFloor = RectangleHitbox(
      position: Vector2(0, floorY),
      size: Vector2(kDesignWidth / 2, 4),
    )..isSolid = true;

    awayFloor = RectangleHitbox(
      position: Vector2(kDesignWidth / 2, floorY),
      size: Vector2(kDesignWidth / 2, 4),
    )..isSolid = true;

    leftWall = RectangleHitbox(position: Vector2(-20, 0), size: Vector2(20, kDesignHeight));
    rightWall = RectangleHitbox(position: Vector2(kDesignWidth, 0), size: Vector2(20, kDesignHeight));

    await addAll([netHitbox, homeFloor, awayFloor, leftWall, rightWall]);
  }

  @override
  void render(Canvas canvas) {
    _drawFloor(canvas);
    _drawBoundaryLines(canvas);
    _drawNet(canvas);
  }

  // -------------------------------------------------------------------
  // WOOD GYM FLOOR
  // -------------------------------------------------------------------
  void _drawFloor(Canvas canvas) {
    final floorRect = Rect.fromLTWH(0, floorY, kDesignWidth, kDesignHeight - floorY);

    // Base gradient: lighter "sheen" near the net, richer wood tone toward
    // the edges — reads as light bouncing off a polished gym floor.
    final woodGradient = ui.Gradient.linear(
      Offset(0, floorY),
      Offset(0, kDesignHeight),
      const [Color(0xFFC79A5C), Color(0xFFA97C43), Color(0xFF8C6432)],
      const [0.0, 0.55, 1.0],
    );
    canvas.drawRect(floorRect, Paint()..shader = woodGradient);

    // Plank lines: evenly spaced vertical strokes with slight alpha
    // variation so it doesn't look like a flat repeating pattern.
    final plankPaint = Paint()
      ..color = const Color(0xFF6E4A22).withValues(alpha: 0.35)
      ..strokeWidth = 1.4;
    const plankWidth = 42.0;
    for (double x = 0; x < kDesignWidth; x += plankWidth) {
      canvas.drawLine(Offset(x, floorY), Offset(x, kDesignHeight), plankPaint);
    }

    // A few horizontal seam breaks (staggered planks look) for texture.
    final seamPaint = Paint()
      ..color = const Color(0xFF6E4A22).withValues(alpha: 0.20)
      ..strokeWidth = 1.0;
    final seamY = floorY + (kDesignHeight - floorY) * 0.55;
    canvas.drawLine(Offset(0, seamY), Offset(kDesignWidth, seamY), seamPaint);

    // Subtle top highlight where the floor meets the "walls" of the court,
    // to give the floor a slight sense of depth/shine.
    canvas.drawRect(
      Rect.fromLTWH(0, floorY, kDesignWidth, 3),
      Paint()..color = Colors.white.withValues(alpha: 0.25),
    );
  }

  // -------------------------------------------------------------------
  // BOUNDARY / ATTACK LINES
  // -------------------------------------------------------------------
  void _drawBoundaryLines(Canvas canvas) {
    final solidLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 3;

    // Center line, directly under the net.
    canvas.drawLine(Offset(kDesignWidth / 2, floorY), Offset(kDesignWidth / 2, kDesignHeight), solidLine);

    // Attack lines (dashed) — the classic 3m line on each side of the net.
    final dashedLine = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 2;
    const attackLineOffset = 180.0;
    _drawDashedVerticalLine(canvas, kDesignWidth / 2 - attackLineOffset, floorY, kDesignHeight, dashedLine);
    _drawDashedVerticalLine(canvas, kDesignWidth / 2 + attackLineOffset, floorY, kDesignHeight, dashedLine);
  }

  void _drawDashedVerticalLine(Canvas canvas, double x, double top, double bottom, Paint paint) {
    const dashLength = 8.0;
    const gapLength = 6.0;
    double y = top;
    while (y < bottom) {
      final segmentEnd = min(y + dashLength, bottom);
      canvas.drawLine(Offset(x, y), Offset(x, segmentEnd), paint);
      y = segmentEnd + gapLength;
    }
  }

  // -------------------------------------------------------------------
  // NET — tape edges + crosshatch mesh pattern
  // -------------------------------------------------------------------
  void _drawNet(Canvas canvas) {
    final netRect = Rect.fromLTWH(
      kDesignWidth / 2 - netThickness / 2,
      floorY - netHeight,
      netThickness,
      netHeight,
    );

    // Faint fill so the mesh reads as "behind glass" rather than a void.
    canvas.drawRect(netRect, Paint()..color = Colors.white.withValues(alpha: 0.06));

    // Mesh pattern: simple crosshatch of thin diagonal lines clipped to
    // the net's rectangle — cheap to draw, reads as net weave at this
    // scale without needing an actual texture asset.
    final meshPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipRect(netRect);
    const meshSpacing = 10.0;
    for (double offset = -netHeight; offset < netThickness + netHeight; offset += meshSpacing) {
      canvas.drawLine(
        Offset(netRect.left + offset, netRect.top),
        Offset(netRect.left + offset - netHeight, netRect.bottom),
        meshPaint,
      );
      canvas.drawLine(
        Offset(netRect.left + offset, netRect.top),
        Offset(netRect.left + offset + netHeight, netRect.bottom),
        meshPaint,
      );
    }
    canvas.restore();

    // Top and bottom tape — crisp solid white bands, the part of a net
    // that actually reads clearly at a distance.
    final tapePaint = Paint()..color = Colors.white.withValues(alpha: 0.95);
    canvas.drawRect(Rect.fromLTWH(netRect.left - 4, netRect.top, netRect.width + 8, 6), tapePaint);
    canvas.drawRect(Rect.fromLTWH(netRect.left - 2, netRect.bottom - 3, netRect.width + 4, 4), tapePaint);
  }

  bool isOverNet(double x) => (x - kDesignWidth / 2).abs() < netThickness;
  bool isHomeSide(double x) => x < kDesignWidth / 2;
}
