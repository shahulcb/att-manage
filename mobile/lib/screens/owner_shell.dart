import 'package:flutter/material.dart';
import '../api.dart';
import '../main.dart' show fadeRoute;
import '../widgets/shell_frame.dart';
import '../widgets/ui.dart';
import 'login.dart';
import 'owner_attendance.dart';
import 'owner_dashboard.dart';
import 'owner_employees.dart';
import 'owner_requests.dart';
import 'owner_settings.dart';

class OwnerShell extends StatefulWidget {
  const OwnerShell({super.key});
  @override
  State<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends State<OwnerShell> {
  final _refresh = ValueNotifier<int>(0); // bumped when the owner changes tab so lists reload

  Future<void> logout() async {
    await Api.i.logout();
    if (mounted) Navigator.pushAndRemoveUntil(context, fadeRoute(const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) => ShellFrame(
        onTab: (_) => _refresh.value++,
        items: const [NavItem(Icons.dashboard_rounded, 'Dashboard'), NavItem(Icons.fact_check_rounded, 'Attendance'), NavItem(Icons.inbox_rounded, 'Requests'), NavItem(Icons.groups_rounded, 'Employees'), NavItem(Icons.tune_rounded, 'Settings')],
        pagesBuilder: (goTo) => [
          OwnerDashboard(refresh: _refresh, onLogout: logout, goToRequests: () => goTo(2)),
          OwnerAttendance(refresh: _refresh),
          OwnerRequests(refresh: _refresh),
          OwnerEmployees(refresh: _refresh),
          const OwnerSettings(),
        ],
      );
}
