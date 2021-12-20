import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:squat_deeply/keypoints.dart';
import 'package:squat_deeply/predictor.dart';
import 'package:squat_deeply/squat_counter.dart';

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
  final bool _showChart = false;
  const SquatCamPage({Key? key, required this.title, required this.cameras})
      : super(key: key);

  @override
  _SquatCamPageState createState() => _SquatCamPageState();
}

class _SquatCamPageState extends State<SquatCamPage> {
  final Predictor _predictor = Predictor();

  int _currentCam = 0;
  CameraController? _cameraController;

  SquatCounter _counter = const SquatCounter.init();
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

    if (!_cntMutex && _counter.isStanding) {
      _cntMutex = true;
      var msg = _counter.isUnderParallel ? "Deep" : "Shallow";
      _shallowAlert = Container(
        alignment: Alignment.center,
        height: height,
        child: Text(msg,
            style: const TextStyle(color: Colors.redAccent, fontSize: 48)),
      );
      Timer(const Duration(seconds: 2), () {
        setState(() {
          _cntMutex = false;
          _shallowAlert = Container();
        });
      });
      setState(() {});
    }

    final previewStack = <Widget>[
      CamView(
        cameraController: _cameraController,
      ),
      _shallowAlert,
    ];

    if (widget._showChart) {
      previewStack.add(Container(
        width: width,
        height: height,
        alignment: Alignment.centerLeft,
        child: AngleChart(_counter),
      ));
    }

    if (_counter.last != null) {
      final kp = _counter.last!;
      previewStack
          .add(KeyPointsPreview(keyPoints: kp, width: width, height: height));

      final msgs = [
        kp.score.toStringAsFixed(3),
        _frameRate.toStringAsFixed(3) + " fps",
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
      _counter = const SquatCounter.init();
    });
    await _cameraController!.startImageStream((image) async {
      if (!_predictor.ready) return;
      var res = await _predictor.predict(image);
      if (res != null && res.keyPoints.score > 0.3) {
        _frameRate = 1000 / res.duration.inMilliseconds.toDouble();
        _counter = _counter.push(res.keyPoints);
      }
      if (mounted) setState(() {});
    });
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

class CamView extends StatelessWidget {
  const CamView({
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

class AngleChart extends StatelessWidget {
  final SquatCounter counter;
  const AngleChart(
    this.counter, {
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _AngleChartPainter(counter),
      );
}

class _AngleChartPainter extends CustomPainter {
  final SquatCounter counter;
  const _AngleChartPainter(this.counter);
  @override
  void paint(Canvas canvas, Size size) {
    final main = Paint()..color = Colors.blue;
    main.strokeWidth = 5;
    final sub1 = Paint()..color = Colors.green;
    canvas.drawLine(const Offset(0, 0), const Offset(300, 0), main);

    counter.history.asMap().forEach((i, v) {
      if (v.leftKneeAngle != null) {
        final x = 10 + 5 * i;
        final y = 30 * (v.leftKneeAngle! - (11 / 18) * pi);
        canvas.drawCircle(Offset(x.toDouble(), y), 3, main);
      }
    });

    counter.hipSpeeds.asMap().forEach((i, v) {
      final x = 10 + 5 * i;
      final y = 2000 * v;
      canvas.drawCircle(Offset(x.toDouble(), y), 3, sub1);
    });
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
