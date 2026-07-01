import 'package:flame/game.dart';
import 'package:flame/camera.dart';

/// -----------------------------------------------------------------------
/// CAMERA / VIEWPORT CONFIG  (answers request #5)
/// -----------------------------------------------------------------------
/// The court is authored at a fixed logical resolution. We use
/// `Viewport.fixed` sized to that resolution so the 3v3 court composition
/// (net centered, 3 slots per side) never has to be recalculated per
/// device — Flame handles the letterboxing (black bars) for us on
/// mismatched aspect ratios.
///
/// Logical design resolution: 1280x720 (16:9). Most phones are taller
/// (e.g. 9:19.5), so in portrait we'll get top/bottom bars; that's fine —
/// volleyball reads better as a wide court anyway, so we lock landscape
/// in the OS manifest and let the fixed viewport do the rest.
/// -----------------------------------------------------------------------
const double kDesignWidth = 1280;
const double kDesignHeight = 720;

Future<void> configureCamera(FlameGame game) async {
  game.camera.viewport = FixedResolutionViewport(
    resolution: Vector2(kDesignWidth, kDesignHeight),
  );

  // Center the world on the court's midpoint (net position). CourtComponent
  // is authored so (kDesignWidth/2, kDesignHeight/2) sits exactly on the net.
  game.camera.viewfinder.position = Vector2(kDesignWidth / 2, kDesignHeight / 2);
  game.camera.viewfinder.anchor = Anchor.center;

  // Zoom stays at 1.0 baseline; JuiceEffects temporarily perturbs this
  // for camera-shake / punch-in on big hits (see juice/juice_effects.dart).
  game.camera.viewfinder.zoom = 1.0;
}

/// Helper for responsive UI overlays (touch-counter pips, score text) that
/// need to know safe letterbox-aware bounds rather than raw device size.
class SafeCourtBounds {
  static Vector2 get topLeft => Vector2.zero();
  static Vector2 get bottomRight => Vector2(kDesignWidth, kDesignHeight);
  static Vector2 get netPosition => Vector2(kDesignWidth / 2, kDesignHeight / 2);
}
