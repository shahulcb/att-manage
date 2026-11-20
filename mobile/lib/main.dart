import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api.dart';
import 'screens/login.dart';
import 'screens/welcome.dart';
import 'screens/employee_shell.dart';
import 'screens/owner_shell.dart';
import 'theme.dart';

final navKey = GlobalKey<NavigatorState>();

Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      pageBuilder: (_, _, _) => page, transitionDuration: const Duration(milliseconds: 450),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
    );

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.dark, systemNavigationBarColor: Colors.transparent, systemNavigationBarIconBrightness: Brightness.dark,
  ));
  await Api.i.init();
  // a rejected/expired session sends the user to the login screen from anywhere in the app
  Api.i.onUnauthorized = (msg) => navKey.currentState?.pushAndRemoveUntil(fadeRoute(LoginScreen(message: msg)), (_) => false);
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});
  @override
  Widget build(BuildContext context) {
    final seen = Api.i.prefs.getBool('seen_welcome') ?? false;
    final home = Api.i.token != null
        ? (Api.i.role == 'owner' ? const OwnerShell() : const EmployeeShell())
        : (seen ? const LoginScreen() : const WelcomeScreen());
    return MaterialApp(
      title: 'Attendance', debugShowCheckedModeBanner: false, theme: buildTheme(), navigatorKey: navKey, home: home,
      // big system font sizes are respected up to a limit so layouts never break
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.25)), child: child!);
      },
    );
  }
}
