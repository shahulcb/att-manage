import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../api.dart';
import '../theme.dart';
import 'ui.dart';

/// Common frame for the employee and owner apps: floating nav, tab fade, "no internet" banner, back-button behaviour.
class ShellFrame extends StatefulWidget {
  final List<NavItem> items;
  final List<Widget> Function(void Function(int) goTo) pagesBuilder;
  final ValueChanged<int>? onTab;
  const ShellFrame({super.key, required this.items, required this.pagesBuilder, this.onTab});
  @override
  State<ShellFrame> createState() => _ShellFrameState();
}

class _ShellFrameState extends State<ShellFrame> {
  int tab = 0;
  DateTime? _lastBack;
  void _go(int i) { setState(() => tab = i); widget.onTab?.call(i); }
  late final List<Widget> pages = widget.pagesBuilder(_go);

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (tab != 0) { _go(0); return; }
          final now = DateTime.now();
          if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) { SystemNavigator.pop(); return; }
          _lastBack = now;
          toast(context, 'Press back again to exit');
        },
        child: Scaffold(
          extendBody: true,
          body: SafeArea(
            bottom: false,
            child: Column(children: [
              ValueListenableBuilder<bool>(
                valueListenable: Api.i.online,
                builder: (_, online, _) => AnimatedSize(
                  duration: const Duration(milliseconds: 250), curve: Curves.easeOut,
                  child: online ? const SizedBox(width: double.infinity) : Container(
                    width: double.infinity, color: C.ink, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 20),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.wifi_off_rounded, color: C.accent, size: 16), SizedBox(width: 8),
                      Flexible(child: Text('No internet. Pull down to retry.', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ),
              ),
              Expanded(
                child: IndexedStack(index: tab, children: pages)
                    .animate(key: ValueKey(tab)).fadeIn(duration: 260.ms).slideY(begin: 0.025, end: 0, duration: 320.ms, curve: Curves.easeOut),
              ),
            ]),
          ),
          bottomNavigationBar: PillNav(items: widget.items, index: tab, onTap: _go),
        ),
      );
}
