import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'employee_leave.dart' show BalanceStrip;

class OwnerEmployees extends StatefulWidget {
  final ValueNotifier<int> refresh;
  const OwnerEmployees({super.key, required this.refresh});
  @override
  State<OwnerEmployees> createState() => _OwnerEmployeesState();
}

class _OwnerEmployeesState extends State<OwnerEmployees> {
  List list = [];
  bool loading = true;
  String? error;
  String q = '';

  @override
  void initState() { super.initState(); widget.refresh.addListener(_quiet); load(); }
  @override
  void dispose() { widget.refresh.removeListener(_quiet); super.dispose(); }
  void _quiet() => load();

  Future<void> load() async {
    try { list = await Api.i.get('/owner/employees'); error = null; } on ApiError catch (e) { error = e.message; } catch (e) { error = '$e'; }
    if (mounted) setState(() => loading = false);
  }

  Future<void> options(Map e) async {
    final a = await showModalBottomSheet<String>(context: context, builder: (ctx) => SafeArea(child: Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Avatar(e['name'], radius: 32), const SizedBox(height: 10),
        Text(e['name'], textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
        Text('${e['externalId']}${'${e['department']}'.isEmpty ? '' : ' · ${e['department']}'}', style: const TextStyle(color: C.muted)),
        const SizedBox(height: 8),
        ListTile(leading: const Icon(Icons.beach_access_outlined), title: const Text('Leave balance'), onTap: () => Navigator.pop(ctx, 'bal')),
        ListTile(leading: const Icon(Icons.fact_check_outlined), title: const Text('Face checks (recent)'), onTap: () => Navigator.pop(ctx, 'att')),
        ListTile(leading: const Icon(Icons.face_retouching_off), title: const Text('Reset face data'), onTap: () => Navigator.pop(ctx, 'face')),
      ]),
    )));
    if (!mounted || a == null) return;
    try {
      if (a == 'att') {
        final rows = await Api.i.get('/owner/face-attempts?employeeId=${e['id']}&limit=30') as List;
        if (!mounted) return;
        await showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${e['name']} · face checks', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
          const SizedBox(height: 4),
          const Text('Score = how closely the face matched (higher is better).', style: TextStyle(fontSize: 12, color: C.muted)),
          const SizedBox(height: 10),
          if (rows.isEmpty) const StateView(icon: Icons.face_retouching_natural, title: 'No checks yet'),
          Flexible(child: ListView(shrinkWrap: true, children: [
            for (final r in rows) ListTile(
              dense: true, contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 16, backgroundColor: r['ok'] == true ? C.accent : const Color(0xFFF6D5D2), child: Icon(r['ok'] == true ? Icons.check_rounded : Icons.close_rounded, size: 18, color: C.ink)),
              title: Text('${r['type']} · ${r['ok'] == true ? 'accepted' : '${r['reason']}'.split(':').first.toLowerCase().replaceAll('_', ' ')}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${DateTime.parse(r['createdAt']).toLocal().toString().substring(0, 16)} · score ${(r['score'] as num).toStringAsFixed(2)} · best other ${(r['otherScore'] as num).toStringAsFixed(2)}'),
            ),
          ])),
        ]))));
      } else if (a == 'bal') {
        final b = await Api.i.get('/owner/employees/${e['id']}/leave-balance');
        if (mounted) await showModalBottomSheet(context: context, builder: (_) => SafeArea(child: Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [Text(e['name'], style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)), const SizedBox(height: 12), BalanceStrip(b)]))));
      } else if (a == 'face' && await confirm(context, 'Reset face', '${e['name']} will have to register their face again.', yes: 'Reset')) {
        await Api.i.post('/owner/employees/${e['id']}/reset-face');
        if (mounted) toast(context, 'Face data reset'); load();
      }
    } catch (x) { if (mounted) toast(context, '$x', error: true); }
  }

  @override
  Widget build(BuildContext context) {
    final shown = list.where((e) => '${e['name']} ${e['externalId']} ${e['department']}'.toLowerCase().contains(q.toLowerCase())).toList();
    return TabPage(onRefresh: load, children: [
      ScreenHeader('Employees', subtitle: loading ? null : '${list.length} in total'),
      TextField(onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(hintText: 'Search name, ID or department', prefixIcon: Icon(Icons.search_rounded))).reveal(1),
      const SizedBox(height: 14),
      if (loading) const SkeletonList()
      else if (error != null) StateView(icon: Icons.cloud_off_rounded, title: 'Could not load', message: error, actionLabel: 'Try again', onAction: load)
      else if (shown.isEmpty) StateView(icon: q.isEmpty ? Icons.groups_rounded : Icons.search_off_rounded, title: q.isEmpty ? 'No employees yet' : 'No match for "$q"', message: q.isEmpty ? 'They appear here after their first login.' : null)
      else for (final (i, e) in shown.indexed)
        Pressable(
          onTap: () => options(e),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: e['active'] ? Colors.white : const Color(0xFFF6E3E1), borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: C.ink.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 5))]),
            child: Row(children: [
              Avatar(e['name'], radius: 24), const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(e['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text('${e['externalId']}${'${e['department']}'.isEmpty ? '' : ' · ${e['department']}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
              ])),
              if (!e['active']) const Text('Inactive', style: TextStyle(color: C.danger, fontWeight: FontWeight.w800))
              else _FaceBadge(e['faceStatus']),
            ]),
          ),
        ).reveal(i),
    ]);
  }
}

class _FaceBadge extends StatelessWidget {
  final String status;
  const _FaceBadge(this.status);
  @override
  Widget build(BuildContext context) {
    final (icon, color, text) = switch (status) { 'REGISTERED' => (Icons.verified_user_rounded, C.accent, 'Verified'), 'PENDING' => (Icons.hourglass_top_rounded, C.lavender, 'Pending'), _ => (Icons.face_retouching_off, C.grey, 'No face') };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 14), const SizedBox(width: 4), Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11))]));
  }
}
