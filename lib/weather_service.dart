import 'dart:convert';
import 'package:http/http.dart' as http;

class WeatherService  {
  /// ===== NETPIE API =====
  static const String controlUrl = 'https://api.netpie.io/v2/device/message?topic=weather/device_control';
  static const String shadowUrl = 'https://api.netpie.io/v2/device/shadow/data';

  /// ===== FIREBASE REALTIME DATABASE =====
  /// แก้ URL ตรงนี้ให้ตรงกับโปรเจกต์ของตัวเอง
  static const String firebaseUrl =
      'https://iotproject-dbc8b-default-rtdb.asia-southeast1.firebasedatabase.app/';

  /// ===== Mobile App Device =====
  static const String controlClientId = 'f5dac080-f4b4-4348-8324-216355396979';
  static const String controlToken = 'CaLnZA4Gv6SZZbi6d9iCEaQ5ievk1NpM';

  /// ===== ESP32 Device =====
  static const String statusClientId = '8c3c6eed-d17c-4125-b6e0-651c0a8c4e9a';
  static const String statusToken = 'PkPqGZXszdXFXU7i23r8iE8fyrtcX1b3';

  /// ===== Headers =====
  Map<String, String> get _controlHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Device $controlClientId:$controlToken',
      };

  Map<String, String> get _statusHeaders => {
        'Content-Type': 'application/json',
        'Authorization': 'Device $statusClientId:$statusToken',
      };

  Future<Map<String, dynamic>> getWeatherData() async {
    final response = await http.get(
      Uri.parse(shadowUrl),
      headers: _statusHeaders,
    );
    if (response.statusCode == 200) {
      final jsonData = json.decode(response.body);
      final data = jsonData['data'];

      return {

        "temperature": data["temperature"] ?? 0.0,
        "humidity": data["humidity"] ?? 0.0,
        "analogValue": data["analogValue"] ?? 0,
        "status": data["status"] ?? "normal",
        "windSpeed": data["windSpeed"] ?? 0.0,
        "windDeg":data["windDeg"] ?? 0,

        "red": data["red"] ?? 0,
        "blue": data["blue"] ?? 0,
        "green": data["green"] ?? 0,
        "buzzer": (data["buzzer"] ?? 0) == 1,
      };

    } else {
      throw Exception("Failed to load weather data");
    }
  }

  Future<void> setDeviceStatus(String device, bool isOn) async {
    final payload = json.encode({
      "data": {device: isOn ? 1 : 0}
    });
    final response = await http.put(
      Uri.parse(controlUrl),
      headers: _controlHeaders,
      body: payload,
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to send command");
    }
  }

  Future<void> setTemperature(double value) async {
    final payload = json.encode({
      "data": {
        "tem": value
      }
    });
    final response = await http.put(
      Uri.parse(controlUrl),
      headers: _controlHeaders,
      body: payload,
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to set temperature");
    }
  }


  Future<void> setHumidity(double value) async {
    final payload = json.encode({
      "data": {
        "hum": value
      }
    });
    final response = await http.put(
      Uri.parse(controlUrl),
      headers: _controlHeaders,
      body: payload,
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to set humidity");
    }
  }

  Future<void> setRain(int value) async {
    final payload = json.encode({
      "data": {
        "val": value
      }
    });
    final response = await http.put(
      Uri.parse(controlUrl),
      headers: _controlHeaders,
      body: payload,
    );
    if (response.statusCode != 200) {
      throw Exception("Failed to set rain");
    }
  }

  Future<void> setWeatherStatus(String status) async {

    final payload = json.encode({
      "status": status
    });

    final response = await http.put(
      Uri.parse(controlUrl),
      headers: _controlHeaders,
      body: payload,
    );

    if (response.statusCode != 200) {
      throw Exception("Failed to send weather command");
    }
  }

  // ─────────────────────────────────────────────
  // ดึงข้อมูลย้อนหลัง N วัน จาก Firebase
  // Firebase path: /sensorData  (ชื่อ node ที่เก็บ entries)
  // แต่ละ entry มี field: timestamp (String ISO8601),
  //   temperature, humidity, analogValue, windSpeed, windDeg, status
  //
  // คืนค่า: Map<String, _DaySummary>  key = "YYYY-MM-DD"
  // ─────────────────────────────────────────────
  Future<Map<String, DaySummary>> getHistoryData(int days) async {
    // สร้าง start timestamp = เที่ยงคืนของ (วันนี้ - days + 1 วัน) UTC+7
    final now = DateTime.now();
    final startDay = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    // Firebase Realtime DB: query orderBy timestamp, startAt
    final startStr =
        '${startDay.year}-${startDay.month.toString().padLeft(2, '0')}-${startDay.day.toString().padLeft(2, '0')}T00:00:00';

    final uri = Uri.parse(
      '$firebaseUrl/sensorData.json'
      '?orderBy="timestamp"'
      '&startAt="${Uri.encodeComponent(startStr)}"',
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Firebase HTTP error: ${response.statusCode}');
    }

    final raw = json.decode(response.body);
    if (raw == null) return {};

    // raw เป็น Map<entryKey, Map<field, value>>
    final entries = (raw as Map<String, dynamic>).values;

    // Group ตามวัน แล้วหา max/min/sum
    final Map<String, _DayAccumulator> acc = {};

    for (final e in entries) {
      if (e is! Map) continue;
      final ts = e['timestamp'] as String?;
      if (ts == null) continue;
      final dateKey = ts.substring(0, 10); // "YYYY-MM-DD"

      acc.putIfAbsent(dateKey, () => _DayAccumulator());
      acc[dateKey]!.add(
        temp: (e['temperature'] ?? 0).toDouble(),
        humid: (e['humidity'] ?? 0).toDouble(),
        rain: (e['analogValue'] ?? 0).toDouble(),
        wind: (e['windSpeed'] ?? 0).toDouble(),
      );
    }

    return acc.map((k, v) => MapEntry(k, v.toSummary(k)));
  }
}

// ── Helper classes (internal) ──

class _DayAccumulator {
  double tempMax = double.negativeInfinity;
  double tempMin = double.infinity;
  double humidSum = 0;
  double rainMax = 0;   // ใช้ค่า max analogValue เป็นตัวแทนฝนของวัน
  double windMax = 0;
  int count = 0;

  void add({
    required double temp,
    required double humid,
    required double rain,
    required double wind,
  }) {
    if (temp > tempMax) tempMax = temp;
    if (temp < tempMin) tempMin = temp;
    humidSum += humid;
    if (rain > rainMax) rainMax = rain;
    if (wind > windMax) windMax = wind;
    count++;
  }

  DaySummary toSummary(String dateKey) {
    final dt = DateTime.tryParse(dateKey) ?? DateTime.now();
    const thaiShort = ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];
    final dayName = thaiShort[dt.weekday - 1];
    final avgHumid = count > 0 ? humidSum / count : 0.0;

    String icon = '☀️';
    if (rainMax > 3000) icon = '🌧';
    else if (rainMax > 1500) icon = '🌦';
    else if (avgHumid > 75) icon = '🌤';

    return DaySummary(
      dateKey: dateKey,
      dayName: dayName,
      tempMax: tempMax == double.negativeInfinity ? 0 : tempMax,
      tempMin: tempMin == double.infinity ? 0 : tempMin,
      humid: double.parse(avgHumid.toStringAsFixed(1)),
      rain: rainMax,
      wind: windMax,
      icon: icon,
    );
  }
}

/// ข้อมูลสรุปรายวัน — ใช้ใน weather.dart ด้วย
class DaySummary {
  final String dateKey;
  final String dayName;
  final double tempMax;
  final double tempMin;
  final double humid;
  final double rain;
  final double wind;
  final String icon;

  DaySummary({
    required this.dateKey,
    required this.dayName,
    required this.tempMax,
    required this.tempMin,
    required this.humid,
    required this.rain,
    required this.wind,
    required this.icon,
  });

  /// fallback เมื่อยังไม่มีข้อมูลของวันนั้น
  factory DaySummary.empty(String dateKey) {
    final dt = DateTime.tryParse(dateKey) ?? DateTime.now();
    const thaiShort = ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];
    return DaySummary(
      dateKey: dateKey,
      dayName: thaiShort[dt.weekday - 1],
      tempMax: 0, tempMin: 0,
      humid: 0, rain: 0, wind: 0,
      icon: '—',
    );
  }
}