import 'dart:collection';
import 'dart:math';

import 'package:squat_deeply/keypoints.dart';

const _bufferSize = 10;

class SquatCounter {
  final int count;
  final List<KeyPoints> history;
  final KeyPoints? movingAverage;

  const SquatCounter(this.count, this.history, this.movingAverage);
  const SquatCounter.init()
      : count = 0,
        history = const [],
        movingAverage = null;

  SquatCounter push(KeyPoints next) {
    const k = 0.6;
    final avg =
        movingAverage != null ? movingAverage! * (1 - k) + next * k : next;
    return SquatCounter(
      count,
      [...history.sublist(max(0, history.length - _bufferSize)), next],
      avg,
    );
  }
}
