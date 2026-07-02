import 'package:flame/components.dart';

/// -----------------------------------------------------------------------
/// ACTION STATE  — what a player is *currently attempting* to do to the
/// ball, independent of whether contact has happened yet.
/// -----------------------------------------------------------------------
/// This is intentionally decoupled from `MatchPhase`/`TouchState` (which
/// track the RALLY's state) — `ActionState` tracks the INDIVIDUAL PLAYER's
/// state, i.e. "what animation/input are they committed to right now."
/// The collision resolver reads both: the player's ActionState answers
/// "what did they intend," and TouchState answers "is that intent legal
/// right now" (see CollisionResolver's spike-eligibility check).
enum ActionState { idle, digging, setting, spiking, blocking }

enum TimingQuality { perfect, good, late }

/// Per-action timing windows, in seconds since the action was started via
/// `startAction()`. Contact inside `perfect` gets the tightest aim cone
/// and a speed bonus; inside `good` is a normal, reliable touch; beyond
/// `good` (but the action is still active) is a sloppy "late" touch with
/// wide deviation and reduced power — still a legal touch, just a worse one.
class ActionTimingWindow {
  const ActionTimingWindow({required this.perfectSeconds, required this.goodSeconds});
  final double perfectSeconds;
  final double goodSeconds;

  static const Map<ActionState, ActionTimingWindow> byAction = {
    ActionState.digging: ActionTimingWindow(perfectSeconds: 0.06, goodSeconds: 0.18),
    ActionState.setting: ActionTimingWindow(perfectSeconds: 0.05, goodSeconds: 0.15),
    ActionState.spiking: ActionTimingWindow(perfectSeconds: 0.07, goodSeconds: 0.16),
    ActionState.blocking: ActionTimingWindow(perfectSeconds: 0.05, goodSeconds: 0.14),
  };
}

/// Mixin any PositionComponent can use to gain a lightweight action/timing
/// state machine, without pulling in the full CollisionResolver. Kept
/// generic (not PlayerComponent-specific) in case other entities — a
/// future "libero" role, a training-mode dummy, etc. — need the same
/// timing-window concept later.
mixin HasActionState on PositionComponent {
  ActionState currentAction = ActionState.idle;
  double actionElapsed = 0;

  /// Begin a new windowed action. Resets the timing clock to 0 regardless
  /// of what the previous action was — a player can cancel out of one
  /// action into another (e.g. a mistimed dig into a recovery block).
  void startAction(ActionState state) {
    currentAction = state;
    actionElapsed = 0;
  }

  /// Clears back to idle — called by the resolver once contact has been
  /// consumed, so the same "spiking" input doesn't fire twice on two
  /// overlapping collision frames.
  void clearAction() {
    currentAction = ActionState.idle;
    actionElapsed = 0;
  }

  /// Call from the component's own `update(dt)`. Only advances the clock
  /// while an action is actually active — idle players cost nothing.
  void updateActionTimer(double dt) {
    if (currentAction == ActionState.idle) return;
    actionElapsed += dt;
  }

  TimingQuality get timingQuality {
    final window = ActionTimingWindow.byAction[currentAction];
    if (window == null) return TimingQuality.late;
    if (actionElapsed <= window.perfectSeconds) return TimingQuality.perfect;
    if (actionElapsed <= window.goodSeconds) return TimingQuality.good;
    return TimingQuality.late;
  }
}
