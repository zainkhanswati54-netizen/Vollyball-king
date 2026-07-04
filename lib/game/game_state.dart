/// -----------------------------------------------------------------------
/// GAME STATE MACHINE
/// -----------------------------------------------------------------------
/// Answers request #2: "How should I architect the game loop to manage
/// states (Serving, Rallying, Scoring) while ensuring 60FPS on mobile?"
///
/// Design choice: a lightweight, allocation-free enum-driven state machine
/// rather than a heavy FSM package. Each state has explicit enter/update/exit
/// hooks. This keeps per-frame logic branchless-ish (a single switch) and
/// avoids GC churn from creating state objects every frame, which matters
/// for hitting stable 60fps on mid-range Android hardware.
/// -----------------------------------------------------------------------

enum MatchPhase {
  serving, // Ball is being placed for serve, input locked to server
  rallying, // Active play: 1-2-3 touch logic, physics, AI all running
  awakening, // Zone Perception slow-mo window (sub-state of a rally)
  scoring, // Point resolved, brief pause + UI feedback before next serve
  setPoint, // Set won, longer pause + score screen
  matchOver,
}

/// Which team currently has the serve / is attacking, used by both the
/// touch-counter UI and the AI controller.
enum TeamSide { home, away }

class TouchState {
  TeamSide? possessingTeam;
  int touchCount = 0; // 0..3
  int? lastToucherId; // enforce "no consecutive touch by same player"

  bool get isFault => touchCount > 3;

  void reset() {
    possessingTeam = null;
    touchCount = 0;
    lastToucherId = null;
  }

  /// Returns false (and should trigger a fault) if the same player tries
  /// to touch twice in a row.
  ///
  /// IMPORTANT: each team gets its OWN fresh 1-2-3 sequence. Previously
  /// this counter just climbed for the whole rally regardless of which
  /// side was touching, which meant the receiving team's very first touch
  /// after the ball crossed the net could already read as touch "4" and
  /// wrongly fault them. Detecting a side change and resetting here is
  /// what makes `touchCount` actually mean "this team's touch count,"
  /// matching both the HUD's 1-2-3 lights and the collision resolver's
  /// Receive/Set/Spike sequencing.
  bool registerTouch(int playerId, TeamSide side) {
    if (playerId == lastToucherId) return false;

    if (side != possessingTeam) {
      touchCount = 0;
      lastToucherId = null;
    }

    possessingTeam = side;
    touchCount++;
    lastToucherId = playerId;
    return touchCount <= 3;
  }
}

class ScoreState {
  int homeSets = 0;
  int awaySets = 0;
  int homePoints = 0;
  int awayPoints = 0;

  static const int pointsToWinSet = 15;
  static const int pointCap = 21;

  bool setIsOver() {
    final diff = (homePoints - awayPoints).abs();
    if (homePoints >= pointsToWinSet && diff >= 2) return true;
    if (awayPoints >= pointsToWinSet && diff >= 2) return true;
    if (homePoints >= pointCap || awayPoints >= pointCap) return true;
    return false;
  }

  bool matchIsOver() => homeSets == 2 || awaySets == 2;
}
