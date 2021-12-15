import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tflite/tflite.dart';

List<CameraDescription> cams = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cams = await availableCameras();
  } on CameraException catch (e) {
    print('Error: ${e.code}\nError Message: ${e.description}');
  }
  runApp(const CameraApp());
}

class CameraApp extends StatelessWidget {
  const CameraApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var title = 'Squat Deeply';
    return MaterialApp(
      title: title,
      home: SquatCamPage(title: title, cameras: cams),
    );
  }
}

class SquatCamPage extends StatefulWidget {
  final String title;
  final List<CameraDescription> cameras;
  const SquatCamPage({Key? key, required this.title, required this.cameras})
      : super(key: key);

  @override
  _SquatCamPageState createState() => _SquatCamPageState();
}

class _SquatCamPageState extends State<SquatCamPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _previewKey = GlobalKey();

  int _currentCam = 0;
  CameraController? _cameraController;

  bool _isModelReady = false;
  bool _playing = false;
  bool _predicting = false;
  KeyPoints? _keyPoints;
  double? _frameRate;

  Size? previewSize;

  @override
  void initState() {
    super.initState();
    _loadModel();
    if (widget.cameras.isNotEmpty) {
      _choiceCamera(0);
    }
  }

  @override
  void dispose() async {
    if (_cameraController != null) {
      await _cameraController!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.of(context).size;
    final width = sz.width;
    final height = _cameraController != null
        ? width * _cameraController!.value.aspectRatio
        : width * (5 / 4);

    List<Widget> previewStack = [
      CamView(cameraController: _cameraController),
    ];

    if (_keyPoints != null) {
      previewStack.addAll(
        _keyPoints!.points.entries
          .map((e) => Positioned(
            left: e.value.x * width - 6,
            top: e.value.y * height - 6,
            child: const KeyPointIndicator(),
          )),
      );
      List<String> msgs = [
        _keyPoints!.score.toStringAsFixed(3),
      ];
      if (_frameRate != null) {
        msgs.add("\n" + _frameRate!.toStringAsFixed(3) + "fps");
      }
      previewStack.add(
        Text(msgs.join("\n"), style: const TextStyle(color: Colors.red, fontSize: 18)),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(
        children: <Widget>[
          Stack(children: previewStack),
          _controls(),
        ],
      ),
    );
  }

  void _loadModel() async {
    print("loading model");
    await Tflite.loadModel(
      model: "assets/posenet_mv1_075_float_from_checkpoints.tflite",
      useGpuDelegate: true,
    );
    _isModelReady = true;
    if (mounted) setState(() {});
  }

  void _choiceCamera(int i) async {
    await _cameraController?.dispose();
    final cam = widget.cameras[i];
    final controller = CameraController(
      cam,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    if (mounted) {
      setState(() {
        print('camera changed: ${cam.name}');
        _currentCam = i;
        _cameraController = controller;
      });
    }
  }

  void _play() async {
    if (!_isModelReady ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return;
    }
    _playing = true;

    await _cameraController!.startImageStream((image) async {
      if (_predicting) return;
      _predicting = true;
      final ts = DateTime.now().millisecondsSinceEpoch;
      var res = await Tflite.runPoseNetOnFrame(
        bytesList: image.planes.map((plane) => plane.bytes).toList(),
        imageHeight: image.height,
        imageWidth: image.width,
        numResults: 2,
      );
      _predicting = false;
      final dur = DateTime.now().millisecondsSinceEpoch - ts;
      _frameRate = 1000.0 / dur;

      if (res != null && res.isNotEmpty && res[0] != null) {
        _keyPoints = KeyPoints.fromPoseNet(res[0]);
      } else {
        _keyPoints = null;
      }
      if (mounted) setState(() {});
    });

    if (mounted) setState(() {});
  }

  void _stop() async {
    _playing = false;
    _keyPoints = null;
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      await _cameraController!.stopImageStream();
    }
    if (mounted) setState(() {});
  }

  Widget _controls() {
    const double iconSize = 48;
    var items = <Widget>[
      IconButton(
        icon: const Icon(Icons.play_arrow),
        iconSize: iconSize,
        onPressed: _playing ? null : _play,
      ),
      IconButton(
        icon: const Icon(Icons.stop),
        iconSize: iconSize,
        onPressed: _playing ? _stop : null,
      ),
    ];
    if (widget.cameras.length > 1) {
      items.add(IconButton(
        icon: const Icon(Icons.flip_camera_ios),
        iconSize: iconSize,
        onPressed: _playing
            ? null
            : () {
                _choiceCamera(_currentCam ^ 1);
              },
      ));
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      mainAxisSize: MainAxisSize.max,
      children: items,
    );
  }
}

class CamView extends StatelessWidget {
  const CamView({Key? key, this.cameraController}) : super(key: key);
  final CameraController? cameraController;
  @override
  Widget build(BuildContext context) {
    if (cameraController == null) {
      return AspectRatio(
        aspectRatio: 4 / 5,
        child: Container(
          alignment: Alignment.center,
          color: Colors.black,
          child: const Text(
            'No cams available',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24.0,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      );
    }
    return AspectRatio(
      aspectRatio: 1 / cameraController!.value.aspectRatio,
      child: CameraPreview(cameraController!),
    );
  }
}

class KeyPointIndicator extends StatelessWidget {
  const KeyPointIndicator({
    Key? key,
    this.size = 12,
    this.color = Colors.redAccent,
  }) : super(key: key);
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Text(
      "●",
      style: TextStyle(fontSize: size, color: color),
    );
  }
}

class CognitionResult {
  final double x;
  final double y;
  final String part;
  final double score;
  const CognitionResult(this.x, this.y, this.part, this.score);
}

class KeyPoints {
  final Map<int, CognitionResult> points;

  KeyPoints(this.points);
  KeyPoints.fromPoseNet(dynamic cognition) : points = {} {
    final keys = [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16];
    for (final key in keys) {
      var v = cognition["keypoints"]?[key];
      if (v != null) {
        points[key] = CognitionResult(v["x"], v["y"], v["part"], v["score"]);
      }
    }
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
}
