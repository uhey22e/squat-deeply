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

const _poseNetIndices = {
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
}

class KeyPoints {
  final Map<KeyPointPart, KeyPoint> _points;

  KeyPoints.fromPoseNet(dynamic cognition) : _points = {} {
    _poseNetIndices.forEach((key, part) {
      var v = cognition["keypoints"]?[key];
      if (v != null) {
        _points[part] = KeyPoint(part, Vector2(v["x"], v["y"]), v["score"]);
      }
    });
  }

  @override
  String toString() {
    return _points.toString();
  }

  List<KeyPoint> get points => _points.values.toList();

  double get score {
    if (_points.isEmpty) {
      return 0;
    }
    var sum = _points.entries
        .map((e) => e.value.score)
        .reduce((value, element) => value + element);
    return sum / _points.length;
  }

  Vector2? get leftHip => _points[KeyPointPart.leftHip]?.vec;

  double? get leftKneeAngle {
    final hip = _points[KeyPointPart.leftHip]?.vec;
    final knee = _points[KeyPointPart.leftKnee]?.vec;
    final ankle = _points[KeyPointPart.leftAnkle]?.vec;
    if (hip == null || knee == null || ankle == null) {
      return null;
    }
    return (hip - knee).angleTo(ankle - knee);
  }

  double? get rightKneeAngle {
    final hip = _points[KeyPointPart.rightHip]?.vec;
    final knee = _points[KeyPointPart.rightKnee]?.vec;
    final ankle = _points[KeyPointPart.rightAnkle]?.vec;
    if (hip == null || knee == null || ankle == null) {
      return null;
    }
    return (hip - knee).angleTo(ankle - knee);
  }
}

const _bufferSize = 30;

class KeyPointsSeries {
  final List<DateTime> timestamps;
  final List<KeyPoints> keyPoints;
  final List<double> kneeAngles;

  const KeyPointsSeries(this.timestamps, this.keyPoints, this.kneeAngles);

  const KeyPointsSeries.init()
      : timestamps = const [],
        keyPoints = const [],
        kneeAngles = const [];

  KeyPointsSeries push(DateTime timestamp, KeyPoints kp) {
    if (kp.leftHip == null || kp.leftKneeAngle == null) {
      return this;
    }

    final timestamps = [timestamp, ...this.timestamps];
    final keyPoints = [kp, ...this.keyPoints];
    if (keyPoints.length == 1) {
      return KeyPointsSeries(timestamps, keyPoints, [kp.leftKneeAngle!]);
    }

    const k = 0.7;
    final kneeAngles = [
      this.kneeAngles.first * (1 - k) + kp.leftKneeAngle! * k,
      ...this.kneeAngles,
    ];
    return KeyPointsSeries(
      timestamps.length > _bufferSize
          ? timestamps.sublist(0, _bufferSize - 1)
          : timestamps,
      keyPoints.length > _bufferSize
          ? keyPoints.sublist(0, _bufferSize - 1)
          : keyPoints,
      kneeAngles.length > _bufferSize
          ? kneeAngles.sublist(0, _bufferSize - 1)
          : kneeAngles,
    );
  }

  double get kneeAngleSpeed {
    // radian / sec
    if (kneeAngles.length < 2) {
      return 0;
    }
    final dt = timestamps[0].difference(timestamps[1]);
    return (kneeAngles[0] - kneeAngles[1]) /
        (dt.inMicroseconds.toDouble() / 1000000);
  }

  List<double> get kneeAngleSpeeds {
    // radian / sec
    if (kneeAngles.length < 2) {
      return [];
    }
    return List<double>.generate(kneeAngles.length - 1, (i) {
      final dt = timestamps[i].difference(timestamps[i + 1]);
      return (kneeAngles[i] - kneeAngles[i + 1]) /
          (dt.inMicroseconds.toDouble() / 1000000);
    });
  }

  bool get isStanding {
    return kneeAngleSpeed > 2.0;
  }

  bool get isUnderParallel {
    return kneeAngles.first < (pi * 10 / 18);
  }
}
