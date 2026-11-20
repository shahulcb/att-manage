import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Ring that animates from 0 to [value] (0..1).
class ProgressRing extends StatelessWidget {
  final double value, size, stroke;
  final Color color, track;
  final Widget? center;
  const ProgressRing({super.key, required this.value, this.size = 96, this.stroke = 10, this.color = C.accent, this.track = const Color(0x22FFFFFF), this.center});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)), duration: const Duration(milliseconds: 1100), curve: Curves.easeOutCubic,
        builder: (_, v, _) => SizedBox(width: size, height: size, child: CustomPaint(painter: _RingPainter(v, stroke, color, track), child: Center(child: center))),
      );
}

class _RingPainter extends CustomPainter {
  final double v, stroke;
  final Color color, track;
  _RingPainter(this.v, this.stroke, this.color, this.track);
  @override
  void paint(Canvas c, Size s) {
    final r = (math.min(s.width, s.height) - stroke) / 2;
    final rect = Rect.fromCircle(center: s.center(Offset.zero), radius: r);
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round;
    c.drawArc(rect, 0, math.pi * 2, false, p..color = track);
    c.drawArc(rect, -math.pi / 2, math.pi * 2 * v, false, p..color = color);
  }
  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color;
}

/// Row of small dots, the first [value]*[count] filled (like the "Goal" strip in the reference).
class DotsProgress extends StatelessWidget {
  final double value;
  final int count;
  final Color on, off;
  const DotsProgress({super.key, required this.value, this.count = 18, this.on = C.ink, this.off = const Color(0x33000000)});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)), duration: const Duration(milliseconds: 1000), curve: Curves.easeOut,
        builder: (_, v, _) => Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          for (var i = 0; i < count; i++) Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: i < (v * count).round() ? on : off)),
        ]),
      );
}

class Bar {
  final String label;
  final double value;
  final Color color;
  final String tip;
  const Bar(this.label, this.value, this.color, this.tip);
}

/// Bars grow from the bottom; tap one to see its tooltip (like the reference chart). Scrolls sideways when there are many.
class BarChart extends StatefulWidget {
  final List<Bar> bars;
  final double height;
  const BarChart({super.key, required this.bars, this.height = 190});
  @override
  State<BarChart> createState() => _BarChartState();
}

class _BarChartState extends State<BarChart> {
  int? sel;
  @override
  Widget build(BuildContext context) {
    final maxV = widget.bars.fold<double>(1, (m, b) => math.max(m, b.value));
    final chartH = widget.height - 52;
    return LayoutBuilder(builder: (context, box) {
      final slot = math.max(34.0, box.maxWidth / math.max(1, widget.bars.length));
      final row = SizedBox(
        width: slot * widget.bars.length, height: widget.height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < widget.bars.length; i++)
            SizedBox(width: slot, child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => sel = sel == i ? null : i),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                SizedBox(height: 26, child: AnimatedOpacity(
                  opacity: sel == i ? 1 : 0, duration: const Duration(milliseconds: 160),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(10)),
                      child: Text(widget.bars[i].tip, maxLines: 1, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                )),
                const SizedBox(height: 4),
                TweenAnimationBuilder<double>(
                  key: ValueKey('${widget.bars.length}-$i-${widget.bars[i].value}'),
                  tween: Tween(begin: 0, end: widget.bars[i].value / maxV), duration: Duration(milliseconds: 650 + i * 40), curve: Curves.easeOutCubic,
                  builder: (_, v, _) => AnimatedContainer(
                    duration: const Duration(milliseconds: 180), width: sel == i ? 26 : 22, height: math.max(6, chartH * v),
                    decoration: BoxDecoration(color: widget.bars[i].color, borderRadius: BorderRadius.circular(12), border: sel == i ? Border.all(color: C.ink, width: 2) : null),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(height: 14, child: Text(widget.bars[i].label, style: TextStyle(fontSize: 10, fontWeight: sel == i ? FontWeight.w800 : FontWeight.w600, color: C.muted))),
              ]),
            )),
        ]),
      );
      return slot * widget.bars.length > box.maxWidth ? SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: row) : row;
    });
  }
}
