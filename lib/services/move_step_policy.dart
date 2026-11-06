/// Explicit conservative calibration of EBO's turning directions.
/// These are per-step angles; the 0.2m translation step remains unchanged.
class MoveStepPolicy {
  static const allowedLeftAngles = [15, 30, 45];
  static int normalizeLeftAngle(int value) =>
      allowedLeftAngles.contains(value) ? value : 30;

  static num distance(String direction, {required int leftAngle}) {
    switch (direction) {
      case 'left': return normalizeLeftAngle(leftAngle);
      case 'right': return 15;
      case 'forward':
      case 'backward': return 0.2;
      default: throw ArgumentError.value(direction, 'direction');
    }
  }
}
