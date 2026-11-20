import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/ui.dart';

String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Color leaveColor(String s) => switch (s) { 'APPROVED' => C.accent, 'PENDING' => C.lavender, 'REJECTED' => const Color(0xFFF6D5D2), _ => C.grey };
String leaveLabel(String s) => {'APPROVED': 'Approved', 'PENDING': 'Pending', 'REJECTED': 'Rejected', 'CANCELLED': 'Cancelled'}[s] ?? s;
String daysText(dynamic d) { final v = (d as num).toDouble(); return v == v.roundToDouble() ? '${v.round()} day${v == 1 ? '' : 's'}' : '$v day'; }
String halfText(Map l) => l['halfDay'] == true ? (l['halfSession'] == 'FIRST' ? 'Half day · morning off' : 'Half day · afternoon off') : daysText(l['days'] ?? 0);
String _type(dynamic t) => '$t'[0] + '$t'.substring(1).toLowerCase();

/// "Casual: 8 left of 12" cards; with no quota it shows days used instead.
class BalanceStrip extends StatelessWidget {
  final Map? data;
  const BalanceStrip(this.data, {super.key});
  static String fmtNum(dynamic v) { final d = (v as num).toDouble(); return d == d.roundToDouble() ? '${d.round()}' : '$d'; }
  @override
  Widget build(BuildContext context) {
    if (data == null) return const SizedBox();
    final quota = data!['quotaEnabled'] == true;
    final colors = {'CASUAL': C.accent, 'SICK': C.lavender, 'OTHER': C.sky};
    final shown = [for (final b in data!['balances'] as List) if (!(quota && b['quota'] == 0)) b];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(quota ? 'Leave balance · ${data!['year']}' : 'Leave taken · ${data!['year']} (no quota)', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: C.muted)),
      const SizedBox(height: 8),
      Row(children: [
        for (final (i, b) in shown.indexed)
          Expanded(child: Container(
            margin: EdgeInsets.only(right: i == shown.length - 1 ? 0 : 8), padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: colors[b['type']], borderRadius: BorderRadius.circular(24)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_type(b['type']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              CountUp(quota ? b['available'] : b['used'], decimals: ((quota ? b['available'] : b['used']) as num) % 1 == 0 ? 0 : 1, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
              Text(quota ? 'left of ${fmtNum(b['quota'])}${(b['pending'] as num) > 0 ? '\n${fmtNum(b['pending'])} pending' : ''}' : 'used${(b['pending'] as num) > 0 ? '\n${fmtNum(b['pending'])} pending' : ''}', style: const TextStyle(fontSize: 11)),
            ]),
          ).animate().fadeIn(delay: Duration(milliseconds: 80 * i)).scale(begin: const Offset(0.92, 0.92), curve: Curves.easeOut)),
      ]),
      const SizedBox(height: 14),
    ]);
  }
}

class EmployeeLeave extends StatefulWidget {
  const EmployeeLeave({super.key});
  @override
  State<EmployeeLeave> createState() => _EmployeeLeaveState();
}

class _EmployeeLeaveState extends State<EmployeeLeave> {
  List list = [];
  Map? bal;
  bool loading = true;
  String? error;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try { list = await Api.i.get('/me/leaves'); bal = await Api.i.get('/me/leave-balance'); error = null; }
    on ApiError catch (e) { error = e.message; } catch (e) { error = '$e'; }
    if (mounted) setState(() => loading = false);
  }

  Future<void> request() async {
    DateTimeRange? range;
    String type = 'CASUAL', session = 'FIRST';
    bool half = false;
    String? err;
    final reason = TextEditingController();
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Request leave', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        const SizedBox(height: 16),
        Pressable(
          onTap: () async {
            final now = DateTime.now();
            final r = await showDateRangePicker(context: ctx, firstDate: now.subtract(const Duration(days: 7)), lastDate: now.add(const Duration(days: 365)), initialDateRange: range);
            if (r != null) set(() { range = r; err = null; if (ymd(r.start) != ymd(r.end)) half = false; });
          },
          child: Container(
            padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(20)),
            child: Row(children: [const Icon(Icons.date_range_rounded), const SizedBox(width: 12), Expanded(child: Text(range == null ? 'Choose dates' : (ymd(range!.start) == ymd(range!.end) ? ymd(range!.start) : '${ymd(range!.start)}  →  ${ymd(range!.end)}'), style: const TextStyle(fontWeight: FontWeight.w700)))]),
          ),
        ),
        AnimatedSize(duration: const Duration(milliseconds: 250), child: range != null && ymd(range!.start) == ymd(range!.end)
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Half day', style: TextStyle(fontWeight: FontWeight.w700)), value: half, onChanged: (v) => set(() => half = v)),
                if (half) Wrap(spacing: 8, children: [Pill('Morning off', selected: session == 'FIRST', onTap: () => set(() => session = 'FIRST')), Pill('Afternoon off', selected: session == 'SECOND', onTap: () => set(() => session = 'SECOND'))]),
              ])
            : const SizedBox(width: double.infinity)),
        const SizedBox(height: 14),
        Wrap(spacing: 8, children: [for (final t in ['CASUAL', 'SICK', 'OTHER']) Pill(_type(t), selected: type == t, onTap: () => set(() => type = t))]),
        const SizedBox(height: 14),
        TextField(controller: reason, maxLines: 3, maxLength: 500, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Reason (required)'), onChanged: (_) { if (err != null) set(() => err = null); }),
        if (err != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [const Icon(Icons.error_outline, size: 16, color: C.danger), const SizedBox(width: 6), Expanded(child: Text(err!, style: const TextStyle(color: C.danger, fontWeight: FontWeight.w600)))])).animate().shake(hz: 4),
        const SizedBox(height: 8),
        FilledButton(onPressed: () {
          if (range == null) return set(() => err = 'Choose the leave dates');
          if (reason.text.trim().length < 3) return set(() => err = 'Please give a reason');
          Navigator.pop(ctx, true);
        }, child: const Text('Send request')),
      ])),
    )));
    if (ok != true || range == null || !mounted) return;
    try {
      await Api.i.post('/me/leaves', {'fromDate': ymd(range!.start), 'toDate': ymd(range!.end), 'type': type, 'reason': reason.text.trim(), 'halfDay': half, if (half) 'halfSession': session});
      if (mounted) toast(context, 'Leave request sent to the owner');
      load();
    } catch (e) { if (mounted) toast(context, '$e', error: true); }
  }

  Future<void> cancel(Map l) async {
    if (!await confirm(context, 'Cancel leave', 'Cancel your leave request for ${l['fromDate']}?', yes: 'Cancel request')) return;
    try { await Api.i.post('/me/leaves/${l['id']}/cancel'); if (mounted) toast(context, 'Cancelled'); load(); }
    catch (e) { if (mounted) toast(context, '$e', error: true); }
  }

  @override
  Widget build(BuildContext context) => TabPage(onRefresh: load, children: [
        ScreenHeader('Leave', subtitle: 'Request time off', trailing: RoundIcon(Icons.add_rounded, label: 'New leave request', onTap: request)),
        if (loading) const SkeletonList(count: 3)
        else if (error != null) StateView(icon: Icons.cloud_off_rounded, title: 'Could not load', message: error, actionLabel: 'Try again', onAction: load)
        else ...[
          BalanceStrip(bal),
          if (list.isEmpty) StateView(icon: Icons.beach_access_rounded, title: 'No leave requests', message: 'Tap + to request time off.', actionLabel: 'Request leave', onAction: request)
          else for (final (i, l) in list.indexed)
            InfoCard(color: Colors.white, padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 40, decoration: BoxDecoration(color: leaveColor(l['status']), borderRadius: BorderRadius.circular(4))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l['fromDate'] == l['toDate'] ? l['fromDate'] : '${l['fromDate']} → ${l['toDate']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text('${halfText(l)} · ${_type(l['type'])}', style: const TextStyle(color: C.muted, fontSize: 12)),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: leaveColor(l['status']), borderRadius: BorderRadius.circular(14)), child: Text(leaveLabel(l['status']), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
              ]),
              const SizedBox(height: 10),
              Text('${l['reason']}'),
              if ('${l['ownerNote']}'.isNotEmpty) Container(margin: const EdgeInsets.only(top: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(16)), child: Text('Owner: ${l['ownerNote']}', style: const TextStyle(fontStyle: FontStyle.italic))),
              if (l['status'] == 'PENDING' || l['status'] == 'APPROVED') Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => cancel(l), child: const Text('Cancel request'))),
            ])).reveal(i),
        ],
      ]);
}
