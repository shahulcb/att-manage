import 'dart:convert';
import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'employee_leave.dart' show leaveColor, leaveLabel, halfText, BalanceStrip;

/// Everything waiting for the owner: new face registrations, face reset requests, leave requests.
class OwnerRequests extends StatefulWidget {
  final ValueNotifier<int> refresh;
  const OwnerRequests({super.key, required this.refresh});
  @override
  State<OwnerRequests> createState() => _OwnerRequestsState();
}

class _OwnerRequestsState extends State<OwnerRequests> {
  List faces = [], resets = [], leaves = [];
  String leaveFilter = 'PENDING';
  bool loading = true;
  final _busy = <String>{}; // ids being processed (no double taps)
  String? error;

  @override
  void initState() { super.initState(); widget.refresh.addListener(_quiet); load(); }
  @override
  void dispose() { widget.refresh.removeListener(_quiet); super.dispose(); }
  void _quiet() => load(silent: true);

  Future<void> load({bool silent = false}) async {
    try {
      final r = await Future.wait([Api.i.get('/owner/face-registrations'), Api.i.get('/owner/face-requests'), Api.i.get('/owner/leaves?status=$leaveFilter')]);
      faces = r[0]; resets = r[1]; leaves = r[2]; error = null;
    } on ApiError catch (e) { error = e.message; } catch (e) { error = '$e'; }
    if (mounted) setState(() => loading = false);
  }

  Future<String?> askNote(String title, {required bool required}) async {
    final c = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => AlertDialog(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      content: TextField(controller: c, maxLines: 2, autofocus: true, decoration: InputDecoration(hintText: required ? 'Reason (required)' : 'Note (optional)', errorText: err)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(96, 44)), onPressed: () {
          if (required && c.text.trim().isEmpty) return set(() => err = 'A reason is required');
          Navigator.pop(ctx, true);
        }, child: const Text('Confirm')),
      ],
    )));
    return ok == true ? c.text.trim() : null;
  }

  Future<void> run(String id, String path, String okMsg, [Map body = const {}]) async {
    if (_busy.contains(id)) return;
    setState(() => _busy.add(id));
    try { await Api.i.post(path, body); if (mounted) toast(context, okMsg); await load(silent: true); }
    catch (e) { if (mounted) toast(context, '$e', error: true); }
    finally { if (mounted) setState(() => _busy.remove(id)); }
  }

  Widget _btns(String id, VoidCallback no, VoidCallback yes, {String yesLabel = 'Approve', String noLabel = 'Reject'}) => Padding(
      padding: const EdgeInsets.only(top: 14),
      child: _busy.contains(id)
          ? const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6, color: C.ink)))
          : Row(children: [
              Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)), onPressed: no, child: Text(noLabel))),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)), onPressed: yes, child: Text(yesLabel))),
            ]));

  @override
  Widget build(BuildContext context) {
    final total = faces.length + resets.length + (leaveFilter == 'PENDING' ? leaves.length : 0);
    return TabPage(onRefresh: () => load(silent: true), children: [
      ScreenHeader('Requests', subtitle: loading ? null : total == 0 ? 'Nothing waiting' : '$total waiting for you'),
      if (loading) const SkeletonList(count: 3)
      else if (error != null) StateView(icon: Icons.cloud_off_rounded, title: 'Could not load', message: error, actionLabel: 'Try again', onAction: load)
      else ...[
        if (faces.isNotEmpty) ...[
          SectionTitle('Face registrations (${faces.length})'),
          for (final (i, f) in faces.indexed)
            InfoCard(color: C.accent, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(22), child: '${f['photo']}'.isEmpty
                    ? Container(width: 92, height: 92, color: Colors.white54, child: const Icon(Icons.face, size: 40))
                    : Image.memory(base64Decode(f['photo']), width: 92, height: 92, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => Container(width: 92, height: 92, color: Colors.white54, child: const Icon(Icons.broken_image)))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(f['name'], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                  Text('${f['externalId']}${'${f['department']}'.isEmpty ? '' : ' · ${f['department']}'}'),
                  const SizedBox(height: 4),
                  const Text('Confirm this photo is really this employee.', style: TextStyle(fontSize: 12)),
                ])),
              ]),
              if ('${f['similarTo']}'.isNotEmpty) Container(
                margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: C.ink, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [const Icon(Icons.warning_amber_rounded, color: C.accent, size: 20), const SizedBox(width: 8), Expanded(child: Text('Looks like ${f['similarTo']} (${((f['similarScore'] as num) * 100).round()}% similar). Check this is not the same person or a look-alike.', style: const TextStyle(color: Colors.white, fontSize: 12)))]),
              ),
              _btns('f${f['id']}', () async {
                final n = await askNote('Reject photo', required: true);
                if (n != null) run('f${f['id']}', '/owner/face-registrations/${f['id']}/reject', 'Rejected. The employee can register again.', {'note': n});
              }, () => run('f${f['id']}', '/owner/face-registrations/${f['id']}/approve', 'Face approved')),
            ])).reveal(i),
        ],
        if (resets.isNotEmpty) ...[
          SectionTitle('Face reset requests (${resets.length})'),
          for (final (i, r) in resets.indexed)
            InfoCard(color: C.lavender, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['employee']['name']} (${r['employee']['externalId']})', style: const TextStyle(fontWeight: FontWeight.w800)),
              if ('${r['reason']}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('"${r['reason']}"')),
              _btns('r${r['id']}', () => run('r${r['id']}', '/owner/face-requests/${r['id']}/reject', 'Request rejected'),
                  () => run('r${r['id']}', '/owner/face-requests/${r['id']}/approve', 'Face data reset. Employee can register again.'), yesLabel: 'Approve reset'),
            ])).reveal(i),
        ],
        SectionTitle('Leave requests (${leaves.length})'),
        Row(children: [
          Pill('Pending', selected: leaveFilter == 'PENDING', onTap: () { setState(() => leaveFilter = 'PENDING'); load(silent: true); }), const SizedBox(width: 8),
          Pill('All', selected: leaveFilter == 'ALL', onTap: () { setState(() => leaveFilter = 'ALL'); load(silent: true); }),
        ]),
        const SizedBox(height: 12),
        if (leaves.isEmpty) StateView(icon: Icons.beach_access_rounded, title: leaveFilter == 'PENDING' ? 'No pending leave requests' : 'No leave requests yet'),
        for (final (i, l) in leaves.indexed)
          InfoCard(color: Colors.white, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Avatar('${l['employee']['name']}', radius: 20), const SizedBox(width: 10),
              Expanded(child: Text('${l['employee']['name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: leaveColor(l['status']), borderRadius: BorderRadius.circular(12)), child: Text(leaveLabel(l['status']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
            ]),
            const SizedBox(height: 10),
            Text(l['fromDate'] == l['toDate'] ? l['fromDate'] : '${l['fromDate']} → ${l['toDate']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${halfText(l)} · ${'${l['type']}'.toLowerCase()}', style: const TextStyle(color: C.muted, fontSize: 12)),
            const SizedBox(height: 6),
            Text('${l['reason']}'),
            if (l['balance'] != null && l['balance']['quota'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Balance before this request: ${BalanceStrip.fmtNum(l['balance']['available'])} of ${BalanceStrip.fmtNum(l['balance']['quota'])} ${'${l['type']}'.toLowerCase()} days', style: const TextStyle(fontSize: 12, color: C.muted))),
            if ('${l['ownerNote']}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Note: ${l['ownerNote']}', style: const TextStyle(fontStyle: FontStyle.italic))),
            if (l['status'] == 'PENDING') _btns('l${l['id']}', () async {
              final n = await askNote('Reject leave', required: true);
              if (n != null) run('l${l['id']}', '/owner/leaves/${l['id']}/reject', 'Leave rejected', {'note': n});
            }, () async {
              final n = await askNote('Approve leave', required: false);
              if (n != null) run('l${l['id']}', '/owner/leaves/${l['id']}/approve', 'Leave approved', {'note': n});
            }),
            if (l['status'] == 'APPROVED') Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () async {
              final n = await askNote('Revoke approved leave', required: true);
              if (n != null) run('l${l['id']}', '/owner/leaves/${l['id']}/revoke', 'Leave revoked', {'note': n});
            }, child: const Text('Revoke'))),
          ])).reveal(i),
      ],
    ]);
  }
}
