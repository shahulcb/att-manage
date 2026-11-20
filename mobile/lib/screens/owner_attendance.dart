import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class OwnerAttendance extends StatefulWidget {
  final ValueNotifier<int> refresh;
  const OwnerAttendance({super.key, required this.refresh});
  @override
  State<OwnerAttendance> createState() => _OwnerAttendanceState();
}

class _OwnerAttendanceState extends State<OwnerAttendance> {
  DateTime day = DateTime.now();
  List rows = [], summary = [];
  String filter = 'ALL', q = '';
  bool monthly = false, loading = true, exporting = false;
  String? error;

  String get _d => '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
  @override
  void initState() { super.initState(); widget.refresh.addListener(_quiet); load(); }
  @override
  void dispose() { widget.refresh.removeListener(_quiet); super.dispose(); }
  void _quiet() => load(silent: true);

  Future<void> load({bool silent = false}) async {
    if (!silent) setState(() { loading = true; error = null; });
    try {
      if (monthly) { summary = await Api.i.get('/owner/report/monthly?month=${_d.substring(0, 7)}'); }
      else { rows = await Api.i.get('/owner/attendance?date=$_d'); }
      error = null;
    } on ApiError catch (e) { error = e.message; } catch (e) { error = '$e'; }
    if (mounted) setState(() => loading = false);
  }

  Future<void> pickDay() async {
    final p = await showDatePicker(context: context, initialDate: day, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (p != null) { day = p; load(); }
  }

  Future<void> export() async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final m = _d.substring(0, 7);
      final csv = await Api.i.getText('/owner/report/export.csv?month=$m');
      final f = File('${(await getTemporaryDirectory()).path}/attendance-$m.csv')..writeAsStringSync(csv);
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Attendance $m'));
    } catch (e) { if (mounted) toast(context, '$e', error: true); }
    finally { if (mounted) setState(() => exporting = false); }
  }

  String _status(Map? a) => a == null ? 'NOTYET' : a['status'];

  Future<void> edit(Map row) async {
    final emp = row['employee'] as Map; final a = row['attendance'] as Map?;
    TimeOfDay? tin = a?['punchIn'] != null ? TimeOfDay.fromDateTime(DateTime.parse(a!['punchIn']).toLocal()) : null;
    TimeOfDay? tout = a?['punchOut'] != null ? TimeOfDay.fromDateTime(DateTime.parse(a!['punchOut']).toLocal()) : null;
    final note = TextEditingController();
    String? err;
    String f(TimeOfDay? t) => t == null ? 'Not set' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Edit ${emp['name']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        Text(_d, style: const TextStyle(color: C.muted)), const SizedBox(height: 12),
        _timeRow('Punch in', f(tin), () async { final t = await showTimePicker(context: ctx, initialTime: tin ?? const TimeOfDay(hour: 9, minute: 0)); if (t != null) set(() => tin = t); }),
        const SizedBox(height: 8),
        _timeRow('Punch out', f(tout), () async { final t = await showTimePicker(context: ctx, initialTime: tout ?? const TimeOfDay(hour: 18, minute: 0)); if (t != null) set(() => tout = t); }),
        TextButton(onPressed: () => set(() { tin = null; tout = null; }), child: const Text('Mark absent (clear times)')),
        TextField(controller: note, onChanged: (_) { if (err != null) set(() => err = null); }, decoration: InputDecoration(hintText: 'Reason for change (required)', errorText: err)),
        const SizedBox(height: 14),
        FilledButton(onPressed: () { if (note.text.trim().isEmpty) return set(() => err = 'A reason is required'); Navigator.pop(ctx, true); }, child: const Text('Save')),
      ])),
    )));
    if (ok != true || !mounted) return;
    try {
      await Api.i.put('/owner/attendance', {'employeeId': emp['id'], 'date': _d, 'punchIn': tin == null ? null : f(tin), 'punchOut': tout == null ? null : f(tout), 'note': note.text.trim()});
      if (mounted) toast(context, 'Saved'); load(silent: true);
    } catch (e) { if (mounted) toast(context, '$e', error: true); }
  }

  Widget _timeRow(String l, String v, VoidCallback onTap) => Pressable(onTap: onTap, child: Container(
        padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: C.bg, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [Text(l, style: const TextStyle(fontWeight: FontWeight.w700)), const Spacer(), Text(v, style: const TextStyle(fontWeight: FontWeight.w800)), const SizedBox(width: 6), const Icon(Icons.access_time_rounded, size: 18)]),
      ));

  @override
  Widget build(BuildContext context) {
    final shown = rows.where((r) => (filter == 'ALL' || _status(r['attendance']) == filter) && (q.isEmpty || '${r['employee']['name']} ${r['employee']['externalId']}'.toLowerCase().contains(q.toLowerCase()))).toList();
    int cnt(String s) => rows.where((r) => _status(r['attendance']) == s).length;
    return TabPage(onRefresh: () => load(silent: true), children: [
      ScreenHeader('Attendance', subtitle: monthly ? _d.substring(0, 7) : _d, trailing: exporting
          ? const SizedBox(width: 48, height: 48, child: Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2.4, color: C.ink)))
          : RoundIcon(Icons.ios_share_rounded, dark: false, label: 'Export month as CSV', onTap: export)),
      Row(children: [
        Pill('Day', selected: !monthly, onTap: () { setState(() => monthly = false); load(); }), const SizedBox(width: 8),
        Pill('Month summary', selected: monthly, onTap: () { setState(() => monthly = true); load(); }),
        const Spacer(),
        RoundIcon(Icons.calendar_today_rounded, dark: false, label: 'Pick date', onTap: pickDay),
      ]).reveal(1),
      const SizedBox(height: 12),
      if (!monthly) ...[
        TextField(onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(hintText: 'Search name or ID', prefixIcon: Icon(Icons.search_rounded))).reveal(2),
        const SizedBox(height: 12),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          for (final x in [['ALL', 'All', rows.length], ['PRESENT', 'On time', cnt('PRESENT')], ['LATE', 'Late', cnt('LATE')], ['ABSENT', 'Absent', cnt('ABSENT')], ['LEAVE', 'Leave', cnt('LEAVE')], ['NOTYET', 'Not yet', cnt('NOTYET')]])
            Padding(padding: const EdgeInsets.only(right: 8), child: Pill(x[1] as String, count: x[2] as int, selected: filter == x[0], onTap: () => setState(() => filter = x[0] as String))),
        ])).reveal(3),
        const SizedBox(height: 14),
      ],
      if (loading) const SkeletonList()
      else if (error != null) StateView(icon: Icons.cloud_off_rounded, title: 'Could not load', message: error, actionLabel: 'Try again', onAction: load)
      else if (monthly) ...[
        if (summary.isEmpty) const StateView(icon: Icons.groups_rounded, title: 'No employees yet', message: 'Add them from the Employees tab.'),
        for (final (i, r) in summary.indexed) _monthTile(r).reveal(i),
      ]
      else if (shown.isEmpty) StateView(icon: Icons.search_off_rounded, title: rows.isEmpty ? 'No employees yet' : 'Nothing matches', message: rows.isEmpty ? 'Add them from the Employees tab.' : 'Try another filter or search.')
      else for (final (i, r) in shown.indexed) _tile(r).reveal(i),
    ]);
  }

  Widget _monthTile(Map r) {
    Widget chip(String l, dynamic v, Color c) => Container(margin: const EdgeInsets.only(right: 6, top: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(14)), child: Text('$l $v', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)));
    return InfoCard(color: Colors.white, padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Avatar(r['employee']['name'], radius: 20), const SizedBox(width: 10), Expanded(child: Text(r['employee']['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))), Text('${(r['workedMinutes'] / 60).toStringAsFixed(1)} h', style: const TextStyle(fontWeight: FontWeight.w800))]),
      Wrap(children: [
        chip('On time', r['present'], C.accent), chip('Late', r['late'], C.lavender), chip('Absent', r['absent'], C.grey), chip('Leave', r['leave'], C.sky),
        chip('Early exit', r['earlyExits'], C.grey), chip('Long lunch', r['lunchOver'], C.grey), chip('No punch-out', r['missingPunchOut'], C.grey),
      ]),
    ]));
  }

  Widget _tile(Map r) {
    final a = r['attendance'] as Map?; final s = _status(a);
    final dark = s == 'ABSENT';
    return Pressable(
      onTap: () => edit(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), boxShadow: [BoxShadow(color: C.ink.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 5))]),
        child: Row(children: [
          Avatar(r['employee']['name'], radius: 24), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['employee']['name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            Text(a == null ? 'Not punched in yet' : s == 'ABSENT' ? 'Absent' : s == 'LEAVE' ? 'On approved leave' : 'In ${fmtTime(a['punchIn'])} · Out ${fmtTime(a['punchOut'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted, fontSize: 12)),
            if (a != null && a['lunchOut'] != null) Text('Lunch ${fmtTime(a['lunchOut'])}–${fmtTime(a['lunchIn'])}${(a['lunchOverMinutes'] ?? 0) > 0 ? ' (+${fmtMin(a['lunchOverMinutes'])})' : ''}', style: const TextStyle(color: C.muted, fontSize: 12)),
            if (a != null && ((a['lateMinutes'] ?? 0) > 0 || (a['earlyMinutes'] ?? 0) > 0)) Text([if (a['lateMinutes'] > 0) 'Late ${fmtMin(a['lateMinutes'])}', if (a['earlyMinutes'] > 0) 'Early ${fmtMin(a['earlyMinutes'])}'].join(' · '), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            if (a != null && a['manual'] == true) const Text('Edited manually', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: C.muted)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7), decoration: BoxDecoration(color: statusColor(s), borderRadius: BorderRadius.circular(14)),
            child: Text(switch (s) { 'PRESENT' => 'On time', 'LATE' => 'Late', 'ABSENT' => 'Absent', 'LEAVE' => 'Leave', _ => 'Not yet' }, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: dark ? Colors.white : C.ink)),
          ),
        ]),
      ),
    );
  }
}
