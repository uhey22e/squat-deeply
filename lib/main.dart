import 'dart:async';
import 'package:camera/camera.dart';
import 'package:charts_flutter/flutter.dart' as charts;
import 'package:flutter/material.dart';
import 'package:squat_deeply/keypoints.dart';
import 'package:squat_deeply/predictor.dart';

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
  final bool _showDebugMsg = true;
  const SquatCamPage({Key? key, required this.title, required this.cameras})
      : super(key: key);

  @override
  _SquatCamPageState createState() => _SquatCamPageState();
}

class _SquatCamPageState extends State<SquatCamPage> {
  final Predictor _predictor = Predictor();
  int _count = 0;
  KeyPointsSeries _keyPoints = const KeyPointsSeries.init();

  int _currentCam = 0;
  CameraController? _cameraController;

  bool _playing = false;
  double _frameRate = 0;

  bool _cntMutex = false;
  Widget _shallowAlert = Container();

  @override
  void initState() {
    super.initState();
    _predictor.init();
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

    final previewStack = <Widget>[
      _CamView(cameraController: _cameraController),
    ];

    if (_keyPoints.keyPoints.isNotEmpty) {
      previewStack.add(
        _KeyPointsPreview(
            keyPoints: _keyPoints.keyPoints.first,
            width: width,
            height: height),
      );

      if (widget._showDebugMsg) {
        final msgs = [
          _keyPoints.keyPoints.first.score.toStringAsFixed(3),
          _frameRate.toStringAsFixed(3) + " fps",
          _keyPoints.kneeAngleSpeed.toStringAsFixed(3),
        ];
        previewStack.add(Container(
          color: Colors.white.withOpacity(0.3),
          child: Text(
            msgs.join("\n"),
            style: const TextStyle(color: Colors.red, fontSize: 18),
          ),
        ));
      }
    }

    previewStack.add(Container(
      alignment: Alignment.center,
      height: height,
      child: _shallowAlert,
    ));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Column(
        children: <Widget>[
          Stack(children: previewStack),
          _PlayControls(
              playable: !_playing,
              onPlay: _onPlay,
              onStop: _onStop,
              children: widget.cameras.length > 1
                  ? [
                      IconButton(
                        icon: const Icon(Icons.flip_camera_ios),
                        iconSize: 32,
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

  void _onStop() async {
    setState(() {
      _cameraController?.stopImageStream();
      _playing = false;
    });
  }

  void _onPlay() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    setState(() {
      _playing = true;
      _cntMutex = false;
      _shallowAlert = Container();
      _keyPoints = const KeyPointsSeries.init();
    });
    await _cameraController!.startImageStream((image) async {
      if (!_predictor.ready) return;
      var res = await _predictor.predict(image);
      if (res != null && res.keyPoints.score > 0.5) {
        _frameRate = 1000 / res.duration.inMilliseconds.toDouble();
        _keyPoints = _keyPoints.push(res.timestamp, res.keyPoints);

        if (!_cntMutex && _keyPoints.isStanding) {
          _cntMutex = true;
          var msg = "浅い!!!";
          if (_keyPoints.isUnderParallel) {
            _count += 1;
            msg = _count.toString();
          }
          _shallowAlert = Text(msg,
              style: const TextStyle(color: Colors.redAccent, fontSize: 90, fontWeight: FontWeight.w800));
          Timer(const Duration(seconds: 2), () {
            setState(() {
              _cntMutex = false;
              _shallowAlert = Container();
            });
          });
        }
      }
      if (mounted) setState(() {});
    });
  }
}

class _PlayControls extends StatelessWidget {
  final bool playable;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final double iconSize;
  final List<Widget> children;
  const _PlayControls({
    Key? key,
    required this.playable,
    required this.onPlay,
    required this.onStop,
    this.iconSize = 32,
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

class _CamView extends StatelessWidget {
  const _CamView({
    Key? key,
    required this.cameraController,
  }) : super(key: key);
  final CameraController? cameraController;
  @override
  Widget build(BuildContext context) {
    if (cameraController != null) {
      return AspectRatio(
        aspectRatio: 1 / cameraController!.value.aspectRatio,
        child: CameraPreview(cameraController!),
      );
    }
    return AspectRatio(
      aspectRatio: 5 / 4,
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
}

class _KeyPointIndicator extends StatelessWidget {
  const _KeyPointIndicator({
    Key? key,
    this.size = 12,
    this.color = Colors.amberAccent,
  }) : super(key: key);
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
        "●",
        style: TextStyle(fontSize: size, color: color),
      );
}

class _KeyPointsPreview extends StatelessWidget {
  final KeyPoints keyPoints;
  final double width;
  final double height;
  const _KeyPointsPreview({
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
          children: keyPoints.points
              .map((e) => Positioned(
                    left: e.vec.x * width - 6,
                    top: e.vec.y * height - 6,
                    child: const _KeyPointIndicator(),
                  ))
              .toList(),
        ),
      );
}

class _SquatChart extends StatelessWidget {
  final KeyPointsSeries data;
  const _SquatChart(this.data, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return charts.TimeSeriesChart([
      charts.Series<double, DateTime>(
        id: 'KneeAngle',
        data: data.kneeAngles,
        domainFn: (_, i) => data.timestamps[i!],
        measureFn: (d, _) => d,
      ),
      charts.Series<double, DateTime>(
        id: 'KneeAngleSpeed',
        data: data.kneeAngleSpeeds,
        domainFn: (_, i) => data.timestamps[i!],
        measureFn: (d, _) => d,
      ),
    ]);
  }
}
