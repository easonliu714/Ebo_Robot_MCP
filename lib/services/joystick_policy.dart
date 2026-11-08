import 'dart:math' as math;

/// EBO's MCP supports one discrete moveId at a time; diagonal inputs
/// are deliberately modeled as two sequential, low-distance commands.
class JoystickMove {
  final int moveId;
  final num targetDistance;
  const JoystickMove(this.moveId, this.targetDistance);
}
class JoystickPolicy {
  static const diagonals = {
    'forward_left', 'forward_right', 'backward_left', 'backward_right'
  };
  static bool isDiagonal(String value) => diagonals.contains(value);

  /// dx positive is right, dy positive is down. stop is central dead zone.
  static String? direction(double dx, double dy, {double radius = 110}) {
    if (radius <= 0) return null;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance > radius) return null;
    if (distance < radius * 0.22) return 'stop';
    final a = math.atan2(-dy, dx) * 180 / math.pi;
    if (a >= -22.5 && a < 22.5) return 'right';
    if (a >= 22.5 && a < 67.5) return 'forward_right';
    if (a >= 67.5 && a < 112.5) return 'forward';
    if (a >= 112.5 && a < 157.5) return 'forward_left';
    if (a >= 157.5 || a < -157.5) return 'left';
    if (a >= -157.5 && a < -112.5) return 'backward_left';
    if (a >= -112.5 && a < -67.5) return 'backward';
    return 'backward_right';
  }

  /// Sequential turn then translation; not simultaneous velocity control.
  /// Operator-selectable microturn angle defaults to 7 degrees.
  static List<JoystickMove> diagonalSteps(
      String direction, {int turnDegrees = 7}) {
    if (!const [7, 10, 15].contains(turnDegrees)) {
      throw ArgumentError.value(turnDegrees, 'turnDegrees');
    }
    return switch (direction) {
      'forward_left' => [JoystickMove(3, turnDegrees), const JoystickMove(1, 0.1)],
      'forward_right' => [JoystickMove(4, turnDegrees), const JoystickMove(1, 0.1)],
      'backward_left' => [JoystickMove(3, turnDegrees), const JoystickMove(2, 0.1)],
      'backward_right' => [JoystickMove(4, turnDegrees), const JoystickMove(2, 0.1)],
      _ => throw ArgumentError.value(direction, 'direction'),
    };
  }
}
