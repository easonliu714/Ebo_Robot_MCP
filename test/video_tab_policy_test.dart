import 'package:ebo_robot_mcp/services/video_tab_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('enter video tab reconnects exactly on tab transition', () {
    expect(VideoTabPolicy.enteredVideoTab(2, 0), isTrue);
    expect(VideoTabPolicy.enteredVideoTab(3, 1), isTrue);
    expect(VideoTabPolicy.enteredVideoTab(0, 1), isTrue);
    expect(VideoTabPolicy.enteredVideoTab(1, 1), isFalse);
    expect(VideoTabPolicy.enteredVideoTab(0, 2), isFalse);
  });
  test('only foreground video tabs reopen on app resume', () {
    expect(VideoTabPolicy.shouldResumeStream(0), isTrue);
    expect(VideoTabPolicy.shouldResumeStream(1), isTrue);
    expect(VideoTabPolicy.shouldResumeStream(2), isFalse);
  });
}
