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
    // Floor
    final floorPaint = Paint()..color = const Color(0xFF16324A);
    canvas.drawRect(Rect.fromLTWH(0, floorY, kDesignWidth, 80), floorPaint);

    // Net
    final netPaint = Paint()..color = const Color(0xFFE8E8E8).withValues(alpha: 0.85);
    canvas.drawRect(
      Rect.fromLTWH(kDesignWidth / 2 - netThickness / 2, floorY - netHeight, netThickness, netHeight),
      netPaint,
    );

    // Center line marker
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(kDesignWidth / 2, floorY),
      Offset(kDesignWidth / 2, kDesignHeight),
      linePaint,
    );
  }

  bool isOverNet(double x) => (x - kDesignWidth / 2).abs() < netThickness;
  bool isHomeSide(double x) => x < kDesignWidth / 2;
}
