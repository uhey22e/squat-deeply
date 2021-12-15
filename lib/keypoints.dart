import 'dart:math';

import 'package:vector_math/vector_math.dart';

enum KeyPointPart {
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
}

const keyPointPartNumbers = {
  5: KeyPointPart.leftShoulder,
  6: KeyPointPart.rightShoulder,
  7: KeyPointPart.leftElbow,
  8: KeyPointPart.rightElbow,
  9: KeyPointPart.leftWrist,
  10: KeyPointPart.rightWrist,
  11: KeyPointPart.leftHip,
  12: KeyPointPart.rightHip,
  13: KeyPointPart.leftKnee,
  14: KeyPointPart.rightKnee,
  15: KeyPointPart.leftAnkle,
  16: KeyPointPart.rightAnkle,
};

class KeyPoint {
  final KeyPointPart part;
  final Vector2 vec;
  final double score;
  const KeyPoint(this.part, this.vec, this.score);

  operator +(KeyPoint other) {
    return KeyPoint(part, vec + other.vec, (score + other.score) / 2);
  }
  operator *(double other) {
    return KeyPoint(part, vec * other, score);
  }
  operator /(double other) {
    return KeyPoint(part, vec / other, score);
  }
}

enum SquatState {
  unknown,
  standing,
  squatPartially,
  sittingUnderParallel,
  standingOverParallel,
  underParallel,
}

class KeyPoints {
  final Map<KeyPointPart, KeyPoint> points;
  const KeyPoints(this.points);

  KeyPoints.fromPoseNet(dynamic cognition) : points = {} {
    keyPointPartNumbers.forEach((key, part) {
      var v = cognition["keypoints"]?[key];
      if (v != null) {
        points[part] = KeyPoint(part, Vector2(v["x"], v["y"]), v["score"]);
      }
    });
  }

  operator +(KeyPoints left) {
    var p = <KeyPointPart, KeyPoint>{};
    for (final part in KeyPointPart.values) {
      final zero = KeyPoint(part, Vector2(0, 0), 0);
      final l = points[part];
      final r = left.points[part];
      if (l != null || r != null) {
        p[part] = (l ?? zero) + (r ?? zero);
      }
    }
    return KeyPoints(p);
  }

  operator *(double other) {
    var p = <KeyPointPart, KeyPoint>{};
    for (final part in KeyPointPart.values) {
      final v = points[part];
      if (v != null) {
        p[part] = v * other;
      }
    }
    return KeyPoints(p);
  }

  @override
  String toString() {
    return points.toString();
  }

  double get score {
    if (points.isEmpty) {
      return 0;
    }
    var sum = points.entries
        .map((e) => e.value.score)
        .reduce((value, element) => value + element);
    return sum / points.length;
  }

  double? get leftKneeAngle {
    final hip = points[KeyPointPart.leftHip]?.vec;
    final knee = points[KeyPointPart.leftKnee]?.vec;
    final ankle = points[KeyPointPart.leftAnkle]?.vec;
    if (hip == null || knee == null || ankle == null) {
      return null;
    }
    return (hip - knee).angleTo(ankle - knee);
  }

  double? get rightKneeAngle {
    final hip = points[KeyPointPart.rightHip]?.vec;
    final knee = points[KeyPointPart.rightKnee]?.vec;
    final ankle = points[KeyPointPart.rightAnkle]?.vec;
    if (hip == null || knee == null || ankle == null) {
      return null;
    }
    return (hip - knee).angleTo(ankle - knee);
  }

  SquatState get pose {
    const threshold = (pi / 2);
    if ((leftKneeAngle ?? pi) < threshold) {
      return SquatState.underParallel;
    }
    if ((rightKneeAngle ?? pi) < threshold) {
      return SquatState.underParallel;
    }
    return SquatState.standing;
  }
}
