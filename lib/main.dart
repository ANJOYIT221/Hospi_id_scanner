import 'package:flutter/material.dart';
import 'package:hospi_id_scanner/screens/splash_wrapper.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hospi_id_scanner/services/crash_logger_service.dart';

Future<void> main() async {
  await dotenv.load(fileName: ".env");
  await CrashLoggerService().initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Check-in HospiSmart',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: SplashWrapper(), // ← ici on met la landing page
    );
  }
}
