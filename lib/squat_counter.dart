import 'dart:math';

import 'package:squat_deeply/keypoints.dart';

enum SquatState {
  unknown,
  sitting,
  standing,
}

const _bufferSize = 20;

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
    final hist = <KeyPoints>[
      ...history.sublist(max(0, history.length - _bufferSize)),
      avg
    ];
    final next = SquatCounter(count, hist);
    return next;
  }

  KeyPoints? get last => history.isEmpty ? null : history.last;
  SquatState get state {
    if (history.length != _bufferSize) {
      return SquatState.unknown;
    }
    final cur = history.last.leftKneeAngle;
    final cmp = history.first.leftKneeAngle;
    if (cur != null || cmp != null) {
      return SquatState.unknown;
    }
    final v = cur! - cmp!;
    const threshold = 0.1;
    if (v > threshold) {
      return SquatState.standing;
    } else if (v < -threshold) {
      return SquatState.sitting;
    }
    return SquatState.unknown;
  }

  bool get switching {
    // 切り返し検出
    if (history.length != _bufferSize) {
      return false;
    }
    const threshold = 0.01;
    return ((angle ?? 0) - (bottom ?? pi)) > threshold;
  }

  double? get angle {
    if (history.isEmpty) return 0;
    return history.last.leftKneeAngle ?? 0;
  }

  double? get bottom {
    if (history.isEmpty) return pi;
    final bottom = history.map((e) => e.leftKneeAngle ?? pi).reduce(min);
    return bottom;
  }
}
