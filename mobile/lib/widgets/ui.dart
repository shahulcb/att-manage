import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme.dart';

// ───────────────────────── basics ─────────────────────────

/// Scale-down feedback on press + haptic tick. Wrap anything tappable.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool haptic;
  const Pressable({super.key, required this.child, this.onTap, this.haptic = true});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap == null ? null : () { if (widget.haptic) HapticFeedback.selectionClick(); widget.onTap!(); },
        child: AnimatedScale(scale: _down ? 0.96 : 1, duration: const Duration(milliseconds: 110), curve: Curves.easeOut, child: widget.child),
      );
}

/// Staggered entrance (fade + slide up). Use `index` inside lists.
extension Reveal on Widget {
  Widget reveal([int index = 0]) => animate(delay: Duration(milliseconds: 55 * math.min(index, 10)))
      .fadeIn(duration: 380.ms, curve: Curves.easeOut)
      .slideY(begin: 0.12, end: 0, duration: 420.ms, curve: Curves.easeOutCubic);
}

/// Number that counts up when it appears or changes.
class CountUp extends StatelessWidget {
  final num value;
  final int decimals;
  final String suffix;
  final TextStyle? style;
  const CountUp(this.value, {super.key, this.decimals = 0, this.suffix = '', this.style});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.toDouble()), duration: const Duration(milliseconds: 900), curve: Curves.easeOutCubic,
        builder: (_, v, _) => Text('${v.toStringAsFixed(decimals)}$suffix', style: style),
      );
}

/// Grey shimmering placeholder used while data loads.
class Skeleton extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;
  const Skeleton({super.key, this.height = 16, this.width, this.radius = 14});
  @override
  Widget build(BuildContext context) => Container(height: height, width: width, decoration: BoxDecoration(color: C.grey, borderRadius: BorderRadius.circular(radius)))
      .animate(onPlay: (c) => c.repeat()).shimmer(duration: 1200.ms, color: Colors.white70);
}

class SkeletonList extends StatelessWidget {
  final int count;
  const SkeletonList({super.key, this.count = 4});
  @override
  Widget build(BuildContext context) => Column(children: [for (var i = 0; i < count; i++) const Padding(padding: EdgeInsets.only(bottom: 12), child: Skeleton(height: 84, radius: 28))]);
}

/// Empty / error state with an icon and optional action. Always scrollable-safe (no fixed heights).
class StateView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const StateView({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 84, height: 84, decoration: const BoxDecoration(color: C.accentSoft, shape: BoxShape.circle), child: Icon(icon, size: 38))
              .animate().scale(duration: 420.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          if (message != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: C.muted))),
          if (actionLabel != null) Padding(padding: const EdgeInsets.only(top: 16), child: SizedBox(width: 180, child: FilledButton(onPressed: onAction, child: Text(actionLabel!)))),
        ]).animate().fadeIn(duration: 300.ms),
      );
}

// ───────────────────────── cards, chips, buttons ─────────────────────────

class Pill extends StatelessWidget {
  final String text;
  final Color bg, fg;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;
  const Pill(this.text, {super.key, this.bg = Colors.white, this.fg = C.ink, this.count, this.selected = false, this.onTap});
  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut,
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(color: selected ? C.ink : bg, borderRadius: BorderRadius.circular(26)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(color: selected ? Colors.white : fg, fontWeight: FontWeight.w700, fontSize: 13))),
            if (count != null) ...[
              const SizedBox(width: 8),
              Container(
                constraints: const BoxConstraints(minWidth: 22), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: selected ? C.accent : C.grey, borderRadius: BorderRadius.circular(12)),
                child: Text('$count', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: C.ink, fontWeight: FontWeight.w800)),
              ),
            ],
          ]),
        ),
      );
}

/// Big rounded card. Colour is one of the accent colours; text colour adapts.
class InfoCard extends StatelessWidget {
  final Color color;
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  const InfoCard({super.key, required this.color, required this.child, this.padding = const EdgeInsets.all(20), this.onTap});
  @override
  Widget build(BuildContext context) {
    final dark = color == C.ink;
    final box = Container(
      width: double.infinity, padding: padding, margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color, borderRadius: BorderRadius.circular(kRadius),
        boxShadow: color == Colors.white ? [BoxShadow(color: C.ink.withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 6))] : null,
      ),
      child: DefaultTextStyle.merge(style: TextStyle(color: dark ? Colors.white : C.ink), child: child),
    );
    return onTap == null ? box : Pressable(onTap: onTap, child: box);
  }
}

class RoundIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool dark;
  final String? label;
  final bool dot;
  const RoundIcon(this.icon, {super.key, this.onTap, this.dark = true, this.label, this.dot = false});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, label: label,
        child: Pressable(
          onTap: onTap,
          child: SizedBox(width: 48, height: 48, child: Stack(alignment: Alignment.center, children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(color: dark ? C.ink : Colors.white, shape: BoxShape.circle), child: Icon(icon, color: dark ? Colors.white : C.ink, size: 22)),
            if (dot) Positioned(right: 6, top: 6, child: Container(width: 10, height: 10, decoration: BoxDecoration(color: C.accent, shape: BoxShape.circle, border: Border.all(color: C.ink, width: 2)))),
          ])),
        ),
      );
}

class Avatar extends StatelessWidget {
  final String name;
  final double radius;
  const Avatar(this.name, {super.key, this.radius = 24});
  @override
  Widget build(BuildContext context) {
    final colors = [C.accent, C.lavender, C.sky, C.accentSoft];
    final c = colors[name.isEmpty ? 0 : name.codeUnitAt(0) % colors.length];
    return CircleAvatar(radius: radius, backgroundColor: c, child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: TextStyle(fontWeight: FontWeight.w800, fontSize: radius * 0.8, color: C.ink)));
  }
}

/// Main call-to-action: blue pill with icon, loading spinner, press feedback.
class ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading, dark;
  const ActionButton({super.key, required this.label, required this.icon, this.onPressed, this.loading = false, this.dark = false});
  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !loading;
    return Pressable(
      onTap: enabled ? onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200), height: 58, width: double.infinity,
        decoration: BoxDecoration(color: enabled ? (dark ? C.brand : C.accent) : (dark ? C.brand.withValues(alpha: 0.4) : C.accent.withValues(alpha: 0.35)), borderRadius: BorderRadius.circular(30)),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: loading
                ? SizedBox(key: const ValueKey('l'), width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.6, color: dark ? Colors.white : C.ink))
                : Row(key: const ValueKey('t'), mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: dark ? Colors.white : C.ink), const SizedBox(width: 10),
                    Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(color: dark ? Colors.white : C.ink, fontWeight: FontWeight.w800, fontSize: 16))),
                  ]),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── screen scaffolding ─────────────────────────

/// Heading used at the top of every tab.
class ScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;
  const ScreenHeader(this.title, {super.key, this.subtitle, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
            if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted)),
          ])),
          if (trailing != null) trailing!,
        ]),
      ).reveal();
}

class SectionTitle extends StatelessWidget {
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const SectionTitle(this.text, {super.key, this.action, this.onAction});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 12),
        child: Row(children: [
          Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
          if (action != null) GestureDetector(onTap: onAction, child: Text(action!, style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600))),
        ]),
      );
}

/// Content wrapper: pads for the floating nav, keeps width sane on tablets, always scrollable (so pull-to-refresh works on empty pages).
class TabPage extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  const TabPage({super.key, required this.children, this.onRefresh});
  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      // the bottom bar overlays the page (extendBody): leave its real height (already in padding.bottom) + breathing room
      padding: EdgeInsets.fromLTRB(20, 12, 20, math.max(110.0, MediaQuery.of(context).padding.bottom + 16)),
      children: children,
    );
    final body = Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kMaxWidth), child: list));
    return onRefresh == null ? body : RefreshIndicator(color: C.ink, backgroundColor: C.accent, onRefresh: onRefresh!, child: body);
  }
}

// ───────────────────────── navigation ─────────────────────────

class NavItem { final IconData icon; final String label; const NavItem(this.icon, this.label); }

/// Frosted-glass bottom bar, flush with the screen edge. The selected tab rises as a "drop" sitting in a curved notch
/// that glides (with a little liquid overshoot) to the tapped tab.
class PillNav extends StatelessWidget {
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  const PillNav({super.key, required this.items, required this.index, required this.onTap});

  static const barH = 64.0;   // visible bar height (above the system gesture area)
  static const lift = 24.0;   // how far the drop rises above the bar
  static const depth = 38.0;  // depth of the notch
  static const ball = 56.0;   // drop diameter
  static const pad = 24.0;    // side inset so the first/last tab have room for the drop and notch

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).padding.bottom;
    return SizedBox(
      height: barH + inset + lift,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final slot = (w - pad * 2) / items.length;
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: index.toDouble()), duration: const Duration(milliseconds: 520), curve: Curves.easeOutBack,
          builder: (context, pos, _) {
            final cx = pad + slot * (pos + 0.5);
            return Stack(clipBehavior: Clip.none, children: [
              // glass body, cut by the notch
              Positioned(
                left: 0, right: 0, bottom: 0, height: barH + inset,
                child: ClipPath(
                  clipper: _NotchClipper(cx, depth),
                  child: BackdropFilter(
                    filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [C.ink.withValues(alpha: 0.72), C.ink.withValues(alpha: 0.88)]))),
                  ),
                ),
              ),
              // thin light edge following the notch
              Positioned(left: 0, right: 0, bottom: 0, height: barH + inset, child: IgnorePointer(child: CustomPaint(painter: _NotchEdge(cx, depth)))),
              // labels + icons
              Positioned(
                left: 0, right: 0, bottom: inset, height: barH,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: pad),
                  child: Row(children: [
                    for (var i = 0; i < items.length; i++)
                      Expanded(child: _NavSlot(item: items[i], selected: i == index, onTap: () => onTap(i))),
                  ]),
                ),
              ),
              // the drop
              Positioned(
                left: cx - ball / 2, top: 0, width: ball, height: ball,
                child: IgnorePointer(child: Container(
                  decoration: BoxDecoration(color: C.accent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: C.accent.withValues(alpha: 0.55), blurRadius: 18, offset: const Offset(0, 6))]),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    transitionBuilder: (c, a) => ScaleTransition(scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack), child: FadeTransition(opacity: a, child: c)),
                    child: Icon(items[index].icon, key: ValueKey(index), color: C.ink, size: 27),
                  ),
                )),
              ),
            ]);
          },
        );
      }),
    ).animate().slideY(begin: 0.6, end: 0, duration: 500.ms, curve: Curves.easeOutCubic).fadeIn();
  }
}

class _NavSlot extends StatelessWidget {
  final NavItem item;
  final bool selected;
  final VoidCallback onTap;
  const _NavSlot({required this.item, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => Semantics(
        button: true, selected: selected, label: item.label,
        child: Pressable(
          onTap: onTap,
          child: SizedBox.expand(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              // unselected: icon here; selected: the icon lives in the drop above, so this space stays empty
              AnimatedOpacity(opacity: selected ? 0 : 1, duration: const Duration(milliseconds: 200), child: Icon(item.icon, color: Colors.white70, size: 24)),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(fontSize: 10.5, fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? Colors.white : Colors.white60),
                child: Text(item.label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
              ),
              const SizedBox(height: 9),
            ]),
          ),
        ),
      );
}

Path _notchPath(Size s, double cx, double depth) {
  const r = 20.0; // top corner radius
  final bar = Path()..addRRect(RRect.fromRectAndCorners(Offset.zero & s, topLeft: const Radius.circular(r), topRight: const Radius.circular(r)));
  // the cut-out starts just above the bar so it meets the top edge smoothly, and may overlap the sides without breaking
  final cut = Path()
    ..moveTo(cx - 46, -2)
    ..cubicTo(cx - 24, -2, cx - 33, depth, cx, depth)
    ..cubicTo(cx + 33, depth, cx + 24, -2, cx + 46, -2)
    ..close();
  return Path.combine(PathOperation.difference, bar, cut);
}

class _NotchClipper extends CustomClipper<Path> {
  final double cx, depth;
  _NotchClipper(this.cx, this.depth);
  @override
  Path getClip(Size size) => _notchPath(size, cx, depth);
  @override
  bool shouldReclip(_NotchClipper o) => o.cx != cx;
}

class _NotchEdge extends CustomPainter {
  final double cx, depth;
  _NotchEdge(this.cx, this.depth);
  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(_notchPath(size, cx, depth), Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white.withValues(alpha: 0.18));
  @override
  bool shouldRepaint(_NotchEdge o) => o.cx != cx;
}

// ───────────────────────── feedback ─────────────────────────

void toast(BuildContext c, String m, {bool error = false}) {
  const bottom = 14.0; // Scaffold already lifts floating snack bars above the bottom bar
  ScaffoldMessenger.of(c).hideCurrentSnackBar();
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(
    content: Row(children: [
      Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: error ? Colors.white : C.accent), const SizedBox(width: 12),
      Expanded(child: Text(m, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
    ]),
    backgroundColor: error ? C.danger : C.ink, behavior: SnackBarBehavior.floating, duration: Duration(seconds: error ? 5 : 3),
    margin: const EdgeInsets.fromLTRB(20, 0, 20, bottom), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ));
}

Future<bool> confirm(BuildContext c, String title, String body, {String yes = 'Confirm'}) async =>
    (await showDialog<bool>(context: c, builder: (_) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)), content: SingleChildScrollView(child: Text(body)),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(96, 44)), onPressed: () => Navigator.pop(c, true), child: Text(yes))],
    ))) == true;

String fmtTime(String? iso) {
  if (iso == null) return '--:--';
  final d = DateTime.parse(iso).toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String fmtMin(int m) => m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '${m}m';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
String fmtDate(DateTime d) => '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
