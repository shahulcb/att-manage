import 'dart:async';
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
      for (final a in actions) ScanStep(a == 'BLINK' ? StepKind.blink : a == 'SMILE' ? StepKind.smile : StepKind.turn),
      const ScanStep(StepKind.straight),
    ];

class ScanScreen extends StatefulWidget {
  final String title;
  final List<ScanStep> steps;
  /// Punch mode: take the first photo silently as soon as the face is ready, so the person only does the action(s) and is done.
  final bool preCapture;
  const ScanScreen({super.key, required this.title, required this.steps, this.preCapture = false});
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
  int _preOk = 0;             // consecutive ready frames before the silent first photo
  int _frames = 0;
  CameraImage? _last;         // newest camera frame: lets us capture even when live face detection is not working on this phone
  String _diag = '';          // shown on screen in diagnostic builds (FACE_DEBUG)
  int _okFrames = 0;          // consecutive frames that meet the step's conditions (auto-capture needs a steady pose)
  bool _manual = false;       // "Take photo now" pressed: capture the next clear frame without waiting for the pose
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
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _done || _capturing) return;
      setState(() {});
      // Fallback: live detection did not capture within 5 s -> try the newest frame directly (face is verified on the picture)
      final i = _step.clamp(0, widget.steps.length - 1);
      if (widget.preCapture && _embeddings.isEmpty && !widget.steps[i].capture && _last != null && DateTime.now().difference(_stepStart).inSeconds >= 5 && !DateTime.now().isBefore(_cooldown)) {
        faceLog('fallback pre-capture from the newest frame');
        _preCapture(_last!);
        return;
      }
      if (widget.steps[i].capture && _last != null && DateTime.now().difference(_stepStart).inSeconds >= 5 && !DateTime.now().isBefore(_cooldown)) {
        faceLog('fallback capture from the newest frame (step=${widget.steps[i].kind.name})');
        if (kFaceDebug) _diag = 'fallback capture (live detection gave no result for 5s)';
        _capture(_last!);
      }
    });
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      final c = CameraController(front, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await c.initialize();
      if (!mounted) return;
      _cam = c;
      faceLog('camera ${front.name} sensor=${front.sensorOrientation} preview=${c.value.previewSize} lens=${front.lensDirection} cams=${cams.length}');
      setState(() => _hint = widget.steps[0].label);
      await c.startImageStream(_onFrame);
    } on CameraException catch (e) {
      faceLog('camera init CameraException ${e.code}: ${e.description}');
      if (!mounted) return;
      setState(() => _hint = e.code == 'CameraAccessDenied' ? 'Camera permission denied. Enable it in Settings.' : 'Camera error: ${e.description}');
    } catch (e, st) {
      faceLog('camera init failed: $e\n$st');
      if (mounted) setState(() => _hint = 'No camera available on this device');
    }
  }

  InputImage? _toInput(CameraImage img) {
    final cam = _cam!;
    final rot = InputImageRotationValue.fromRawValue(cam.description.sensorOrientation);
    if (rot == null || (img.planes.length != 1 && img.planes.length != 3)) {
      _diag = 'unsupported frame: planes=${img.planes.length} fmt=${img.format.group} rot=$rot';
      if (_frames < 3) faceLog(_diag);
      return null;
    }
    // repack to plain NV21 whatever layout the phone sends (single-plane NV21 or 3-plane YUV_420_888)
    return InputImage.fromBytes(
      bytes: frameToNv21(img),
      metadata: InputImageMetadata(size: Size(img.width.toDouble(), img.height.toDouble()), rotation: rot, format: InputImageFormat.nv21, bytesPerRow: img.width),
    );
  }

  void _resetStepState() { _eyesWereOpen = false; _eyesClosed = false; _okFrames = 0; _manual = false; _stepStart = DateTime.now(); }

  Future<void> _onFrame(CameraImage image) async {
    _last = image;
    if (_busy || _capturing || _done || DateTime.now().isBefore(_cooldown)) return;
    _busy = true;
    try {
      _frames++;
      final input = _toInput(image);
      if (input == null) return;
      final faces = await _detector.processImage(input);
      if (kFaceDebug && (_frames <= 2 || _frames % 5 == 0)) {
        final fc = faces.length == 1 ? faces.first : null;
        final t = 'f#$_frames ${image.width}x${image.height} planes=${image.planes.length} faces=${faces.length}${fc == null ? '' : ' y=${fc.headEulerAngleY?.toStringAsFixed(0)} x=${fc.headEulerAngleX?.toStringAsFixed(0)} z=${fc.headEulerAngleZ?.toStringAsFixed(0)} eyes=${fc.leftEyeOpenProbability?.toStringAsFixed(1)}/${fc.rightEyeOpenProbability?.toStringAsFixed(1)}'} step=${widget.steps[_step.clamp(0, widget.steps.length - 1)].kind.name} ok=$_okFrames';
        if (mounted) setState(() => _diag = t);
      }
      if (_frames <= 2 || _frames % 15 == 0) faceLog('frame#$_frames ${image.width}x${image.height} fmt=${image.format.group} planes=${image.planes.length} faces=${faces.length}${faces.length == 1 ? ' y=${faces.first.headEulerAngleY?.toStringAsFixed(0)} eyes=${faces.first.leftEyeOpenProbability?.toStringAsFixed(2)} smile=${faces.first.smilingProbability?.toStringAsFixed(2)}' : ''} step=${widget.steps[_step.clamp(0, widget.steps.length - 1)].kind.name} okFrames=$_okFrames');
      if (!mounted) return;
      if (faces.isEmpty) { _setHint('No face found. Move closer.'); return; }
      if (faces.length > 1) { _setHint('Only one person should be in view.'); return; }
      final f = faces.first;
      final step = widget.steps[_step];
      final y = f.headEulerAngleY ?? 0;
      final l = f.leftEyeOpenProbability ?? 1, r = f.rightEyeOpenProbability ?? 1;
      final smile = f.smilingProbability ?? 0;
      final eyesOpen = l > 0.35 && r > 0.35;

      if (widget.preCapture && _embeddings.isEmpty && !step.capture) {
        final ready = y.abs() < 14 && (f.headEulerAngleX ?? 0).abs() < 16 && (f.headEulerAngleZ ?? 0).abs() < 14 && eyesOpen;
        _preOk = ready ? _preOk + 1 : 0;
        if (_preOk >= 2) { _preOk = 0; await _preCapture(image); } else { _setHint('Look at the camera'); }
        return;
      }

      bool ok = false;
      switch (step.kind) {
        case StepKind.straight:
          ok = y.abs() < 14 && (f.headEulerAngleX ?? 0).abs() < 16 && (f.headEulerAngleZ ?? 0).abs() < 14 && eyesOpen;
        case StepKind.smileShot:
          ok = y.abs() < 14 && eyesOpen && smile > 0.25;
        case StepKind.turnSide:
          ok = y.abs() > 15 && eyesOpen;
          if (ok) _firstSide = y;
        case StepKind.turnOtherSide:
          ok = y.abs() > 15 && y * _firstSide < 0 && eyesOpen;
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
      if (step.capture) {
        _okFrames = (ok || _manual) ? _okFrames + 1 : 0;
        if (_okFrames >= (_manual ? 1 : (widget.preCapture ? 2 : 3))) { _okFrames = 0; await _capture(image); }   // about a third of a second of steady pose
        else if (ok) { _setHint('Hold still…'); }
        else { _setHint(step.label); }
      }
    } catch (e, st) {
      if (kFaceDebug && mounted) setState(() => _diag = 'frame error: ${e.runtimeType} $e');
      if (_frames < 50 || _frames % 30 == 0) faceLog('frame error (frame#$_frames): $e\n$st');
    } finally { _busy = false; }
  }

  void _advanceAction(ScanStep step) {
    _actions.add(step.action);
    HapticFeedback.selectionClick();
    _resetStepState();
    setState(() { _step++; _hint = widget.steps[_step].label; });
  }

  void _setHint(String h) { if (h != _hint) setState(() => _hint = h); }

  /// The silent first photo (punch mode): same checks as any capture, but no step is consumed.
  Future<void> _preCapture(CameraImage image) async {
    _capturing = true;
    try {
      final rot = InputImageRotationValue.fromRawValue(_cam!.description.sensorOrientation)?.rawValue ?? 0;
      final cap = await FaceEmbedder.i.embedFrame(image, rot, frontal: true);
      _embeddings.add(cap.embedding);
      if (_photo.isEmpty) _photo = cap.thumbBase64;
      HapticFeedback.selectionClick();
      _resetStepState();
      if (mounted) setState(() => _hint = widget.steps[_step].label);
    } on FaceQualityError catch (e) {
      faceLog('pre-capture rejected: ${e.message}');
      _cooldown = DateTime.now().add(const Duration(milliseconds: 800));
      _setHint(e.message);
    } catch (e, st) {
      faceLog('pre-capture exception: $e\n$st');
      _cooldown = DateTime.now().add(const Duration(milliseconds: 1500));
      _setHint('Could not read the camera frame. Trying again…');
    } finally { _capturing = false; }
  }

  Future<void> _capture(CameraImage image) async {
    _capturing = true;
    final step = widget.steps[_step];
    try {
      setState(() => _hint = 'Hold still…');
      final rot = InputImageRotationValue.fromRawValue(_cam!.description.sensorOrientation)?.rawValue ?? 0;
      FaceCapture cap;
      faceLog('capture step=${step.kind.name} manual=$_manual');
      try {
        cap = await FaceEmbedder.i.embedFrame(image, rot, frontal: step.frontal);
      } on FaceQualityError catch (e) {
        faceLog('rejected: ${e.message}');
        _manual = false;
        _cooldown = DateTime.now().add(const Duration(milliseconds: 1000));
        _setHint(e.message);
        return;
      }
      _manual = false;
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
        _cooldown = DateTime.now().add(const Duration(milliseconds: 700));
      }
    } catch (e, st) {
      faceLog('capture exception: $e\n$st');
      if (kFaceDebug && mounted) setState(() => _diag = 'capture error: ${e.runtimeType} $e');
      // show the real reason (and wait a moment) instead of retrying in a tight loop
      _manual = false;
      _cooldown = DateTime.now().add(const Duration(milliseconds: 1500));
      _setHint('Could not read the camera frame (${e.runtimeType}). Trying again…');
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
                            onPressed: () { if (_last != null && !_capturing) _capture(_last!); }, icon: const Icon(Icons.camera_alt_outlined), label: const Text('Take photo now')))
                        : Center(child: Text(kFaceDebug && _diag.isNotEmpty ? _diag : 'Face the light. Only you in view.', textAlign: TextAlign.center, maxLines: 3, style: TextStyle(color: kFaceDebug ? C.accent : Colors.white38, fontSize: kFaceDebug ? 11 : 12)))),
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
