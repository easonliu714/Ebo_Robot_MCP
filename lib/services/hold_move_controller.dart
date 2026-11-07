import 'dart:async';

/// Converts a held direction into bounded, sequential single-step MCP calls.
/// This is NOT real continuous-velocity control. Never queue move requests:
/// each new step starts only after the previous one completes plus a pause.
/// On finger release/background/timeout, cancel further steps and request stop.
class HoldMoveController {
  final Future<void> Function(String action) sendStep;
  final Future<void> Function() sendStop;
  final void Function(bool active, String? action) onState;
  final void Function(Object error) onError;
  final Duration minPause;
  final Duration maxHold;
  final int maxSteps;

  bool _active = false;
  String? _action;
  int _epoch = 0;
  int _stepCount = 0;
  int _limit = 12;
  Timer? _watchdog;

  HoldMoveController({
    required this.sendStep,
    required this.sendStop,
    required this.onState,
    required this.onError,
    this.minPause = const Duration(milliseconds: 450),
    this.maxHold = const Duration(seconds: 12),
    this.maxSteps = 12,
  }) : assert(maxSteps > 0);

  bool get active => _active;
  String? get action => _action;

  void start(String action, {int? maxSteps}) {
    if (_active) return;
    _active = true;
    _action = action;
    _stepCount = 0;
    _limit = maxSteps == null ? this.maxSteps : maxSteps.clamp(1, this.maxSteps);
    final epoch = ++_epoch;
    onState(true, action);
    _watchdog?.cancel();
    _watchdog = Timer(maxHold, () => unawaited(end()));
    unawaited(_run(epoch, action));
  }

  Future<void> _run(int epoch, String action) async {
    while (_active && epoch == _epoch && _stepCount < _limit) {
      _stepCount++;
      try {
        await sendStep(action); // one call at a time; no backlog
      } catch (error) {
        onError(error);
        await end();
        return;
      }
      if (!_active || epoch != _epoch) return;
      if (_stepCount == _limit) {
        await end();
        return;
      }
      await Future<void>.delayed(minPause);
    }
  }

  /// Idempotent: prevents new steps synchronously; stop is best effort.
  /// MCP's existing exclusive queue serializes stop after an in-flight step.
  Future<void> end() async {
    if (!_active) return;
    _active = false;
    _action = null;
    ++_epoch;
    _watchdog?.cancel();
    _watchdog = null;
    onState(false, null);
    try {
      await sendStop();
    } catch (error) {
      onError(error);
    }
  }

  /// Never initiate new work after the widget is gone.
  void dispose() {
    _active = false;
    _action = null;
    ++_epoch;
    _watchdog?.cancel();
    _watchdog = null;
  }
}
