import 'dart:async';
import 'package:ebo_robot_mcp/services/hold_move_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('release stops sequence; in-flight RPC cannot queue another move', () async {
    final first = Completer<void>();
    final events = <String>[];
    final ctl = HoldMoveController(
      sendStep: (a) async { events.add('move:$a'); await first.future; },
      sendStop: () async { events.add('stop'); },
      onState: (_, _) {},
      onError: (e) => fail('$e'),
      minPause: const Duration(milliseconds: 1),
    );
    ctl.start('forward');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(events, ['move:forward']);
    await ctl.end();
    first.complete();
    await Future<void>.delayed(const Duration(milliseconds: 15));
    expect(events, ['move:forward', 'stop']);
    ctl.dispose();
  });

  test('held move sends sequential short steps, then one stop', () async {
    var steps = 0;
    var concurrent = 0;
    var peak = 0;
    var stops = 0;
    final ctl = HoldMoveController(
      sendStep: (_) async {
        concurrent++;
        if (concurrent > peak) peak = concurrent;
        steps++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        concurrent--;
      },
      sendStop: () async { stops++; },
      onState: (_, _) {},
      onError: (e) => fail('$e'),
      minPause: const Duration(milliseconds: 2),
      maxSteps: 3,
    );
    ctl.start('left');
    await Future<void>.delayed(const Duration(milliseconds: 75));
    expect(steps, 3);
    expect(peak, 1);
    expect(stops, 1);
    expect(ctl.active, isFalse);
    ctl.dispose();
  });

  test('watchdog triggers stop on long-held gesture', () async {
    var stops = 0;
    final blocker = Completer<void>();
    final ctl = HoldMoveController(
      sendStep: (_) => blocker.future,
      sendStop: () async { stops++; },
      onState: (_, _) {},
      onError: (e) => fail('$e'),
      maxHold: const Duration(milliseconds: 15),
    );
    ctl.start('right');
    await Future<void>.delayed(const Duration(milliseconds: 45));
    expect(stops, 1);
    expect(ctl.active, isFalse);
    blocker.complete();
    ctl.dispose();
  });
}
