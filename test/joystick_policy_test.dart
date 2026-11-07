import 'package:ebo_robot_mcp/services/joystick_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all eight compass sectors and center stop', () {
    expect(JoystickPolicy.direction(0, -100), 'forward');
    expect(JoystickPolicy.direction(70, -70), 'forward_right');
    expect(JoystickPolicy.direction(100, 0), 'right');
    expect(JoystickPolicy.direction(70, 70), 'backward_right');
    expect(JoystickPolicy.direction(0, 100), 'backward');
    expect(JoystickPolicy.direction(-70, 70), 'backward_left');
    expect(JoystickPolicy.direction(-100, 0), 'left');
    expect(JoystickPolicy.direction(-70, -70), 'forward_left');
    expect(JoystickPolicy.direction(0, 0), 'stop');
    expect(JoystickPolicy.direction(999, 0), isNull);
  });

  test('diagonal movement is sequential, constrained and orthogonal', () {
    final upLeft = JoystickPolicy.diagonalSteps('forward_left');
    expect(upLeft.map((e) => e.moveId).toList(), [3, 1]);
    expect(upLeft.map((e) => e.targetDistance).toList(), [7, 0.1]);
    final downRight = JoystickPolicy.diagonalSteps('backward_right');
    expect(downRight.map((e) => e.moveId).toList(), [4, 2]);
    expect(JoystickPolicy.isDiagonal('left'), isFalse);
    expect(JoystickPolicy.isDiagonal('backward_right'), isTrue);
  });
}
