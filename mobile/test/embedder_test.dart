import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:attendance_app/face/embedder.dart';

void main() {
  test('NV21 frame converts to the right colours', () {
    // 2x2 frame: Y plane (4 bytes) then one V,U pair. Y=82,U=90,V=240 is red.
    final red = nv21ToImage(Uint8List.fromList([82, 82, 82, 82, 240, 90]), 2, 2, 2);
    final p = red.getPixel(1, 1);
    expect(p.r, greaterThan(220)); expect(p.g, lessThan(40)); expect(p.b, lessThan(40));
    // grey: U=V=128 gives r=g=b=Y
    final grey = nv21ToImage(Uint8List.fromList([100, 100, 100, 100, 128, 128]), 2, 2, 2).getPixel(0, 0);
    expect([grey.r, grey.g, grey.b], everyElement(closeTo(100, 1)));
  });

  test('rows padded beyond the width (stride > width) are handled', () {
    // width 2 but stride 4: each Y row has 2 padding bytes (99) that must be ignored
    final bytes = Uint8List.fromList([10, 20, 99, 99, 30, 40, 99, 99, /* V,U row: */ 128, 128, 99, 99]);
    final im = nv21ToImage(bytes, 2, 2, 4);
    expect(im.getPixel(1, 0).r, closeTo(20, 1));
    expect(im.getPixel(0, 1).r, closeTo(30, 1));
    expect(im.getPixel(1, 1).r, closeTo(40, 1));
  });

  test('copyRotate turns the image clockwise (matches ML Kit rotation)', () {
    // [red | blue] rotated 90 degrees clockwise puts red on TOP, blue below
    final im = img.Image(width: 2, height: 1)..setPixelRgb(0, 0, 255, 0, 0)..setPixelRgb(1, 0, 0, 0, 255);
    final r = img.copyRotate(im, angle: 90);
    expect([r.width, r.height], [1, 2]);
    expect(r.getPixel(0, 0).r, 255); expect(r.getPixel(0, 1).b, 255);
    // 270 clockwise = 90 counter-clockwise: red at the BOTTOM
    final l = img.copyRotate(im, angle: 270);
    expect(l.getPixel(0, 1).r, 255); expect(l.getPixel(0, 0).b, 255);
  });

  test('3-plane YUV_420_888 frames pack to the same NV21 as a single-plane frame', () {
    // 4x2 image. Y rows have stride 6 (2 padding bytes). U/V planes: rowStride 4, pixelStride 2 (interleaved, as many phones do).
    final y = Uint8List.fromList([1, 2, 3, 4, 99, 99, 5, 6, 7, 8, 99, 99]);
    final u = Uint8List.fromList([20, 0, 22, 0]);      // U at cols 0 and 2 of the row (pixelStride 2)
    final v = Uint8List.fromList([30, 0, 32, 0]);
    final nv21 = planesToNv21(4, 2, [y, u, v], [6, 4, 4], [1, 2, 2]);
    expect(nv21.sublist(0, 8), [1, 2, 3, 4, 5, 6, 7, 8]);       // Y, padding removed
    expect(nv21.sublist(8), [30, 20, 32, 22]);                     // V,U interleaved (NV21 order)
    // the same picture as one padded NV21 plane gives identical bytes
    final single = Uint8List.fromList([1, 2, 3, 4, 99, 99, 5, 6, 7, 8, 99, 99, 30, 20, 32, 22, 99, 99]);
    expect(planesToNv21(4, 2, [single], [6], [1]), nv21);
  });
}
