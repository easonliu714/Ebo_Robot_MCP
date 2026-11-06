/// Entry-triggered RTSP refresh: no continuous background polling.
class VideoTabPolicy {
  static bool enteredVideoTab(int previous, int next) =>
      previous != next && (next == 0 || next == 1);
  static bool shouldResumeStream(int current) =>
      current == 0 || current == 1;
}
