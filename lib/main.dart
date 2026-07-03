import 'package:flutter/material.dart';
import 'package:flame/game.dart';

import 'persistence/persistence_service.dart';
import 'game/spike_zone_game.dart';
import 'ui/hud_overlay.dart';

/// -----------------------------------------------------------------------
/// APP ENTRY POINT  (answers request #8)
/// -----------------------------------------------------------------------
/// `PersistenceService.initialize()` fully opens all Hive boxes and seeds
/// first-launch defaults BEFORE `runApp()` is called. This guarantees the
/// very first widget tree build already has correct currency/unlock state
/// — no loading spinner, no "0 gold" flash-then-correct-value pop-in.
/// -----------------------------------------------------------------------
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final persistence = await PersistenceService.initialize();

  runApp(SpikeZoneApp(persistence: persistence));
}

class SpikeZoneApp extends StatelessWidget {
  const SpikeZoneApp({super.key, required this.persistence});
  final PersistenceService persistence;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spike Zone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        body: GameWidget<SpikeZoneGame>(
          game: SpikeZoneGame(persistence: persistence),
          overlayBuilderMap: {
            'hud': (context, game) => HudOverlay(game: game),
          },
          initialActiveOverlays: const ['hud'],
        ),
      ),
    );
  }
}
