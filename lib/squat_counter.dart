import 'dart:math';

import 'package:squat_deeply/keypoints.dart';

enum SquatState {
  unknown,
  sitting,
  standing,
}

const _bufferSize = 30;

class SquatCounter {
  final int count;
  final List<KeyPoints> history;
  final List<double> hipSpeeds;

  const SquatCounter(this.count, this.history, this.hipSpeeds);
  const SquatCounter.init()
      : count = 0,
        history = const [],
        hipSpeeds = const [];

  SquatCounter push(KeyPoints keypoints) {
    const k = 0.6;
    final avg =
        history.isEmpty ? keypoints : history.last * (1 - k) + keypoints * k;
    final hist = <KeyPoints>[
      ...history.sublist(max(0, history.length - _bufferSize)),
      avg
    ];

    final hipSpeeds = List<double>.generate(max(0, hist.length - 2), (i) {
      final base = hist[i + 2].points[KeyPointPart.leftHip];
      final cmp = hist[i].points[KeyPointPart.leftHip];
      if (base != null && cmp != null) {
        return base.vec.y - cmp.vec.y;
      }
      return 0;
    });

    return SquatCounter(count, hist, hipSpeeds);
  }

  KeyPoints? get last => history.isEmpty ? null : history.last;

  bool get isUnderParallel {
    if (history.isNotEmpty && history.last.leftKneeAngle != null) {
      return history.last.leftKneeAngle! < (10 * pi / 18);
    }
    return false;
  }

  bool get isStanding {
    if (hipSpeeds.isNotEmpty) {
      return hipSpeeds.last < -0.015;
    }
    return false;
  }
}
