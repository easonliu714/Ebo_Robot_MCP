import 'dart:async';
import 'package:flutter/material.dart';
import '../services/joystick_policy.dart';

/// Eight-way circular touch pad. Touch center = STOP. A short tap triggers
/// one step; holding over 300 ms triggers bounded repeating steps.
/// Releasing/cancelling/dragging into center asks controller to stop.
class RobotJoystick extends StatefulWidget {
  final Future<void> Function(String action) onTapAction;
  final void Function(String action) onHoldStart;
  final void Function(String? action) onHoldChange;
  final void Function() onHoldEnd;
  final bool enabled;
  final double size;

  const RobotJoystick({
    super.key,
    required this.onTapAction,
    required this.onHoldStart,
    required this.onHoldChange,
    required this.onHoldEnd,
    required this.enabled,
    this.size = 228,
  });

  @override
  State<RobotJoystick> createState() => _RobotJoystickState();
}

class _RobotJoystickState extends State<RobotJoystick> {
  Timer? _holdTimer;
  int? _pointer;
  String? _direction;
  bool _held = false;

  String? _resolve(Offset local) => JoystickPolicy.direction(
    local.dx - widget.size / 2, local.dy - widget.size / 2,
    radius: widget.size / 2,
  );

  void _startTimer(String? direction) {
    _holdTimer?.cancel();
    if (direction == null || direction == 'stop') return;
    _holdTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || _pointer == null || _held || !widget.enabled) return;
      _held = true;
      widget.onHoldStart(direction);
    });
  }

  void _down(PointerDownEvent event) {
    if (!widget.enabled || _pointer != null) return;
    _pointer = event.pointer;
    final next = _resolve(event.localPosition);
    setState(() => _direction = next);
    _held = false;
    if (next == 'stop') {
      unawaited(widget.onTapAction('stop'));
    } else {
      _startTimer(next);
    }
  }

  void _move(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final next = _resolve(event.localPosition);
    if (next == _direction) return;
    setState(() => _direction = next);
    if (_held) {
      widget.onHoldChange(next == 'stop' ? null : next);
      if (next == null || next == 'stop') {
        // Hold controller gets STOP immediately; movement never resumes
        // until a new gesture starts.
        _held = false;
        _holdTimer?.cancel();
      }
    } else {
      _startTimer(next);
    }
  }

  void _finish(int pointer, {bool cancelled = false}) {
    if (pointer != _pointer) return;
    _holdTimer?.cancel();
    final action = _direction;
    final wasHeld = _held;
    _pointer = null;
    _held = false;
    if (mounted) setState(() => _direction = null);
    if (wasHeld) {
      widget.onHoldEnd();
    } else if (!cancelled && action != null && action != 'stop' &&
        widget.enabled) {
      unawaited(widget.onTapAction(action));
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    if (_held) widget.onHoldEnd();
    super.dispose();
  }

  Widget _arrow(String action, IconData icon, double x, double y) {
    final selected = _direction == action;
    return Positioned(
      left: widget.size / 2 + x - 21,
      top: widget.size / 2 + y - 21,
      child: IgnorePointer(child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? const Color(0xCC22B8C8) : const Color(0x5550727E),
        ),
        child: Icon(icon, color: Colors.white, size: 25),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.size * 0.33;
    return Semantics(
      label: '八方向圓盤。左上為前進加左轉，右下為後退加右轉。中央立即停止。',
      child: SizedBox(
        width: widget.size, height: widget.size,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: (e) => _finish(e.pointer),
          onPointerCancel: (e) => _finish(e.pointer, cancelled: true),
          child: Stack(children: [
            Positioned.fill(child: IgnorePointer(child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xAA18343D),
                border: Border.all(color: const Color(0xFF77CAD5), width: 2),
              ),
            ))),
            _arrow('forward', Icons.north, 0, -r),
            _arrow('forward_right', Icons.north_east, r * .70, -r * .70),
            _arrow('right', Icons.east, r, 0),
            _arrow('backward_right', Icons.south_east, r * .70, r * .70),
            _arrow('backward', Icons.south, 0, r),
            _arrow('backward_left', Icons.south_west, -r * .70, r * .70),
            _arrow('left', Icons.west, -r, 0),
            _arrow('forward_left', Icons.north_west, -r * .70, -r * .70),
            Positioned(
              left: widget.size / 2 - 23, top: widget.size / 2 - 23,
              child: IgnorePointer(child: Container(
                width: 46, height: 46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle, color: Color(0xFF8B2833)),
                child: const Icon(Icons.stop_circle, color: Colors.white),
              )),
            ),
          ]),
        ),
      ),
    );
  }
}
