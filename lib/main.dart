import 'package:flutter/material.dart';
import 'package:hospi_id_scanner/screens/splash_wrapper.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Check-in LOUNA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      home: SplashWrapper(), // ← ici on met la landing page
    );
  }
}
