import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../theme.dart';
import 'embedder.dart';

enum StepKind { straight, turnSide, turnOtherSide, smileShot, blink, turn, smile }

class ScanStep {
  final StepKind kind;
  const ScanStep(this.kind);
  bool get capture => kind == StepKind.straight || kind == StepKind.turnSide || kind == StepKind.turnOtherSide || kind == StepKind.smileShot;
  bool get frontal => kind == StepKind.straight || kind == StepKind.smileShot;
  String get action => kind == StepKind.blink ? 'BLINK' : kind == StepKind.turn ? 'TURN' : kind == StepKind.smile ? 'SMILE' : '';
  String get label => switch (kind) {
        StepKind.straight => 'Look straight at the camera',
        StepKind.turnSide => 'Slowly turn your head to one side',
        StepKind.turnOtherSide => 'Now turn to the other side',
        StepKind.smileShot => 'Look straight and smile a little',
        StepKind.blink => 'Blink once',
        StepKind.turn => 'Turn your head to either side',
        StepKind.smile => 'Smile',
      };
}

class ScanResult {
  final List<List<double>> embeddings; // one per capture step
  final List<String> actions;          // liveness actions completed, in order
  final String photo;                  // base64 thumbnail of the first capture
  ScanResult(this.embeddings, this.actions, this.photo);
}

/// Registration: 4 easy photos, all facing the camera (the owner checks the photo; the system keeps learning on later punches).
List<ScanStep> registerSteps() => const [
      ScanStep(StepKind.straight), ScanStep(StepKind.straight), ScanStep(StepKind.smileShot), ScanStep(StepKind.straight),
    ];

/// Punch: photo, the actions the SERVER asked for (random each time), photo again.
List<ScanStep> punchSteps(List actions) => [
      const ScanStep(StepKind.straight),
      for (final a in actions) ScanStep(a == 'BLINK' ? StepKind.blink : a == 'SMILE' ? StepKind.smile : StepKind.turn),
      const ScanStep(StepKind.straight),
    ];

class ScanScreen extends StatefulWidget {
  final String title;
  final List<ScanStep> steps;
  const ScanScreen({super.key, required this.title, required this.steps});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  CameraController? _cam;
  final _detector = FaceDetector(options: FaceDetectorOptions(enableClassification: true, performanceMode: FaceDetectorMode.fast));
  int _step = 0;
  bool _busy = false, _capturing = false, _done = false;
  bool _eyesWereOpen = false, _eyesClosed = false;
  double _firstSide = 0;
  DateTime _cooldown = DateTime.now();
  String _hint = 'Starting camera…';
  final _embeddings = <List<double>>[];
  final _actions = <String>[];
  String _photo = '';
  DateTime _stepStart = DateTime.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _init();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted && !_done && !_capturing) setState(() {}); });
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      final c = CameraController(front, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await c.initialize();
      if (!mounted) return;
      _cam = c;
      setState(() => _hint = widget.steps[0].label);
      await c.startImageStream(_onFrame);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _hint = e.code == 'CameraAccessDenied' ? 'Camera permission denied. Enable it in Settings.' : 'Camera error: ${e.description}');
    } catch (_) {
      if (mounted) setState(() => _hint = 'No camera available on this device');
    }
  }

  InputImage? _toInput(CameraImage img) {
    final cam = _cam!;
    final rot = InputImageRotationValue.fromRawValue(cam.description.sensorOrientation);
    if (rot == null || img.format.group != ImageFormatGroup.nv21 || img.planes.length != 1) return null;
    return InputImage.fromBytes(
      bytes: img.planes.first.bytes,
      metadata: InputImageMetadata(size: Size(img.width.toDouble(), img.height.toDouble()), rotation: rot, format: InputImageFormat.nv21, bytesPerRow: img.planes.first.bytesPerRow),
    );
  }

  void _resetStepState() { _eyesWereOpen = false; _eyesClosed = false; _stepStart = DateTime.now(); }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || _capturing || _done || DateTime.now().isBefore(_cooldown)) return;
    _busy = true;
    try {
      final input = _toInput(image);
      if (input == null) return;
      final faces = await _detector.processImage(input);
      if (!mounted) return;
      if (faces.isEmpty) { _setHint('No face found. Move closer.'); return; }
      if (faces.length > 1) { _setHint('Only one person should be in view.'); return; }
      final f = faces.first;
      final step = widget.steps[_step];
      final y = f.headEulerAngleY ?? 0;
      final l = f.leftEyeOpenProbability ?? 1, r = f.rightEyeOpenProbability ?? 1;
      final smile = f.smilingProbability ?? 0;
      final eyesOpen = l > 0.35 && r > 0.35;

      switch (step.kind) {
        case StepKind.straight:
          if (y.abs() < 14 && (f.headEulerAngleX ?? 0).abs() < 16 && (f.headEulerAngleZ ?? 0).abs() < 14 && eyesOpen) { await _capture(); } else { _setHint(step.label); }
        case StepKind.smileShot:
          if (y.abs() < 14 && eyesOpen && smile > 0.25) { await _capture(); } else { _setHint(step.label); }
        case StepKind.turnSide:
          if (y.abs() > 15 && eyesOpen) { _firstSide = y; await _capture(); } else { _setHint(step.label); }
        case StepKind.turnOtherSide:
          if (y.abs() > 15 && y * _firstSide < 0 && eyesOpen) { await _capture(); } else { _setHint(step.label); }
        case StepKind.blink:
          if (eyesOpen) {
            if (_eyesClosed) { _advanceAction(step); return; }
            _eyesWereOpen = true;
          } else if (l < 0.3 && r < 0.3 && _eyesWereOpen) { _eyesClosed = true; }
          _setHint(step.label);
        case StepKind.turn:
          if (y.abs() > 15) { _advanceAction(step); return; }
          _setHint(step.label);
        case StepKind.smile:
          if (smile > 0.6) { _advanceAction(step); return; }
          _setHint(step.label);
      }
    } catch (_) {/* ignore frame errors */} finally { _busy = false; }
  }

  void _advanceAction(ScanStep step) {
    _actions.add(step.action);
    HapticFeedback.selectionClick();
    _resetStepState();
    setState(() { _step++; _hint = widget.steps[_step].label; });
  }

  void _setHint(String h) { if (h != _hint) setState(() => _hint = h); }

  Future<void> _capture() async {
    _capturing = true;
    final step = widget.steps[_step];
    try {
      setState(() => _hint = 'Hold still…');
      final shot = await _cam!.takePicture();
      FaceCapture cap;
      try {
        cap = await FaceEmbedder.i.embedFile(shot.path, frontal: step.frontal);
      } on FaceQualityError catch (e) {
        _cooldown = DateTime.now().add(const Duration(milliseconds: 1200));
        _setHint(e.message);
        return;
      } finally { try { File(shot.path).deleteSync(); } catch (_) {} }
      HapticFeedback.lightImpact();
      _embeddings.add(cap.embedding);
      if (_photo.isEmpty) _photo = cap.thumbBase64;
      _resetStepState();
      if (_step + 1 >= widget.steps.length) {
        _done = true;
        await _cam?.stopImageStream().catchError((_) {});
        if (mounted) Navigator.pop(context, ScanResult(_embeddings, _actions, _photo));
      } else {
        setState(() { _step++; _hint = widget.steps[_step].label; });
        _cooldown = DateTime.now().add(const Duration(milliseconds: 600));
      }
    } catch (_) {
      _setHint('Capture failed, try again');
    } finally { _capturing = false; }
  }

  @override
  void dispose() {
    _done = true;
    _cam?.dispose();
    _tick?.cancel();
    _detector.close();
    super.dispose();
  }

  bool get _denied => _hint.startsWith('Camera permission denied');

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    final progress = widget.steps.isEmpty ? 0.0 : (_done ? 1.0 : _step / widget.steps.length);
    return PopScope(
      canPop: !_capturing,
      child: Scaffold(
        backgroundColor: C.ink,
        appBar: AppBar(backgroundColor: C.ink, foregroundColor: Colors.white, title: Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(children: [
                const SizedBox(height: 8),
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 3 / 4,
                      child: Stack(alignment: Alignment.center, children: [
                        // progress ring around the camera frame
                        Positioned.fill(child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: progress), duration: const Duration(milliseconds: 500), curve: Curves.easeOut,
                          builder: (_, v, _) => CustomPaint(painter: _FramePainter(v)),
                        )),
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(200),
                            child: cam == null || !cam.value.isInitialized
                                ? ColoredBox(color: Colors.white10, child: Center(child: _denied
                                    ? Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                                        const Icon(Icons.no_photography_outlined, color: Colors.white70, size: 44), const SizedBox(height: 12),
                                        const Text('Camera access is off', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 12),
                                        FilledButton(style: FilledButton.styleFrom(backgroundColor: C.accent, foregroundColor: C.ink, minimumSize: const Size(160, 46)), onPressed: Geolocator.openAppSettings, child: const Text('Open settings')),
                                      ]))
                                    : const CircularProgressIndicator(color: C.accent)))
                                : FittedBox(fit: BoxFit.cover, child: SizedBox(width: cam.value.previewSize!.height, height: cam.value.previewSize!.width, child: CameraPreview(cam))),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                  child: Column(children: [
                    SizedBox(height: 56, child: Center(child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a), child: c)),
                      child: Text(_hint, key: ValueKey(_hint), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700)),
                    ))),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (var i = 0; i < widget.steps.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300), margin: const EdgeInsets.symmetric(horizontal: 3), height: 6,
                          width: i == _step && !_done ? 30 : 18,
                          decoration: BoxDecoration(color: i < _step || _done ? C.accent : (i == _step ? Colors.white : Colors.white24), borderRadius: BorderRadius.circular(3)),
                        ),
                    ]),
                    SizedBox(height: 52, child: !_capturing && !_done && widget.steps[_step.clamp(0, widget.steps.length - 1)].capture && DateTime.now().difference(_stepStart).inSeconds >= 6
                        ? Center(child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white54), minimumSize: const Size(190, 44)),
                            onPressed: _capture, icon: const Icon(Icons.camera_alt_outlined), label: const Text('Take photo now')))
                        : const Center(child: Text('Face the light. Only you in view.', style: TextStyle(color: Colors.white38, fontSize: 12)))),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _FramePainter extends CustomPainter {
  final double v;
  _FramePainter(this.v);
  @override
  void paint(Canvas c, Size s) {
    final rect = Rect.fromLTWH(4, 4, s.width - 8, s.height - 8);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(s.width));
    c.drawRRect(rr, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..color = Colors.white12);
    final path = Path()..addRRect(rr);
    final m = path.computeMetrics().first;
    c.drawPath(m.extractPath(0, m.length * v), Paint()..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.round..color = C.accent);
  }
  @override
  bool shouldRepaint(_FramePainter o) => o.v != v;
}
