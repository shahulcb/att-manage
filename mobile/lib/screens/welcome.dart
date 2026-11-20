import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../api.dart';
import '../main.dart' show fadeRoute;
import '../theme.dart';
import '../widgets/ui.dart';
import 'login.dart';

/// First-launch intro: blue canvas, floating icons around a hero disc.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  Future<void> _go(BuildContext context) async {
    await Api.i.prefs.setBool('seen_welcome', true);
    if (context.mounted) Navigator.pushReplacement(context, fadeRoute(const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMaxWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: LayoutBuilder(builder: (context, box) {
                  final size = math.min(box.maxWidth, box.maxHeight);
                  return Center(child: SizedBox(width: size, height: size, child: _Hero(size: size)));
                })),
                const Text('Attendance\nmade simple\nfor teams.', style: TextStyle(fontSize: 38, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -1))
                    .animate().fadeIn(delay: 300.ms, duration: 500.ms).slideY(begin: 0.15, end: 0, curve: Curves.easeOutCubic),
                const SizedBox(height: 10),
                const Text('Punch in with your face, plan your lunch, and ask for leave, all in one place.', style: TextStyle(fontSize: 15, color: C.muted))
                    .animate().fadeIn(delay: 450.ms, duration: 500.ms),
                const SizedBox(height: 24),
                Row(children: [
                  TextButton(onPressed: () => _go(context), child: const Text('Skip')),
                  const Spacer(),
                  Pressable(
                    onTap: () => _go(context),
                    child: Container(
                      height: 64, padding: const EdgeInsets.only(left: 26, right: 8),
                      decoration: BoxDecoration(color: C.brand, borderRadius: BorderRadius.circular(40)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Text("Let's start", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                        const SizedBox(width: 14),
                        Container(width: 48, height: 48, decoration: const BoxDecoration(color: C.accent, shape: BoxShape.circle), child: const Icon(Icons.arrow_forward_rounded)),
                      ]),
                    ),
                  ).animate(onPlay: (c) => c.repeat(reverse: true)).moveX(begin: 0, end: 4, duration: 900.ms, curve: Curves.easeInOut),
                ]).animate().fadeIn(delay: 600.ms),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final double size;
  const _Hero({required this.size});
  @override
  Widget build(BuildContext context) {
    final orbit = [
      (Icons.location_on_rounded, 0.0, C.ink, Colors.white),
      (Icons.event_available_rounded, 1.6, Colors.white, C.ink),
      (Icons.restaurant_rounded, 3.1, C.ink, C.accent),
      (Icons.schedule_rounded, 4.7, Colors.white, C.ink),
    ];
    return Stack(alignment: Alignment.center, children: [
      Container(width: size * 0.74, height: size * 0.74, decoration: const BoxDecoration(color: C.accentSoft, shape: BoxShape.circle))
          .animate(onPlay: (c) => c.repeat(reverse: true)).scale(begin: const Offset(0.96, 0.96), end: const Offset(1.04, 1.04), duration: 2.2.seconds, curve: Curves.easeInOut),
      Container(
        width: size * 0.5, height: size * 0.5,
        decoration: BoxDecoration(color: C.ink, shape: BoxShape.circle, boxShadow: [BoxShadow(color: C.ink.withValues(alpha: 0.25), blurRadius: 30, offset: const Offset(0, 14))]),
        child: Icon(Icons.face_retouching_natural_rounded, color: C.accent, size: size * 0.24),
      ).animate().scale(duration: 700.ms, curve: Curves.easeOutBack).then().shimmer(duration: 1800.ms, color: Colors.white24),
      for (final (i, o) in orbit.indexed)
        _Orbiter(size: size, phase: o.$2, icon: o.$1, bg: o.$3, fg: o.$4, delay: 200 + i * 120),
    ]);
  }
}

/// Icon bubble circling the hero.
class _Orbiter extends StatefulWidget {
  final double size, phase;
  final IconData icon;
  final Color bg, fg;
  final int delay;
  const _Orbiter({required this.size, required this.phase, required this.icon, required this.bg, required this.fg, required this.delay});
  @override
  State<_Orbiter> createState() => _OrbiterState();
}

class _OrbiterState extends State<_Orbiter> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final a = widget.phase + _c.value * math.pi * 2;
          final r = widget.size * 0.4;
          return Transform.translate(
            offset: Offset(math.cos(a) * r, math.sin(a) * r * 0.8),
            child: Container(width: 54, height: 54, decoration: BoxDecoration(color: widget.bg, shape: BoxShape.circle, boxShadow: [BoxShadow(color: C.ink.withValues(alpha: 0.15), blurRadius: 14, offset: const Offset(0, 6))]), child: Icon(widget.icon, color: widget.fg)),
          );
        },
      ).animate().fadeIn(delay: Duration(milliseconds: widget.delay), duration: 500.ms).scale(delay: Duration(milliseconds: widget.delay), curve: Curves.easeOutBack);
}
