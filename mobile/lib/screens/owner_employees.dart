import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Shows a freshly generated login once, with a copy button.
  Future<void> showLogin(String title, String username, String password) => showDialog(context: context, builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Username', style: TextStyle(color: C.muted, fontSize: 12)), SelectableText(username, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 12),
          const Text('Password', style: TextStyle(color: C.muted, fontSize: 12)), SelectableText(password, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 12),
          const Text('This password is shown only now. Send it to the employee privately.', style: TextStyle(fontSize: 12, color: C.muted)),
        ]),
        actions: [
          TextButton(onPressed: () { Clipboard.setData(ClipboardData(text: 'Username: $username\nPassword: $password')); toast(ctx, 'Copied'); }, child: const Text('Copy')),
          FilledButton(style: FilledButton.styleFrom(minimumSize: const Size(96, 44)), onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
        ],
      ));

  Future<void> addEmployee() async {
    final name = TextEditingController(), user = TextEditingController(), pass = TextEditingController(), dept = TextEditingController();
    final errs = <String, String?>{};
    bool saving = false;
    final done = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (ctx) => StatefulBuilder(builder: (ctx, set) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
      child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Add employee', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
        const SizedBox(height: 14),
        TextField(controller: name, textCapitalization: TextCapitalization.words, textInputAction: TextInputAction.next, decoration: InputDecoration(hintText: 'Full name', errorText: errs['name'])),
        const SizedBox(height: 10),
        TextField(controller: user, autocorrect: false, textInputAction: TextInputAction.next, decoration: InputDecoration(hintText: 'Username (letters, numbers, . _ -)', errorText: errs['user'])),
        const SizedBox(height: 10),
        TextField(controller: pass, obscureText: false, autocorrect: false, textInputAction: TextInputAction.next, decoration: InputDecoration(hintText: 'Password (empty = generate one)', errorText: errs['pass'])),
        const SizedBox(height: 10),
        TextField(controller: dept, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'Department (optional)')),
        const SizedBox(height: 16),
        ActionButton(label: 'Create account', icon: Icons.person_add_alt_1_rounded, dark: true, loading: saving, onPressed: () async {
          set(() { errs['name'] = name.text.trim().length < 2 ? 'Enter the full name' : null; errs['user'] = RegExp(r'^[A-Za-z0-9._-]{3,30}$').hasMatch(user.text.trim()) ? null : 'Use 3-30 letters, numbers, . _ -'; errs['pass'] = pass.text.isNotEmpty && pass.text.length < 8 ? 'At least 8 characters' : null; });
          if (errs.values.any((v) => v != null)) return;
          set(() => saving = true);
          try {
            final r = await Api.i.post('/owner/employees', {'name': name.text.trim(), 'username': user.text.trim(), if (pass.text.isNotEmpty) 'password': pass.text, 'department': dept.text.trim()});
            if (ctx.mounted) Navigator.pop(ctx, true);
            if (mounted) {
              await load();
              if (r['password'] != null && mounted) { await showLogin('Account created', r['username'], r['password']); } else if (mounted) { toast(context, 'Account created'); }
            }
          } on ApiError catch (e) {
            set(() { saving = false; if (e.code == 'USERNAME_TAKEN') { errs['user'] = e.message; } else { toast(ctx, e.message, error: true); } });
          } catch (e) { set(() => saving = false); if (ctx.mounted) toast(ctx, '$e', error: true); }
        }),
      ])),
    )));
    if (done != true) { /* cancelled */ }
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
        if (e['username'] != null) ListTile(leading: const Icon(Icons.password_rounded), title: const Text('Reset password'), onTap: () => Navigator.pop(ctx, 'pw')),
        ListTile(leading: const Icon(Icons.face_retouching_off), title: const Text('Reset face data'), onTap: () => Navigator.pop(ctx, 'face')),
        ListTile(leading: Icon(e['active'] == true ? Icons.block_rounded : Icons.check_circle_outline_rounded), title: Text(e['active'] == true ? 'Deactivate account' : 'Activate account'), onTap: () => Navigator.pop(ctx, 'active')),
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
      } else if (a == 'pw') {
        if (await confirm(context, 'Reset password', 'Create a new password for ${e['name']}? Their old password stops working.', yes: 'Reset')) {
          final r = await Api.i.post('/owner/employees/${e['id']}/reset-password');
          if (mounted) await showLogin('New password', r['username'], r['password']);
        }
      } else if (a == 'active') {
        final on = e['active'] == true;
        if (await confirm(context, on ? 'Deactivate' : 'Activate', on ? '${e['name']} will not be able to sign in or punch. Their history is kept.' : '${e['name']} will be able to sign in again.', yes: on ? 'Deactivate' : 'Activate')) {
          await Api.i.post('/owner/employees/${e['id']}/active', {'active': !on});
          if (mounted) toast(context, on ? 'Deactivated' : 'Activated');
          load();
        }
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
      ScreenHeader('Employees', subtitle: loading ? null : '${list.length} in total', trailing: RoundIcon(Icons.person_add_alt_1_rounded, label: 'Add employee', onTap: addEmployee)),
      TextField(onChanged: (v) => setState(() => q = v), decoration: const InputDecoration(hintText: 'Search name, ID or department', prefixIcon: Icon(Icons.search_rounded))).reveal(1),
      const SizedBox(height: 14),
      if (loading) const SkeletonList()
      else if (error != null) StateView(icon: Icons.cloud_off_rounded, title: 'Could not load', message: error, actionLabel: 'Try again', onAction: load)
      else if (shown.isEmpty) StateView(icon: q.isEmpty ? Icons.groups_rounded : Icons.search_off_rounded, title: q.isEmpty ? 'No employees yet' : 'No match for "$q"', message: q.isEmpty ? 'Tap the + button to add the first employee.' : null)
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
                Text('${e['username'] != null ? '@${e['username']} · ' : ''}${e['externalId']}${'${e['department']}'.isEmpty ? '' : ' · ${e['department']}'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)),
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
