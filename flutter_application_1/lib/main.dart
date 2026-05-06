import 'package:flutter/material.dart';
import 'screens/map_screen.dart';
import 'screens/incidents_screen.dart';
import 'utils/parish_helper.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize parish helper (loads GeoJSON boundaries)
  await ParishHelper().initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Disaster Response',
      debugShowCheckedModeBanner: true,
      theme: ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const MapScreen(),
        '/incidents': (context) => const IncidentsScreen(),
      },
    );
  }
}
