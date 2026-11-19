import 'package:flutter/material.dart';
import 'weather.dart';
import 'weather_service.dart';

void main() {
  final missing = WeatherService.missingConfig;
  if (missing.isNotEmpty) {
    runApp(_MissingConfigApp(missing));
    return;
  }
  runApp(const WeatherApp());
}

/// แสดงเมื่อไม่ได้ส่งค่า NETPIE ผ่าน --dart-define-from-file
class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp(this.missing);
  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'ยังไม่ได้ตั้งค่า: ${missing.join(', ')}\n\n'
              'คัดลอก dart_defines.example.json เป็น dart_defines.json ใส่ค่าจริง\n'
              'แล้วรันด้วย flutter run --dart-define-from-file=dart_defines.json',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
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

