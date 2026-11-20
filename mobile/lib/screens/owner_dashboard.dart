import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/ui.dart';

class OwnerDashboard extends StatefulWidget {
  final ValueNotifier<int> refresh;
  final VoidCallback onLogout, goToRequests;
  const OwnerDashboard({super.key, required this.refresh, required this.onLogout, required this.goToRequests});
  @override
  State<OwnerDashboard> createState() => _OwnerDashboardState();
}

class _OwnerDashboardState extends State<OwnerDashboard> {
  Map? d;
  List activity = [];
  String? error;

  @override
  void initState() { super.initState(); widget.refresh.addListener(load); load(); }
  @override
  void dispose() { widget.refresh.removeListener(load); super.dispose(); }

  Future<void> load() async {
    try {
      final a = await Api.i.get('/owner/dashboard');
      List rows = [];
      try { rows = await Api.i.get('/owner/attendance?date=${a['date']}'); } catch (_) {}
      final withPunch = rows.where((r) => r['attendance'] != null && r['attendance']['punchIn'] != null).toList()
        ..sort((x, y) => '${y['attendance']['punchOut'] ?? y['attendance']['punchIn']}'.compareTo('${x['attendance']['punchOut'] ?? x['attendance']['punchIn']}'));
      if (mounted) setState(() { d = a; activity = withPunch.take(5).toList(); error = null; });
    } on ApiError catch (e) { if (mounted) setState(() => error = e.message); }
    catch (e) { if (mounted) setState(() => error = '$e'); }
  }

  @override
  Widget build(BuildContext context) {
    if (d == null) {
      return error != null
          ? TabPage(onRefresh: load, children: [StateView(icon: Icons.cloud_off_rounded, title: 'Could not load', message: error, actionLabel: 'Try again', onAction: load)])
          : const TabPage(children: [Skeleton(height: 56, radius: 28), SizedBox(height: 16), Skeleton(height: 200, radius: 32), SizedBox(height: 16), Skeleton(height: 120, radius: 28), SizedBox(height: 16), SkeletonList(count: 3)]);
    }
    final total = d!['totalEmployees'] as int;
    final punched = (d!['present'] as int) + (d!['late'] as int);
    final pending = (d!['pendingFaceRegistrations'] as int) + (d!['pendingFaceRequests'] as int) + (d!['pendingLeaves'] as int);

    return TabPage(onRefresh: load, children: [
      Row(children: [
        const Avatar('O', radius: 26), const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Welcome Back 👋', style: TextStyle(color: C.muted, fontSize: 12)),
          Text('Owner', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        ])),
        RoundIcon(Icons.inbox_rounded, dark: false, label: 'Requests', dot: pending > 0, onTap: widget.goToRequests),
        const SizedBox(width: 8),
        RoundIcon(Icons.logout_rounded, dark: false, label: 'Sign out', onTap: () async { if (await confirm(context, 'Sign out', 'Do you want to sign out?', yes: 'Sign out')) widget.onLogout(); }),
      ]).reveal(0),
      const SizedBox(height: 18),

      // summary card
      Container(
        width: double.infinity, padding: const EdgeInsets.all(22), margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(34), boxShadow: [BoxShadow(color: C.ink.withValues(alpha: 0.25), blurRadius: 28, offset: const Offset(0, 14))]),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Today · ${d!['date']}', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              CountUp(punched, style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w900, height: 1)),
              Padding(padding: const EdgeInsets.only(bottom: 6, left: 6), child: Text('/ $total', style: const TextStyle(color: Colors.white54, fontSize: 20, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 6),
            const Text('employees punched in', style: TextStyle(color: Colors.white70)),
            if ((d!['notYet'] as int) > 0) Padding(padding: const EdgeInsets.only(top: 10), child: Text('${d!['notYet']} not yet in', style: const TextStyle(color: C.accent, fontWeight: FontWeight.w700))),
          ])),
          ProgressRing(value: total == 0 ? 0 : punched / total, size: 104, stroke: 12, center: Text(total == 0 ? '–' : '${(punched / total * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 18))),
        ]),
      ).reveal(1),

      GridView.count(
        crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.75,
        children: [
          _Tile('On time', d!['present'], C.accent, Icons.check_circle_outline_rounded),
          _Tile('Late', d!['late'], C.lavender, Icons.watch_later_outlined),
          _Tile('Absent', d!['absent'], Colors.white, Icons.person_off_outlined),
          _Tile('On leave', d!['onLeave'], C.sky, Icons.beach_access_outlined),
        ].indexed.map((e) => e.$2.reveal(2 + e.$1)).toList(),
      ),

      const SizedBox(height: 14),
      InfoCard(
        color: pending > 0 ? C.accent : Colors.white, onTap: widget.goToRequests,
        child: Row(children: [
          Container(width: 46, height: 46, decoration: const BoxDecoration(color: C.ink, shape: BoxShape.circle), child: const Icon(Icons.inbox_rounded, color: C.accent)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pending > 0 ? '$pending waiting for you' : 'All caught up', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text(pending > 0 ? '${d!['pendingFaceRegistrations']} face approvals · ${d!['pendingFaceRequests']} resets · ${d!['pendingLeaves']} leaves' : 'No pending requests', style: const TextStyle(fontSize: 12)),
          ])),
          const Icon(Icons.chevron_right_rounded),
        ]),
      ).reveal(6),

      const SectionTitle('Latest activity'),
      if (activity.isEmpty) const InfoCard(color: Colors.white, child: Text('Nobody has punched in yet today.', style: TextStyle(color: C.muted)))
      else for (final (i, r) in activity.indexed)
        InfoCard(color: Colors.white, padding: const EdgeInsets.all(14), child: Row(children: [
          Avatar(r['employee']['name'], radius: 22), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['employee']['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(r['attendance']['punchOut'] != null ? 'Punched out' : r['attendance']['lunchOut'] != null && r['attendance']['lunchIn'] == null ? 'On lunch' : 'Punched in', style: const TextStyle(color: C.muted, fontSize: 12)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: statusColor(r['attendance']['status']), borderRadius: BorderRadius.circular(12)),
              child: Text(fmtTime(r['attendance']['punchOut'] ?? r['attendance']['punchIn']), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: r['attendance']['status'] == 'ABSENT' ? Colors.white : C.ink))),
        ])).reveal(7 + i),
    ]);
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final dynamic value;
  final Color color;
  final IconData icon;
  const _Tile(this.label, this.value, this.color, this.icon);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(26), boxShadow: color == Colors.white ? [BoxShadow(color: C.ink.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 5))] : null),
        child: Row(children: [
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            CountUp(value as num, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, height: 1)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ])),
          Icon(icon, size: 26),
        ]),
      );
}
