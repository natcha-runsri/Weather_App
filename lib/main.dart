import 'package:flutter/material.dart';
import 'weather.dart';

void main() {
  runApp(const WeatherApp());
}

class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFF0F6FF),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0284C7),
          secondary: Color(0xFF6366F1),
        ),
      ),
      home: const WeatherDashboard(),
    );
  }
}

