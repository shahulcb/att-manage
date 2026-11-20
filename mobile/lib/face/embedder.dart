import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceCapture {
  final List<double> embedding;
  final String thumbBase64; // small JPEG of the face so the owner can verify a registration
  FaceCapture(this.embedding, this.thumbBase64);
}

/// The photo is not good enough to use. The message tells the person what to fix.
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

  /// [frontal]: face must look straight into the camera with eyes open (all comparison photos).
  Future<FaceCapture> embedFile(String path, {bool frontal = true, bool eyesOpen = true}) async {
    await _load();
    final faces = await _detector.processImage(InputImage.fromFilePath(path));
    if (faces.isEmpty) throw FaceQualityError('No face found. Look at the camera.');
    if (faces.length > 1) throw FaceQualityError('Only one person should be in view.');
    final f = faces.first;
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
