import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import '../api.dart';
import '../face/scan_screen.dart';
import '../punch_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class EmployeeHome extends StatefulWidget {
  final VoidCallback onLogout;
  final void Function(int) goTo;
  const EmployeeHome({super.key, required this.onLogout, required this.goTo});
  @override
  State<EmployeeHome> createState() => _EmployeeHomeState();
}

class _EmployeeHomeState extends State<EmployeeHome> with WidgetsBindingObserver {
  Map? me, today;
  List recent = [];
  bool onLeave = false, holiday = false, loading = true, working = false;
  String? halfLeave, error;

  @override
  void initState() { super.initState(); WidgetsBinding.instance.addObserver(this); load(); }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) { if (s == AppLifecycleState.resumed && !working) load(silent: true); }

  Future<void> load({bool silent = false}) async {
    if (!silent && me == null) setState(() { loading = true; error = null; });
    try {
      final m = await Api.i.get('/me');
      final t = await Api.i.get('/me/today');
      final n = DateTime.now();
      final month = '${n.year}-${n.month.toString().padLeft(2, '0')}';
      List rec = [];
      try { rec = (await Api.i.get('/me/attendance?month=$month') as List).where((r) => r['date'] != t['date']).toList().reversed.take(4).toList(); } catch (_) {}
      if (mounted) setState(() { me = m; today = t['attendance']; onLeave = t['onLeave'] == true; halfLeave = t['halfLeave']; holiday = t['holiday'] == true; recent = rec; error = null; });
    } on ApiError catch (e) {
      if (e.code == 'INACTIVE') { if (mounted) { toast(context, e.message, error: true); widget.onLogout(); } return; }
      if (mounted) setState(() => error = e.message);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally { if (mounted) setState(() => loading = false); }
  }

  // ───────── actions ─────────

  Future<void> registerFace() async {
    final ok = await confirm(context, 'Register your face', 'You will take 4 quick photos looking at the camera (one with a small smile). Do it in good light, alone, without sunglasses or a cap. The owner will then approve it.', yes: 'Start');
    if (!ok || !mounted) return;
    final r = await Navigator.push<ScanResult>(context, MaterialPageRoute(builder: (_) => ScanScreen(title: 'Register your face', steps: registerSteps())));
    if (r == null || !mounted) return;
    setState(() => working = true);
    try {
      await Api.i.post('/me/face/register', {'embeddings': r.embeddings, 'photo': r.photo});
      if (mounted) toast(context, 'Sent to the owner for approval');
      await load(silent: true);
    } catch (e) { if (mounted) toast(context, '$e', error: true); }
    finally { if (mounted) setState(() => working = false); }
  }

  Future<void> punch(String type) async {
    if (working) return;
    setState(() => working = true);
    try {
      final fix = await PunchService.locate(me!['config']); // location first: no point scanning a face if it will be refused
      final ch = await PunchService.challenge(type);
      if (!mounted) return;
      setState(() => working = false);
      final r = await Navigator.push<ScanResult>(context, MaterialPageRoute(builder: (_) => ScanScreen(title: punchTitles[type]!, steps: punchSteps(ch['actions']), preCapture: true)));
      if (r == null || !mounted) return;
      setState(() => working = true);
      final o = await PunchService.send(type: type, fix: fix, challenge: ch, frames: r.embeddings, actions: r.actions);
      if (mounted) toast(context, o.message);
      await load(silent: true);
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.code == 'GPS_DENIED' || e.code == 'GPS_OFF') {
        final open = await confirm(context, e.code == 'GPS_OFF' ? 'Turn on location' : 'Location needed', e.message, yes: 'Open settings');
        if (open) { e.code == 'GPS_OFF' ? await Geolocator.openLocationSettings() : await Geolocator.openAppSettings(); }
      } else {
        toast(context, e.message, error: true);
      }
      if (!mounted) return;
      if (e.code == 'FACE_MISMATCH') _offerFaceReset();
      if (['FACE_PENDING', 'FACE_NOT_REGISTERED', 'ON_LEAVE', 'ALREADY_IN', 'ALREADY_OUT'].contains(e.code)) load(silent: true);
    } catch (e) { if (mounted) toast(context, '$e', error: true); }
    finally { if (mounted) setState(() => working = false); }
  }

  Future<void> _offerFaceReset() async {
    final ok = await confirm(context, 'Face not matching?', 'If your appearance has changed, you can ask the owner to reset your face data so you can register again.', yes: 'Send request');
    if (!ok) return;
    try { await Api.i.post('/me/face/reset-request', {'reason': 'Face did not match'}); if (mounted) { toast(context, 'Request sent to the owner'); load(silent: true); } }
    catch (e) { if (mounted) toast(context, '$e', error: true); }
  }

  bool _inLunchWindow(Map cfg) {
    int m(String v) => int.parse(v.split(':')[0]) * 60 + int.parse(v.split(':')[1]);
    final n = DateTime.now(); final now = n.hour * 60 + n.minute;
    return now >= m(cfg['lunchStart']) && now <= m(cfg['lunchEnd']);
  }

  List<(IconData, String)> _alerts() {
    final a = <(IconData, String)>[];
    final face = me!['faceStatus'];
    if (face == 'NONE' && '${me!['faceNote'] ?? ''}'.isNotEmpty) a.add((Icons.face_retouching_off, 'Owner rejected your face photo: ${me!['faceNote']}'));
    if (face == 'NONE' && '${me!['faceNote'] ?? ''}'.isEmpty) a.add((Icons.face_retouching_natural, 'Register your face to start punching.'));
    if (face == 'PENDING') a.add((Icons.hourglass_top_rounded, 'Your face registration is waiting for owner approval.'));
    if (me!['faceResetPending'] == true) a.add((Icons.sync_problem_rounded, 'Your face reset request is waiting for the owner.'));
    if (onLeave) a.add((Icons.beach_access_rounded, 'You are on approved leave today.'));
    if (halfLeave != null) a.add((Icons.timelapse_rounded, halfLeave == 'FIRST' ? 'Half-day leave: morning off.' : 'Half-day leave: afternoon off.'));
    if (holiday) a.add((Icons.celebration_rounded, 'Today is a holiday.'));
    return a;
  }

  void _showAlerts() {
    final a = _alerts();
    showModalBottomSheet(context: context, builder: (_) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)), const SizedBox(height: 12),
        if (a.isEmpty) const StateView(icon: Icons.notifications_none_rounded, title: 'All caught up', message: 'Nothing needs your attention.'),
        for (final x in a) ListTile(contentPadding: EdgeInsets.zero, leading: CircleAvatar(backgroundColor: C.accentSoft, child: Icon(x.$1, color: C.ink)), title: Text(x.$2)),
      ]),
    )));
  }

  void _showProfile() {
    showModalBottomSheet(context: context, builder: (_) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Avatar(me!['name'], radius: 36), const SizedBox(height: 12),
        Text(me!['name'], textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        Text('${me!['externalId']}${'${me!['department']}'.isEmpty ? '' : ' · ${me!['department']}'}', style: const TextStyle(color: C.muted)),
        const SizedBox(height: 6),
        Chip(label: Text(me!['faceStatus'] == 'REGISTERED' ? 'Face verified' : me!['faceStatus'] == 'PENDING' ? 'Face pending approval' : 'Face not registered'), backgroundColor: C.accentSoft, side: BorderSide.none),
        const SizedBox(height: 14),
        if (me!['faceStatus'] == 'REGISTERED' && me!['faceResetPending'] != true) OutlinedButton.icon(onPressed: () { Navigator.pop(context); _offerFaceReset(); }, icon: const Icon(Icons.face), label: const Text('My face changed: request reset')),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: () async { Navigator.pop(context); if (await confirm(context, 'Sign out', 'Do you want to sign out?', yes: 'Sign out')) widget.onLogout(); }, icon: const Icon(Icons.logout), label: const Text('Sign out')),
      ]),
    )));
  }

  // ───────── build ─────────

  @override
  Widget build(BuildContext context) {
    if (loading && me == null) return const TabPage(children: [Skeleton(height: 56, radius: 28), SizedBox(height: 16), Skeleton(height: 260, radius: 32), SizedBox(height: 16), Skeleton(height: 90, radius: 28), SizedBox(height: 16), SkeletonList()]);
    if (me == null) return TabPage(onRefresh: load, children: [StateView(icon: Icons.cloud_off_rounded, title: 'Could not load', message: error, actionLabel: 'Try again', onAction: load)]);

    final cfg = me!['config'] as Map;
    final face = me!['faceStatus'] as String;
    final faceOk = face == 'REGISTERED';
    final pin = today?['punchIn'] != null, pout = today?['punchOut'] != null;
    final lout = today?['lunchOut'] != null, lin = today?['lunchIn'] != null;
    final onLunch = pin && !pout && lout && !lin;
    final alerts = _alerts();
    final first = '${me!['name']}'.split(' ').first;

    String headline() {
      if (face == 'NONE') return 'Register your face to start';
      if (face == 'PENDING') return 'Waiting for owner approval';
      if (onLeave) return 'You are on leave today';
      if (pout) return 'Day complete';
      if (onLunch) return 'Enjoy your lunch';
      if (pin) return 'You are working';
      return holiday ? 'Today is a holiday' : 'Ready to punch in';
    }

    Widget action() {
      if (face == 'NONE') return ActionButton(label: 'Register face', icon: Icons.face_retouching_natural, onPressed: registerFace, loading: working);
      if (face == 'PENDING') return const Text('The owner will review your photo. You can punch once it is approved.', style: TextStyle(color: Colors.white70));
      if (onLeave) return const Text('Enjoy your leave 🌴', style: TextStyle(color: Colors.white70));
      if (pout) return const Text('See you tomorrow 👋', style: TextStyle(color: Colors.white70));
      if (!pin) return _Pulse(child: ActionButton(label: 'Punch in', icon: Icons.login_rounded, onPressed: () => punch('IN'), loading: working));
      return Column(children: [
        if (onLunch) ActionButton(label: 'Back from lunch', icon: Icons.restaurant_rounded, onPressed: () => punch('LUNCH_IN'), loading: working)
        else ActionButton(label: 'Punch out', icon: Icons.logout_rounded, onPressed: () => punch('OUT'), loading: working),
        if (onLunch) TextButton(onPressed: working ? null : () async { if (await confirm(context, 'Still on lunch', 'You have not returned from lunch yet. Punch out anyway?', yes: 'Punch out')) punch('OUT'); }, child: const Text('Punch out instead', style: TextStyle(color: Colors.white70))),
      ]);
    }

    return TabPage(onRefresh: () => load(silent: true), children: [
      // header
      Row(children: [
        Pressable(onTap: _showProfile, child: Avatar(me!['name'], radius: 26)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Welcome Back 👋', style: TextStyle(color: C.muted, fontSize: 12)),
          Text(first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        ])),
        RoundIcon(Icons.notifications_none_rounded, dark: false, label: 'Notifications', dot: alerts.isNotEmpty, onTap: _showAlerts),
      ]).reveal(0),
      const SizedBox(height: 18),

      // hero card
      _HeroCard(
        dateText: fmtDate(DateTime.now()), headline: headline(), status: today?['status'], inTime: fmtTime(today?['punchIn']),
        lunch: lout ? '${fmtTime(today?['lunchOut'])}${lin ? ' – ${fmtTime(today?['lunchIn'])}' : ' …'}' : '--:--', outTime: fmtTime(today?['punchOut']),
        shift: '${cfg['workStart']} – ${cfg['workEnd']}',
        notes: [
          if ((today?['lateMinutes'] ?? 0) > 0) 'Late by ${fmtMin(today!['lateMinutes'])}',
          if ((today?['earlyMinutes'] ?? 0) > 0) 'Early exit by ${fmtMin(today!['earlyMinutes'])}',
          if ((today?['lunchOverMinutes'] ?? 0) > 0) 'Lunch ${fmtMin(today!['lunchOverMinutes'])} over',
        ],
        action: action(),
      ).reveal(1),

      // quick actions
      Row(children: [
        _Quick(Icons.restaurant_rounded, onLunch ? 'Back' : 'Lunch', enabled: faceOk && pin && !pout && !lout && _inLunchWindow(cfg) && !working, onTap: () => punch('LUNCH_OUT'), hint: lout ? 'Taken' : null),
        _Quick(Icons.beach_access_rounded, 'Leave', onTap: () => widget.goTo(3)),
        _Quick(Icons.calendar_month_rounded, 'History', onTap: () => widget.goTo(1)),
        _Quick(Icons.bar_chart_rounded, 'Stats', onTap: () => widget.goTo(2)),
      ]).reveal(2),
      if (faceOk && pin && !pout && !lout && !_inLunchWindow(cfg))
        Padding(padding: const EdgeInsets.only(top: 10), child: Text('Lunch break: ${cfg['lunchStart']} – ${cfg['lunchEnd']} (${cfg['lunchMinutes']} min)', style: const TextStyle(color: C.muted, fontSize: 12))).reveal(2),

      // today's timeline
      const SectionTitle("Today's activity"),
      InfoCard(color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16), child: Column(children: [
        _Row(Icons.login_rounded, 'Punch in', fmtTime(today?['punchIn']), done: pin, sub: today?['status'] == 'LATE' ? 'Late by ${fmtMin(today!['lateMinutes'])}' : null),
        _Row(Icons.restaurant_rounded, 'Lunch out', fmtTime(today?['lunchOut']), done: lout),
        _Row(Icons.restaurant_menu_rounded, 'Lunch in', fmtTime(today?['lunchIn']), done: lin, sub: (today?['lunchOverMinutes'] ?? 0) > 0 ? 'Over by ${fmtMin(today!['lunchOverMinutes'])}' : null),
        _Row(Icons.logout_rounded, 'Punch out', fmtTime(today?['punchOut']), done: pout, last: true, sub: (today?['earlyMinutes'] ?? 0) > 0 ? 'Early by ${fmtMin(today!['earlyMinutes'])}' : null),
      ])).reveal(3),

      // recent
      SectionTitle('Recent activity', action: 'See all', onAction: () => widget.goTo(1)),
      if (recent.isEmpty) const InfoCard(color: Colors.white, child: Text('Your previous days will show here.', style: TextStyle(color: C.muted)))
      else for (final (i, r) in recent.indexed)
        InfoCard(color: Colors.white, padding: const EdgeInsets.all(14), child: Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: statusColor(r['status']), shape: BoxShape.circle),
              child: Icon(r['status'] == 'ABSENT' ? Icons.close_rounded : r['status'] == 'LEAVE' ? Icons.beach_access_rounded : Icons.check_rounded, color: r['status'] == 'ABSENT' ? Colors.white : C.ink)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fmtDate(DateTime.parse(r['date'])), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(r['status'] == 'ABSENT' ? 'Absent' : r['status'] == 'LEAVE' ? 'On leave' : '${fmtTime(r['punchIn'])} – ${fmtTime(r['punchOut'])}', style: const TextStyle(color: C.muted, fontSize: 12)),
          ])),
          if (r['workedMinutes'] > 0) Text(fmtMin(r['workedMinutes']), style: const TextStyle(fontWeight: FontWeight.w800)),
        ])).reveal(4 + i),

      // info
      const SectionTitle('Workplace'),
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: InfoCard(color: C.accent, padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.schedule_rounded), const SizedBox(height: 10),
          const Text('Work hours', style: TextStyle(fontWeight: FontWeight.w800)),
          Text('${cfg['workStart']} – ${cfg['workEnd']}'), Text('${cfg['graceMinutes']} min grace', style: const TextStyle(fontSize: 12)),
        ]))),
        const SizedBox(width: 12),
        Expanded(child: InfoCard(color: C.lavender, padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.location_on_outlined), const SizedBox(height: 10),
          Text('${cfg['orgName'] ?? 'Office'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(cfg['officeLat'] == null ? 'Location not set' : 'Within ${cfg['radiusM']} m', style: const TextStyle(fontSize: 13)),
        ]))),
      ])).reveal(5),
    ]);
  }
}

/// Soft pulsing glow behind the main button when a punch is possible.
class _Pulse extends StatelessWidget {
  final Widget child;
  const _Pulse({required this.child});
  @override
  Widget build(BuildContext context) => Stack(alignment: Alignment.center, children: [
        Positioned.fill(child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(32), border: Border.all(color: C.accent, width: 2)))
            .animate(onPlay: (c) => c.repeat()).scale(begin: const Offset(1, 1), end: const Offset(1.06, 1.35), duration: 1500.ms, curve: Curves.easeOut).fadeOut(duration: 1500.ms)),
        child,
      ]);
}

class _HeroCard extends StatelessWidget {
  final String dateText, headline, inTime, lunch, outTime, shift;
  final String? status;
  final List<String> notes;
  final Widget action;
  const _HeroCard({required this.dateText, required this.headline, required this.inTime, required this.lunch, required this.outTime, required this.shift, required this.status, required this.notes, required this.action});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(22), margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(34), boxShadow: [BoxShadow(color: C.ink.withValues(alpha: 0.25), blurRadius: 28, offset: const Offset(0, 14))]),
      child: Stack(children: [
        // twinkling sparkles
        Positioned(right: 6, top: 28, child: _Spark(size: 26, delay: 0)),
        Positioned(right: 64, top: 70, child: _Spark(size: 14, delay: 600)),
        Positioned(left: 150, top: 6, child: _Spark(size: 10, delay: 1100)),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(dateText, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (status == 'PRESENT' || status == 'LATE')
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: statusColor(status), borderRadius: BorderRadius.circular(14)),
                  child: Text(status == 'LATE' ? 'Late' : 'On time', style: const TextStyle(color: C.ink, fontWeight: FontWeight.w800, fontSize: 12))).animate().scale(curve: Curves.easeOutBack),
          ]),
          const SizedBox(height: 18),
          Text(headline, style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800, height: 1.15)),
          const SizedBox(height: 18),
          Row(children: [
            Expanded(child: _T('IN', inTime)), Expanded(child: _T('LUNCH', lunch, small: true)), Expanded(child: _T('OUT', outTime)),
          ]),
          for (final n in notes) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [const Icon(Icons.info_outline, size: 14, color: C.lavender), const SizedBox(width: 6), Flexible(child: Text(n, style: const TextStyle(color: C.lavender, fontSize: 13)))])),
          const SizedBox(height: 20),
          AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: KeyedSubtree(key: ValueKey(headline), child: action)),
          const SizedBox(height: 4),
        ]),
      ]),
    );
  }
}

class _T extends StatelessWidget {
  final String label, value;
  final bool small;
  const _T(this.label, this.value, {this.small = false});
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 2),
        AnimatedSwitcher(duration: const Duration(milliseconds: 350), child: Text(value, key: ValueKey(value), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: small ? 15 : 26, fontWeight: FontWeight.w800, height: small ? 1.9 : 1.1))),
      ]);
}

class _Spark extends StatelessWidget {
  final double size;
  final int delay;
  const _Spark({required this.size, required this.delay});
  @override
  Widget build(BuildContext context) => Icon(Icons.auto_awesome, color: C.accent, size: size)
      .animate(delay: Duration(milliseconds: delay), onPlay: (c) => c.repeat(reverse: true)).fade(begin: 0.25, end: 1, duration: 1400.ms).rotate(begin: -0.05, end: 0.05, duration: 2.seconds);
}

class _Quick extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final String? hint;
  const _Quick(this.icon, this.label, {required this.onTap, this.enabled = true, this.hint});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Semantics(
            button: true, label: label, enabled: enabled,
            child: Pressable(
              onTap: enabled ? onTap : null,
              child: AnimatedOpacity(
                opacity: enabled ? 1 : 0.45, duration: const Duration(milliseconds: 200),
                child: Container(
                  height: 84, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: C.ink.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 5))]),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(width: 38, height: 38, decoration: const BoxDecoration(color: C.accentSoft, shape: BoxShape.circle), child: Icon(icon, size: 20)),
                    const SizedBox(height: 6),
                    Text(hint ?? label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String title, time;
  final bool done, last;
  final String? sub;
  const _Row(this.icon, this.title, this.time, {required this.done, this.last = false, this.sub});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          AnimatedContainer(duration: const Duration(milliseconds: 400), width: 40, height: 40, decoration: BoxDecoration(color: done ? C.accent : C.grey, shape: BoxShape.circle), child: Icon(icon, size: 19, color: done ? C.ink : C.muted)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: done ? C.ink : C.muted)),
            if (sub != null) Text(sub!, style: const TextStyle(fontSize: 12, color: C.muted)),
          ])),
          Text(time, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: done ? C.ink : C.muted)),
        ]),
      );
}
