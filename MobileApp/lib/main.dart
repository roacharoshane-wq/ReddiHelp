import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/map_screen.dart';
import 'screens/login_screen.dart';
import 'screens/volunteer_shell.dart';
import 'screens/responder_shell.dart';
import 'screens/coordinator/coordinator_shell.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'services/sync_service.dart';
import 'services/notification_service.dart';
import 'services/tile_cache_service.dart';
import 'utils/parish_helper.dart';
import 'utils/accessibility_helper.dart';

final themeProvider = ThemeProvider();

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  runApp(const MyApp());
  WidgetsBinding.instance.addPostFrameCallback((_) {
    _initializeBackgroundServices();
  });
}

Future<void> _initializeBackgroundServices() async {
  await Future.wait([
    themeProvider.init(),
    AccessibilityHelper().init(),
    TileCacheService.init(),
    SyncService().init(),
    NotificationService().init(),
    ParishHelper().initialize(),
  ]);

  // NOTE: clearAll() and clearMockUsers() removed — they wiped user
  // accounts and sync queue on every debug restart, breaking non-victim logins.
  // Call them manually from a debug menu if you ever need to reset state.
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AccessibilityHelper _accessibilityHelper = AccessibilityHelper();

  @override
  void initState() {
    super.initState();
    _accessibilityHelper.addListener(_onThemeChanged);
    themeProvider.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _accessibilityHelper.removeListener(_onThemeChanged);
    themeProvider.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final effectiveTheme = _accessibilityHelper.enabled
        ? _accessibilityHelper.accessibleTheme
        : themeProvider.currentTheme;

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
            create: (_) => AuthProvider()..checkAuthStatus()),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: MaterialApp(
        title: 'ReddiHelp',
        debugShowCheckedModeBanner: false,
        theme: effectiveTheme,
        home: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            if (auth.isLoading) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (!auth.isAuthenticated) {
              return const LoginScreen();
            }

            final role = auth.userRole;

            switch (role) {
              case 'volunteer':
                return const VolunteerShell();
              case 'coordinator':
                return const CoordinatorShell();
              case 'responder':
                return const ResponderShell();
              case 'victim':
              default:
                return const MapScreen();
            }
          },
        ),
      ),
    );
  }
}
