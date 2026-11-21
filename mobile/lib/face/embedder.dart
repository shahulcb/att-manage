import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:camera/camera.dart' show CameraImage;
import 'package:path_provider/path_provider.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

/// Packs camera planes into plain NV21 (Y plane, then interleaved V/U), with no row padding (stride == width).
/// Works for a single-plane NV21 frame and for the 3-plane YUV_420_888 layout many phones deliver.
Uint8List planesToNv21(int width, int height, List<Uint8List> planes, List<int> rowStrides, List<int> pixelStrides) {
  final out = Uint8List(width * height * 3 ~/ 2);
  final yStride = rowStrides[0];
  for (var y = 0; y < height; y++) {
    out.setRange(y * width, y * width + width, planes[0], y * yStride);
  }
  final ySize = width * height;
  if (planes.length == 1) {
    // NV21 already: V/U rows follow the Y rows (with the same row stride)
    final uvStart = yStride * height;
    for (var r = 0; r < height ~/ 2; r++) {
      out.setRange(ySize + r * width, ySize + r * width + width, planes[0], uvStart + r * yStride);
    }
  } else {
    final u = planes[1], v = planes[2];
    final uR = rowStrides[1], vR = rowStrides[2], uP = pixelStrides[1], vP = pixelStrides[2];
    for (var r = 0; r < height ~/ 2; r++) {
      for (var c = 0; c < width ~/ 2; c++) {
        out[ySize + r * width + 2 * c] = v[r * vR + c * vP];
        out[ySize + r * width + 2 * c + 1] = u[r * uR + c * uP];
      }
    }
  }
  return out;
}

Uint8List frameToNv21(CameraImage f) => planesToNv21(f.width, f.height, [for (final p in f.planes) p.bytes], [for (final p in f.planes) p.bytesPerRow], [for (final p in f.planes) p.bytesPerPixel ?? 1]);

/// Converts an Android NV21 camera frame (Y plane followed by interleaved V/U) to an RGB image.
/// [stride] is the number of bytes per row of the Y plane (it can be larger than [width]).
img.Image nv21ToImage(Uint8List bytes, int width, int height, int stride) {
  final rgb = Uint8List(width * height * 3);
  final uvStart = stride * height;
  var o = 0;
  for (var y = 0; y < height; y++) {
    final uvRow = uvStart + (y >> 1) * stride;
    for (var x = 0; x < width; x++) {
      final yy = bytes[y * stride + x];
      final uv = uvRow + (x & ~1);
      final v = bytes[uv] - 128, u = bytes[uv + 1] - 128;
      rgb[o++] = (yy + 1.402 * v).round().clamp(0, 255);
      rgb[o++] = (yy - 0.344136 * u - 0.714136 * v).round().clamp(0, 255);
      rgb[o++] = (yy + 1.772 * u).round().clamp(0, 255);
    }
  }
  return img.Image.fromBytes(width: width, height: height, bytes: rgb.buffer, numChannels: 3);
}

class FaceCapture {
  final List<double> embedding;
  final String thumbBase64; // small JPEG of the face so the owner can verify a registration
  FaceCapture(this.embedding, this.thumbBase64);
}

/// The photo is not good enough to use. The message tells the person what to fix.
/// Diagnostic logging: always on in debug builds, and in release when built with --dart-define=FACE_DEBUG=true
const kFaceDebug = bool.fromEnvironment('FACE_DEBUG');
void faceLog(String m) { if (kDebugMode || kFaceDebug) debugPrint('FACEDBG $m'); }
void _log(String m) => faceLog(m);

class FaceQualityError implements Exception {
  final String message;
  FaceQualityError(this.message);
  @override
  String toString() => message;
}

/// Turns a photo into a 192-d MobileFaceNet embedding (runs on the device; matching happens on the server).
/// Every photo must pass quality checks first: bad photos are the biggest cause of wrong matches.
class FaceEmbedder {
  FaceEmbedder._();
  static final FaceEmbedder i = FaceEmbedder._();
  Interpreter? _it;
  final _detector = FaceDetector(options: FaceDetectorOptions(enableClassification: true, performanceMode: FaceDetectorMode.accurate));

  Future<void> _load() async => _it ??= await Interpreter.fromAsset('assets/models/mobile_face_net.tflite');

  /// Capture from a live camera frame (no still photo needed: many phones cannot take a photo while streaming video).
  /// [rotation] = degrees the frame must be turned clockwise to be upright (the sensor orientation, as given to ML Kit).
  /// The frame is made upright, saved as a temporary JPEG, and goes through exactly the same checks as any photo.
  Future<FaceCapture> embedFrame(CameraImage frame, int rotation, {bool frontal = true, bool eyesOpen = true}) async {
    _log('embedFrame ${frame.width}x${frame.height} format=${frame.format.group} planes=${frame.planes.length} bytes=${frame.planes.first.bytes.length} stride=${frame.planes.first.bytesPerRow} expected>=${frame.planes.first.bytesPerRow * frame.height * 3 ~/ 2} rotation=$rotation');
    var image = nv21ToImage(frameToNv21(frame), frame.width, frame.height, frame.width);
    if (rotation % 360 != 0) image = img.copyRotate(image, angle: rotation % 360);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/frame_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(img.encodeJpg(image, quality: 92));
    try {
      return await embedFile(file.path, frontal: frontal, eyesOpen: eyesOpen);
    } finally {
      try { await file.delete(); } catch (_) {}
    }
  }

  /// [frontal]: face must look straight into the camera with eyes open (all comparison photos).
  Future<FaceCapture> embedFile(String path, {bool frontal = true, bool eyesOpen = true}) async {
    await _load();
    final faces = await _detector.processImage(InputImage.fromFilePath(path));
    _log('embedFile faces=${faces.length}');
    if (faces.isEmpty) throw FaceQualityError('No face found. Look at the camera.');
    if (faces.length > 1) throw FaceQualityError('Only one person should be in view.');
    final f = faces.first;
    _log('  pose y=${f.headEulerAngleY?.toStringAsFixed(1)} x=${f.headEulerAngleX?.toStringAsFixed(1)} z=${f.headEulerAngleZ?.toStringAsFixed(1)} eyes=${f.leftEyeOpenProbability?.toStringAsFixed(2)}/${f.rightEyeOpenProbability?.toStringAsFixed(2)} box=${f.boundingBox}');
    if (frontal) {
      if ((f.headEulerAngleY ?? 0).abs() > 18 || (f.headEulerAngleX ?? 0).abs() > 20 || (f.headEulerAngleZ ?? 0).abs() > 18) {
        throw FaceQualityError('Face the camera straight on.');
      }
    }
    if (eyesOpen && ((f.leftEyeOpenProbability ?? 1) < 0.2 || (f.rightEyeOpenProbability ?? 1) < 0.2)) {
      throw FaceQualityError('Keep your eyes open.');
    }

    var image = img.decodeImage(await File(path).readAsBytes());
    if (image == null) throw FaceQualityError('Could not read the photo. Try again.');
    image = img.bakeOrientation(image);
    final b = f.boundingBox;
    _log('  image=${image.width}x${image.height} faceWidthRatio=${(b.width / image.width).toStringAsFixed(2)}');
    if (b.width < image.width * 0.2) throw FaceQualityError('Move a little closer to the camera.');

    final side = math.max(b.width, b.height) * 1.1;
    final x = (b.center.dx - side / 2).clamp(0, image.width - 1).toInt();
    final y = (b.center.dy - side / 2).clamp(0, image.height - 1).toInt();
    final w = math.min(side.toInt(), image.width - x), h = math.min(side.toInt(), image.height - y);
    final crop = img.copyResize(img.copyCrop(image, x: x, y: y, width: w, height: h), width: 112, height: 112);

    // light + sharpness checks on the 112px crop
    final gray = Float32List(112 * 112);
    var sum = 0.0;
    for (var py = 0; py < 112; py++) {
      for (var px = 0; px < 112; px++) {
        final p = crop.getPixel(px, py);
        final g = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
        gray[py * 112 + px] = g.toDouble();
        sum += g;
      }
    }
    final mean = sum / (112 * 112);
    _log('  brightness=${mean.toStringAsFixed(0)}');
    if (mean < 30) throw FaceQualityError('Too dark. Move to a brighter place.');
    if (mean > 230) throw FaceQualityError('Too bright or glare. Avoid strong light behind or on your face.');
    var lapSum = 0.0, lapSq = 0.0, cnt = 0;
    for (var py = 1; py < 111; py++) {
      for (var px = 1; px < 111; px++) {
        final c = gray[py * 112 + px];
        final l = 4 * c - gray[py * 112 + px - 1] - gray[py * 112 + px + 1] - gray[(py - 1) * 112 + px] - gray[(py + 1) * 112 + px];
        lapSum += l; lapSq += l * l; cnt++;
      }
    }
    final variance = lapSq / cnt - math.pow(lapSum / cnt, 2);
    _log('  sharpness=${variance.toStringAsFixed(1)} (needs >= 10)');
    if (variance < 10) throw FaceQualityError('Photo is blurry. Hold the phone steady.');

    final input = Float32List(112 * 112 * 3);
    var k = 0;
    for (final p in crop) {
      input[k++] = (p.r - 127.5) / 128;
      input[k++] = (p.g - 127.5) / 128;
      input[k++] = (p.b - 127.5) / 128;
    }
    final out = List.generate(1, (_) => List.filled(192, 0.0));
    _it!.run(input.reshape([1, 112, 112, 3]), out);
    final v = out[0];
    final n = math.sqrt(v.fold<double>(0, (a, e) => a + e * e));
    return FaceCapture(v.map((e) => e / (n == 0 ? 1 : n)).toList(), _thumb(crop));
  }

  /// Small JPEG for the owner to verify a registration. Shrinks until it is comfortably under the server limit.
  static String _thumb(img.Image crop) {
    var size = 112, q = 60;
    var out = '';
    for (var i = 0; i < 6; i++) {
      final t = size == crop.width ? crop : img.copyResize(crop, width: size, height: size, interpolation: img.Interpolation.average);
      out = base64Encode(img.encodeJpg(t, quality: q));
      if (out.length <= 30000) break;
      size = (size * 0.85).round();
      q = (q - 8).clamp(30, 100);
    }
    return out.length <= 30000 ? out : '';
  }
}
