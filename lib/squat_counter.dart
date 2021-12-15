import 'dart:math';

import 'package:squat_deeply/keypoints.dart';

enum SquatState {
  unknown,
  sittingToParallel,
  sittingToBottom,
  standingToParallel,
  standing,
}

const _bufferSize = 10;

class SquatCounter {
  final int count;
  final List<KeyPoints> history;

  const SquatCounter(this.count, this.history);
  const SquatCounter.init()
      : count = 0,
        history = const [];

  SquatCounter push(KeyPoints keypoints) {
    const k = 0.6;
    final avg =
       history.isEmpty ? keypoints : history.last * (1 - k) + keypoints * k;
    final next = SquatCounter(
      count,
      [...history.sublist(max(0, history.length - _bufferSize)), avg],
    );
    return next;
  }

  KeyPoints? get last => history.isEmpty ? null : history.last;
  SquatState get state {
    if (history.length < 2) {
      return SquatState.unknown;
    }
    final last = history.last.leftKneeAngle ?? 0;
    final prev = history[history.length - 2].leftKneeAngle ?? 0;
    if (last > prev) {
      if (last < pi / 2) {
        return SquatState.standingToParallel;
      } else {
        return SquatState.standing;
      }
    } else {
      if (last < pi / 2) {
        return SquatState.sittingToBottom;
      } else {
        return SquatState.sittingToBottom;
      }
    }
  }
  SquatState get prevState => SquatState.sittingToParallel;
}
