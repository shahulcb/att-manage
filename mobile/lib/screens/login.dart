import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../api.dart';
import '../main.dart' show fadeRoute;
import '../theme.dart';
import '../widgets/ui.dart';
import 'employee_shell.dart';
import 'owner_shell.dart';

class LoginScreen extends StatefulWidget {
  final String? message; // e.g. "session expired"
  const LoginScreen({super.key, this.message});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool busy = false, hide = true;
  final id = TextEditingController(), pw = TextEditingController();
  final _pwFocus = FocusNode();
  String? idError, pwError, formError;

  @override
  void initState() {
    super.initState();
    formError = widget.message;
  }

  @override
  void dispose() { id.dispose(); pw.dispose(); _pwFocus.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (busy) return; // no double submits
    FocusScope.of(context).unfocus();
    setState(() {
      idError = id.text.trim().isEmpty ? 'Enter your username or email' : null;
      pwError = pw.text.isEmpty ? 'Enter your password' : null;
      formError = null;
    });
    if (idError != null || pwError != null) return;
    setState(() => busy = true);
    try {
      final r = await Api.i.post('/auth/login', {'identifier': id.text.trim(), 'password': pw.text});
      await Api.i.saveSession(r);
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(context, fadeRoute(r['role'] == 'owner' ? const OwnerShell() : const EmployeeShell()), (_) => false);
    } on ApiError catch (e) {
      if (mounted) setState(() { formError = e.message; if (e.code == 'BAD_CREDENTIALS') pw.clear(); });
    } catch (e) {
      if (mounted) setState(() => formError = '$e');
    } finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      backgroundColor: C.bg,
      resizeToAvoidBottomInset: false,
      body: Column(children: [
        // neutral hero
        Expanded(
          child: SafeArea(
            bottom: false,
            child: AnimatedOpacity(
              opacity: kb > 0 ? 0.0 : 1, duration: const Duration(milliseconds: 200),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(width: 64, height: 64, decoration: const BoxDecoration(color: C.ink, shape: BoxShape.circle), child: const Icon(Icons.fingerprint_rounded, color: C.accent, size: 34))
                      .animate().scale(duration: 600.ms, curve: Curves.easeOutBack),
                  const SizedBox(height: 18),
                  const Text('Welcome\nback 👋', style: TextStyle(fontSize: 38, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -1)).animate().fadeIn(delay: 150.ms).slideY(begin: 0.2, end: 0, curve: Curves.easeOutCubic),
                  const SizedBox(height: 8),
                  const Text('Sign in with your company account', style: TextStyle(color: C.muted)).animate().fadeIn(delay: 300.ms),
                ]),
              ),
            ),
          ),
        ),
        // white sheet
        AnimatedPadding(
          duration: const Duration(milliseconds: 200), padding: EdgeInsets.only(bottom: kb),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(color: Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(40)), boxShadow: [BoxShadow(color: C.ink.withValues(alpha: 0.08), blurRadius: 30, offset: const Offset(0, -8))]),
            child: SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kMaxWidth),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        child: formError == null ? const SizedBox(width: double.infinity) : Container(
                          margin: const EdgeInsets.only(bottom: 14), padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: const Color(0xFFFBE4E2), borderRadius: BorderRadius.circular(18)),
                          child: Row(children: [const Icon(Icons.error_outline, color: C.danger), const SizedBox(width: 10), Expanded(child: Text(formError!, style: const TextStyle(color: Color(0xFF8A2B27), fontWeight: FontWeight.w600)))]),
                        ).animate().shake(hz: 4, duration: 350.ms),
                      ),
                      TextField(
                        controller: id, textInputAction: TextInputAction.next, keyboardType: TextInputType.emailAddress, autocorrect: false, enableSuggestions: false,
                        autofillHints: const [AutofillHints.username], onSubmitted: (_) => _pwFocus.requestFocus(),
                        decoration: InputDecoration(hintText: 'Username or email', prefixIcon: const Icon(Icons.person_outline), errorText: idError),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: pw, focusNode: _pwFocus, obscureText: hide, textInputAction: TextInputAction.done, onSubmitted: (_) => _login(),
                        autofillHints: const [AutofillHints.password], enableSuggestions: false, autocorrect: false,
                        decoration: InputDecoration(
                          hintText: 'Password', prefixIcon: const Icon(Icons.lock_outline), errorText: pwError,
                          suffixIcon: IconButton(tooltip: hide ? 'Show password' : 'Hide password', icon: Icon(hide ? Icons.visibility_off_outlined : Icons.visibility_outlined), onPressed: () => setState(() => hide = !hide)),
                        ),
                      ),
                      const SizedBox(height: 22),
                      ActionButton(label: 'Sign in', icon: Icons.arrow_forward_rounded, onPressed: _login, loading: busy, dark: true),
                      const SizedBox(height: 14),
                      const Text('Forgot your password? Reset it in the company system.', textAlign: TextAlign.center, style: TextStyle(color: C.muted, fontSize: 12)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ).animate().slideY(begin: 0.3, end: 0, duration: 600.ms, curve: Curves.easeOutCubic).fadeIn(),
      ]),
    );
  }
}
