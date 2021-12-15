import 'dart:async';
import 'dart:collection';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:squat_deeply/keypoints.dart';
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

  int _currentCam = 0;
  CameraController? _cameraController;

  bool _isModelReady = false;
  bool _playing = false;
  bool _predicting = false;

  KeyPoints? _keyPoints;
  double _frameRate = 0;

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
      // final kp = KeyPoints.average(_rawKeyPoints.toList());
      final kp = _keyPoints!;
      // keypoints
      previewStack.add(KeyPointsPreview(keyPoints: kp, width: width, height: height));

      if (kp.pose == SquatState.underParallel) {
        previewStack.add(Container(
          width: width,
          height: height,
          color: Colors.amber.withOpacity(0.3),
        ));
      }

      final msgs = [
        kp.score.toStringAsFixed(3),
        _frameRate.toStringAsFixed(3) + "fps",
      ];
      previewStack.add(Container(
        color: Colors.white.withOpacity(0.3),
        child: Text(
          msgs.join("\n"),
          style: const TextStyle(color: Colors.red, fontSize: 18),
        ),
      ));
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(
        children: <Widget>[
          Stack(children: previewStack),
          PlayControls(
              playable: !_playing,
              onPlay: _onPlay,
              onStop: _onStop,
              children: widget.cameras.length > 1
                  ? [
                      IconButton(
                        icon: const Icon(Icons.flip_camera_ios),
                        iconSize: 48,
                        onPressed: _playing
                            ? null
                            : () {
                                _choiceCamera(_currentCam ^ 1);
                              },
                      ),
                    ]
                  : []),
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

  void _onPlay() async {
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
        final kp = KeyPoints.fromPoseNet(res[0]);
        const k = 0.6;
        if (_keyPoints != null) {
          _keyPoints = _keyPoints! * (1 - k) + kp * k;
        } else {
          _keyPoints = kp;
        }
      }
      if (mounted) setState(() {});
    });

    if (mounted) setState(() {});
  }

  void _onStop() async {
    _playing = false;
    _keyPoints = null;
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      await _cameraController!.stopImageStream();
    }
    if (mounted) setState(() {});
  }
}

class PlayControls extends StatelessWidget {
  final bool playable;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final double iconSize;
  final List<Widget> children;
  const PlayControls({
    Key? key,
    required this.playable,
    required this.onPlay,
    required this.onStop,
    this.iconSize = 48,
    this.children = const [],
  }) : super(key: key);
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        mainAxisSize: MainAxisSize.max,
        children: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            iconSize: iconSize,
            onPressed: playable ? onPlay : null,
          ),
          IconButton(
            icon: const Icon(Icons.stop),
            iconSize: iconSize,
            onPressed: playable ? null : onStop,
          ),
          ...children,
        ],
      );
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
  Widget build(BuildContext context) => Text(
        "●",
        style: TextStyle(fontSize: size, color: color),
      );
}

class KeyPointsPreview extends StatelessWidget {
  final KeyPoints keyPoints;
  final double width;
  final double height;
  const KeyPointsPreview({
    Key? key,
    required this.keyPoints,
    required this.width,
    required this.height,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: Stack(
        children: keyPoints.points.values
            .map((e) => Positioned(
                  left: e.vec.x * width - 6,
                  top: e.vec.y * height - 6,
                  child: const KeyPointIndicator(),
                ))
            .toList(),
      ),
  );
}
