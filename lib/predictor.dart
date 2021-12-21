import 'package:camera/camera.dart';
import 'package:squat_deeply/keypoints.dart';
import 'package:tflite/tflite.dart';

class PredictionResult {
  final DateTime timestamp;
  final KeyPoints keyPoints;
  final Duration duration;
  const PredictionResult(this.timestamp, this.keyPoints, this.duration);
}

class Predictor {
  bool _initialized = false;
  bool _busy = false;
  Predictor();

  bool get ready => _initialized && !_busy;

  Future<void> init() async {
    await Tflite.loadModel(
      model: "assets/posenet_mv1_075_float_from_checkpoints.tflite",
      useGpuDelegate: true,
    );
    _initialized = true;
  }

  Future<PredictionResult?> predict(CameraImage image) async {
    if (!_initialized) {
      throw Exception("Model is not loaded");
    } else if (_busy) {
      throw ResourceIsBusy();
    }
    _busy = true;
    final ts = DateTime.now();
    try {
      var res = await Tflite.runPoseNetOnFrame(
        bytesList: image.planes.map((plane) => plane.bytes).toList(),
        imageHeight: image.height,
        imageWidth: image.width,
        numResults: 2,
      );
      if (res == null) {
        throw Exception("Invalid prediction result");
      } else if (res.isEmpty) {
        return null;
      }
      final kp = KeyPoints.fromPoseNet(res[0]);
      return PredictionResult(ts, kp, DateTime.now().difference(ts));
    } catch (e) {
      rethrow;
    } finally {
      _busy = false;
    }
  }
}

class ResourceIsBusy extends Error {
  @override
  String toString() => "Resource is busy";
}
