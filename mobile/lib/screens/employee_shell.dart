import 'package:flutter/material.dart';
import '../api.dart';
import '../main.dart' show fadeRoute;
import '../widgets/shell_frame.dart';
import '../widgets/ui.dart';
import 'employee_history.dart';
import 'employee_home.dart';
import 'employee_leave.dart';
import 'login.dart';

class EmployeeShell extends StatelessWidget {
  const EmployeeShell({super.key});

  Future<void> _logout(BuildContext context) async {
    await Api.i.logout();
    if (context.mounted) Navigator.pushAndRemoveUntil(context, fadeRoute(const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) => ShellFrame(
        items: const [NavItem(Icons.home_rounded, 'Home'), NavItem(Icons.calendar_month_rounded, 'Calendar'), NavItem(Icons.bar_chart_rounded, 'Statistics'), NavItem(Icons.beach_access_rounded, 'Leave')],
        pagesBuilder: (goTo) => [
          EmployeeHome(onLogout: () => _logout(context), goTo: goTo),
          const EmployeeHistory(mode: HistoryMode.calendar),
          const EmployeeHistory(mode: HistoryMode.chart),
          const EmployeeLeave(),
        ],
      );
}
