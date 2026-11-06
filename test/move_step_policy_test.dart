import 'package:ebo_robot_mcp/services/move_step_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('left calibration affects only left rotation', () {
    expect(MoveStepPolicy.distance('left', leftAngle: 30), 30);
    expect(MoveStepPolicy.distance('left', leftAngle: 45), 45);
    expect(MoveStepPolicy.distance('right', leftAngle: 45), 15);
    expect(MoveStepPolicy.distance('forward', leftAngle: 45), 0.2);
    expect(MoveStepPolicy.normalizeLeftAngle(999), 30);
  });
}
