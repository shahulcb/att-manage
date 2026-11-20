import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../api.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/ui.dart';

enum HistoryMode { calendar, chart }

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

class EmployeeHistory extends StatefulWidget {
  final HistoryMode mode;
  const EmployeeHistory({super.key, required this.mode});
  @override
  State<EmployeeHistory> createState() => _EmployeeHistoryState();
}

class _EmployeeHistoryState extends State<EmployeeHistory> {
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, Map> byDate = {};
  String? error, selected;
  bool loading = true, weekly = false;

  @override
  void initState() { super.initState(); load(); }

  String get _m => '${month.year}-${month.month.toString().padLeft(2, '0')}';
  bool get _isCurrent => month.year == DateTime.now().year && month.month == DateTime.now().month;

  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      final r = await Api.i.get('/me/attendance?month=$_m') as List;
      byDate = {for (final x in r) x['date'] as String: x as Map};
    } on ApiError catch (e) { error = e.message; } catch (e) { error = '$e'; }
    if (mounted) setState(() => loading = false);
  }

  void shift(int d) { month = DateTime(month.year, month.month + d); selected = null; load(); }

  @override
  Widget build(BuildContext context) {
    final cal = widget.mode == HistoryMode.calendar;
    return TabPage(onRefresh: load, children: [
      ScreenHeader(cal ? 'Attendance' : 'Statistics', subtitle: cal ? 'Tap a day for details' : 'Your punctuality and hours'),
      // month switcher
      Container(
        padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
        child: Row(children: [
          IconButton(tooltip: 'Previous month', icon: const Icon(Icons.chevron_left_rounded), onPressed: () => shift(-1)),
          Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: Text('${_monthNames[month.month - 1]} ${month.year}', key: ValueKey(_m), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)))),
          IconButton(tooltip: 'Next month', icon: const Icon(Icons.chevron_right_rounded), onPressed: _isCurrent ? null : () => shift(1)),
        ]),
      ).reveal(1),
      const SizedBox(height: 16),
      if (loading) const SkeletonList(count: 3)
      else if (error != null) StateView(icon: Icons.cloud_off_rounded, title: 'Could not load', message: error, actionLabel: 'Try again', onAction: load)
      else if (byDate.isEmpty) StateView(icon: cal ? Icons.event_busy_rounded : Icons.insights_rounded, title: 'No attendance yet', message: 'Nothing recorded for ${_monthNames[month.month - 1]}.')
      else ...(cal ? _calendar() : _stats()),
    ]);
  }

  // ───────── calendar ─────────

  List<Widget> _calendar() {
    final first = DateTime(month.year, month.month, 1);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final lead = first.weekday % 7; // Sunday first
    final sel = selected != null ? byDate[selected!] : null;
    return [
      InfoCard(color: Colors.white, padding: const EdgeInsets.all(14), child: Column(children: [
        Row(children: [for (final d in ['S', 'M', 'T', 'W', 'T', 'F', 'S']) Expanded(child: Center(child: Text(d, style: const TextStyle(fontWeight: FontWeight.w800, color: C.muted))))]),
        const SizedBox(height: 8),
        GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 6, crossAxisSpacing: 6, children: [
          for (var i = 0; i < lead; i++) const SizedBox(),
          for (var d = 1; d <= days; d++) _dayCell(d),
        ]),
      ])).reveal(2),
      Wrap(spacing: 14, runSpacing: 6, children: const [_Legend(C.accent, 'On time'), _Legend(C.lavender, 'Late'), _Legend(C.ink, 'Absent'), _Legend(C.sky, 'Leave')]),
      const SizedBox(height: 14),
      AnimatedSize(
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut,
        child: selected == null ? const SizedBox(width: double.infinity) : _detail(sel),
      ),
    ];
  }

  Widget _detail(Map? sel) {
    final st = sel?['status'] as String?;
    return InfoCard(
      key: ValueKey(selected), color: sel == null ? Colors.white : statusColor(st),
      child: sel == null
          ? Text('No record for $selected', style: const TextStyle(fontWeight: FontWeight.w700))
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fmtDate(DateTime.parse(selected!)), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 8),
              if (st == 'ABSENT') const Text('Absent (no punch in)')
              else if (st == 'LEAVE') const Text('On approved leave')
              else ...[
                Text('In ${fmtTime(sel['punchIn'])}   ·   Out ${fmtTime(sel['punchOut'])}'),
                if (sel['lunchOut'] != null) Text('Lunch ${fmtTime(sel['lunchOut'])} – ${fmtTime(sel['lunchIn'])} (${fmtMin(sel['lunchTakenMinutes'])})'),
                if ((sel['lunchOverMinutes'] ?? 0) > 0) Text('Lunch over by ${fmtMin(sel['lunchOverMinutes'])}'),
                if (sel['punchOut'] != null) Text('Worked ${fmtMin(sel['workedMinutes'])}', style: const TextStyle(fontWeight: FontWeight.w800)) else const Text('No punch out recorded'),
                if (sel['lateMinutes'] > 0) Text('Late by ${fmtMin(sel['lateMinutes'])}'),
                if (sel['earlyMinutes'] > 0) Text('Early exit by ${fmtMin(sel['earlyMinutes'])}'),
              ],
              if (sel['manual'] == true) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Edited by owner: ${sel['note']}', style: const TextStyle(fontStyle: FontStyle.italic))),
            ]),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.08, end: 0);
  }

  Widget _dayCell(int d) {
    final key = '$_m-${d.toString().padLeft(2, '0')}';
    final st = byDate[key]?['status'] as String?;
    final isToday = _isCurrent && d == DateTime.now().day;
    final isSel = selected == key;
    return Semantics(
      button: true, label: '$d, ${st ?? 'no record'}',
      child: Pressable(
        onTap: () => setState(() => selected = isSel ? null : key),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(color: st == null ? C.bg : statusColor(st), shape: BoxShape.circle, border: isSel ? Border.all(color: C.ink, width: 2.4) : isToday ? Border.all(color: C.ink, width: 1.2) : null),
          alignment: Alignment.center,
          child: Text('$d', style: TextStyle(color: st == 'ABSENT' ? Colors.white : C.ink, fontWeight: isToday ? FontWeight.w900 : FontWeight.w600, fontSize: 13)),
        ),
      ).animate().scale(delay: Duration(milliseconds: 12 * d), duration: 300.ms, curve: Curves.easeOutBack).fadeIn(),
    );
  }

  // ───────── statistics (like the reference) ─────────

  List<Widget> _stats() {
    var keys = byDate.keys.toList()..sort();
    if (weekly && keys.length > 7) keys = keys.sublist(keys.length - 7);
    final recs = [for (final k in keys) byDate[k]!];
    final present = recs.where((r) => r['status'] == 'PRESENT').length;
    final late = recs.where((r) => r['status'] == 'LATE').length;
    final absent = recs.where((r) => r['status'] == 'ABSENT').length;
    final leave = recs.where((r) => r['status'] == 'LEAVE').length;
    final counted = present + late + absent;
    final pct = counted == 0 ? 0.0 : (present + late) / counted; // attended
    final onTimePct = (present + late) == 0 ? 0.0 : present / (present + late);
    final minutes = recs.fold<int>(0, (a, r) => a + (r['workedMinutes'] as int));
    final early = recs.where((r) => (r['earlyMinutes'] as int) > 0).length;
    const goal = 0.9;

    return [
      Row(children: [
        Pill('Week', selected: weekly, onTap: () => setState(() => weekly = true)), const SizedBox(width: 8),
        Pill('Month', selected: !weekly, onTap: () => setState(() => weekly = false)),
      ]).reveal(2),
      const SizedBox(height: 14),
      IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: InfoCard(color: C.accent, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.trending_up_rounded, size: 18), SizedBox(width: 6), Text('On time', style: TextStyle(fontWeight: FontWeight.w800))]),
          const SizedBox(height: 10),
          CountUp(onTimePct * 100, suffix: '%', style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: -1)),
          const Text('of your working days started on time', style: TextStyle(fontSize: 12)),
          const Spacer(),
          const SizedBox(height: 14),
          Text('Goal ${(goal * 100).round()}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)), const SizedBox(height: 6),
          DotsProgress(value: onTimePct / goal, count: 12),
        ]))),
        const SizedBox(width: 12),
        Expanded(child: InfoCard(color: C.ink, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.schedule_rounded, size: 18, color: C.accent), SizedBox(width: 6), Text('Hours', style: TextStyle(fontWeight: FontWeight.w800))]),
          const SizedBox(height: 14),
          Center(child: ProgressRing(value: pct, size: 96, stroke: 11, center: Text('${(pct * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white)))),
          const SizedBox(height: 12),
          Center(child: Text('${(minutes / 60).toStringAsFixed(1)} h worked', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600))),
        ]))),
      ])).reveal(3),
      const SectionTitle('Overview'),
      InfoCard(color: Colors.white, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Hours per day', style: TextStyle(fontWeight: FontWeight.w800))),
          Text('${(minutes / 60).toStringAsFixed(1)} h', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        ]),
        const SizedBox(height: 4),
        const Text('Tap a bar for details', style: TextStyle(color: C.muted, fontSize: 12)),
        const SizedBox(height: 14),
        BarChart(bars: [
          for (final k in keys)
            Bar(k.substring(8), ((byDate[k]!['workedMinutes'] as int) / 60), statusColor(byDate[k]!['status']),
                '${(byDate[k]!['workedMinutes'] / 60).toStringAsFixed(1)} h'),
        ]),
        const SizedBox(height: 10),
        const Wrap(spacing: 14, runSpacing: 6, children: [_Legend(C.accent, 'On time'), _Legend(C.lavender, 'Late'), _Legend(C.sky, 'Leave')]),
      ])).reveal(4),
      Row(children: [
        Expanded(child: _Stat('On time', '$present', C.accent)), const SizedBox(width: 10),
        Expanded(child: _Stat('Late', '$late', C.lavender)), const SizedBox(width: 10),
        Expanded(child: _Stat('Absent', '$absent', Colors.white)),
      ]).reveal(5),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _Stat('Leave', '$leave', C.sky)), const SizedBox(width: 10),
        Expanded(child: _Stat('Early exits', '$early', Colors.white)), const SizedBox(width: 10),
        const Expanded(child: SizedBox()),
      ]).reveal(6),
    ];
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Stat(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CountUp(int.parse(value), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _Legend extends StatelessWidget {
  final Color c;
  final String t;
  const _Legend(this.c, this.t);
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: c == C.ink ? null : Border.all(color: C.ink.withValues(alpha: 0.15)))),
        const SizedBox(width: 6), Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]);
}
