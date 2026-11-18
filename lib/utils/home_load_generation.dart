/// Tracks overlapping Home requests so stale responses cannot replace newer
/// authenticated or context-specific content.
class HomeLoadGeneration {
  int _current = 0;

  int begin() => ++_current;

  bool isCurrent(int generation) => generation == _current;
}
