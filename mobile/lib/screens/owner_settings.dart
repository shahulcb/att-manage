import 'package:flutter/material.dart';
import '../api.dart';
import '../punch_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class OwnerSettings extends StatefulWidget {
  const OwnerSettings({super.key});
  @override
  State<OwnerSettings> createState() => _OwnerSettingsState();
}

class _OwnerSettingsState extends State<OwnerSettings> {
  Map? s;
  String? error;
  bool saving = false;
  final c = <String, TextEditingController>{};
  Set<int> days = {};
  bool quotaOn = false;

  static const keys = ['orgName', 'officeLat', 'officeLng', 'radiusM', 'workStart', 'workEnd', 'graceMinutes', 'timezone', 'maxAccuracyM', 'lunchStart', 'lunchEnd', 'lunchMinutes', 'holidays', 'faceThreshold', 'faceMargin', 'leaveQuotaCasual', 'leaveQuotaSick', 'leaveQuotaOther', 'leaveYearStartMonth'];

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    try {
      s = await Api.i.get('/owner/settings');
      for (final k in keys) { c.putIfAbsent(k, TextEditingController.new).text = s![k] == null ? '' : '${s![k]}'; }
      days = (s!['workDays'] as String).split(',').map(int.parse).toSet();
      quotaOn = s!['leaveQuotaEnabled'] == true;
      error = null;
    } catch (e) { error = '$e'; }
    if (mounted) setState(() {});
  }

  Future<void> useMyLocation() async {
    try {
      final p = await PunchService.currentLocation();
      if (p.isMocked) throw ApiError(0, 'MOCK', 'Mock location is on. Turn it off.');
      c['officeLat']!.text = p.latitude.toStringAsFixed(6);
      c['officeLng']!.text = p.longitude.toStringAsFixed(6);
      setState(() {});
      if (mounted) toast(context, 'Location captured (±${p.accuracy.round()} m). Stand at the office entrance for best accuracy, then Save.');
    } catch (e) { if (mounted) toast(context, '$e', error: true); }
  }

  Future<void> save() async {
    double? d(String k) => c[k]!.text.trim().isEmpty ? null : double.tryParse(c[k]!.text.trim());
    int? n(String k) => int.tryParse(c[k]!.text.trim());
    final lat = d('officeLat'), lng = d('officeLng');
    if ((lat == null) != (lng == null) || (c['officeLat']!.text.trim().isNotEmpty && lat == null) || (c['officeLng']!.text.trim().isNotEmpty && lng == null)) return toast(context, 'Enter valid latitude and longitude', error: true);
    if (n('radiusM') == null || n('graceMinutes') == null || n('maxAccuracyM') == null) return toast(context, 'Radius, grace and accuracy must be whole numbers', error: true);
    if (days.isEmpty) return toast(context, 'Select at least one working day', error: true);
    setState(() => saving = true);
    try {
      s = await Api.i.put('/owner/settings', {
        'orgName': c['orgName']!.text.trim(), 'officeLat': lat, 'officeLng': lng, 'radiusM': n('radiusM'),
        'workStart': c['workStart']!.text.trim(), 'workEnd': c['workEnd']!.text.trim(), 'graceMinutes': n('graceMinutes'),
        'lunchStart': c['lunchStart']!.text.trim(), 'lunchEnd': c['lunchEnd']!.text.trim(), 'lunchMinutes': int.tryParse(c['lunchMinutes']!.text.trim()) ?? 60,
        'holidays': c['holidays']!.text.replaceAll(' ', ''), 'faceThreshold': double.tryParse(c['faceThreshold']!.text.trim()) ?? 0.65, 'faceMargin': double.tryParse(c['faceMargin']!.text.trim()) ?? 0.05, 'leaveQuotaEnabled': quotaOn,
        'leaveQuotaCasual': double.tryParse(c['leaveQuotaCasual']!.text.trim()) ?? 0, 'leaveQuotaSick': double.tryParse(c['leaveQuotaSick']!.text.trim()) ?? 0,
        'leaveQuotaOther': double.tryParse(c['leaveQuotaOther']!.text.trim()) ?? 0, 'leaveYearStartMonth': int.tryParse(c['leaveYearStartMonth']!.text.trim()) ?? 1, 'workDays': (days.toList()..sort()).join(','), 'timezone': c['timezone']!.text.trim(), 'maxAccuracyM': n('maxAccuracyM'),
      });
      if (mounted) toast(context, 'Settings saved');
    } catch (e) { if (mounted) toast(context, '$e', error: true); }
    finally { if (mounted) setState(() => saving = false); }
  }

  Widget _t(String k, String label, {TextInputType? type, int lines = 1, bool obscure = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(controller: c[k], keyboardType: type, maxLines: lines, obscureText: obscure, decoration: InputDecoration(labelText: label)));

  Widget _h(String t) => SectionTitle(t);

  @override
  Widget build(BuildContext context) {
    if (s == null) {
      return TabPage(onRefresh: load, children: [error != null ? StateView(icon: Icons.cloud_off_rounded, title: 'Could not load settings', message: error, actionLabel: 'Try again', onAction: load) : const SkeletonList(count: 5)]);
    }
    const dn = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return TabPage(onRefresh: load, children: [
      const ScreenHeader('Settings', subtitle: 'Hours, location and rules'),
      _h('Organisation'),
      _t('orgName', 'Organisation name'),
      _h('Punch location'),
      InfoCard(color: C.accent, child: const Text('One common office location for everyone. Employees can punch only inside this radius.')),
      Row(children: [Expanded(child: _t('officeLat', 'Latitude', type: const TextInputType.numberWithOptions(decimal: true, signed: true))), const SizedBox(width: 10), Expanded(child: _t('officeLng', 'Longitude', type: const TextInputType.numberWithOptions(decimal: true, signed: true)))]),
      OutlinedButton.icon(onPressed: useMyLocation, icon: const Icon(Icons.my_location), label: const Text('Use my current location')),
      const SizedBox(height: 12),
      Row(children: [Expanded(child: _t('radiusM', 'Radius (meters)', type: TextInputType.number)), const SizedBox(width: 10), Expanded(child: _t('maxAccuracyM', 'Max GPS error (m)', type: TextInputType.number))]),
      _h('Work hours'),
      Row(children: [Expanded(child: _t('workStart', 'Start (HH:MM)')), const SizedBox(width: 10), Expanded(child: _t('workEnd', 'End (HH:MM)'))]),
      _t('graceMinutes', 'Late grace (minutes)', type: TextInputType.number),
      _t('timezone', 'Timezone (e.g. Asia/Kolkata)'),
      Wrap(spacing: 8, runSpacing: 8, children: [for (var i = 0; i < 7; i++) Pill(dn[i], selected: days.contains(i), onTap: () => setState(() => days.contains(i) ? days.remove(i) : days.add(i)))]),
      _h('Lunch break'),
      Row(children: [Expanded(child: _t('lunchStart', 'Can start from (HH:MM)')), const SizedBox(width: 10), Expanded(child: _t('lunchEnd', 'Must start by (HH:MM)'))]),
      _t('lunchMinutes', 'Allowed length (minutes)', type: TextInputType.number),
      _h('Face matching'),
      Row(children: [
        Expanded(child: _t('faceThreshold', 'Match strictness (0.40–0.90)', type: const TextInputType.numberWithOptions(decimal: true))), const SizedBox(width: 10),
        Expanded(child: _t('faceMargin', 'Look-alike margin (0–0.20)', type: const TextInputType.numberWithOptions(decimal: true))),
      ]),
      const Text('Higher strictness = fewer wrong people accepted, but more genuine retries. Start at 0.65 and use Employees → Face checks to see real scores before changing it.', style: TextStyle(color: Colors.black54, fontSize: 12)),
      _h('Leave quota'),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Limit leave with a yearly quota'), subtitle: Text(quotaOn ? 'Requests over the balance are blocked' : 'Off: employees can take any amount of leave'), value: quotaOn, onChanged: (v) => setState(() => quotaOn = v)),
      if (quotaOn) ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _t('leaveQuotaCasual', 'Casual (days)', type: const TextInputType.numberWithOptions(decimal: true))), const SizedBox(width: 10),
          Expanded(child: _t('leaveQuotaSick', 'Sick (days)', type: const TextInputType.numberWithOptions(decimal: true))), const SizedBox(width: 10),
          Expanded(child: _t('leaveQuotaOther', 'Other (days)', type: const TextInputType.numberWithOptions(decimal: true))),
        ]),
        const Text('0 means that type is not allowed. Half days count as 0.5.', style: TextStyle(color: Colors.black54, fontSize: 12)),
        const SizedBox(height: 12),
        _t('leaveYearStartMonth', 'Leave year starts in month (1 = Jan … 12 = Dec)', type: TextInputType.number),
      ],
      _h('Holidays'),
      _t('holidays', 'Holiday dates (YYYY-MM-DD, comma separated)', lines: 2),
      const SizedBox(height: 20),
      ActionButton(label: 'Save settings', icon: Icons.check_rounded, onPressed: save, loading: saving, dark: true),
    ]);
  }
}
