/// Explicit conservative calibration of EBO's turning directions.
/// These are per-step angles; the 0.2m translation step remains unchanged.
class MoveStepPolicy {
  static const allowedLeftAngles = [15, 30, 45];
  // The MCP schema describes 3 as a smaller radius, NOT as 3x speed.
  static const allowedTurnRadiusModes = [1, 3];
  static int normalizeTurnRadiusMode(int value) =>
      allowedTurnRadiusModes.contains(value) ? value : 1;
  static const allowedDiagonalAngles = [7, 10, 15];
  static int normalizeDiagonalAngle(int value) =>
      allowedDiagonalAngles.contains(value) ? value : 7;

  // A reply is only an MCP acknowledgement, not wheel-motion completion.
  static const turnSettling = Duration(milliseconds: 400);
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
