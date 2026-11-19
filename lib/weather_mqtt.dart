import 'dart:async';
import 'package:flutter/material.dart';
import 'weather_service.dart';
import 'mqtt_service.dart';

class WeatherDashboard extends StatefulWidget {
  const WeatherDashboard({super.key});

  @override
  State<WeatherDashboard> createState() => _WeatherDashboardState();
}
class _WeatherDashboardState extends State<WeatherDashboard> {

  final WeatherService _service = WeatherService();
  late MqttService _mqtt;
  /// NETPIE Mobile Credential
  final String mobileClientId = '11555b0d-d6a1-463e-a4b7-4ffcb23580e8';
  /// อ่านจาก --dart-define-from-file=dart_defines.json (ใช้ token เดียวกับ controlToken)
  final String mobileToken = WeatherService.controlToken;
  final String mobileSecret = const String.fromEnvironment('NETPIE_MOBILE_SECRET');

  /// Device
  bool red = false;
  bool blue = false;
  bool green = false;
  bool buzzer = false;

  /// Sensor
  double temperature = 0;
  double humidity = 0;
  int analogValue = 0;
  String status = "normal";

  @override
  void initState() {
    super.initState();

    /// MQTT realtime
    _mqtt = MqttService(
      clientId: mobileClientId,
      token: mobileToken,
      secret: mobileSecret,

      onStatusChanged: (status) {
        setState(() {
          red = status['red'] ?? false;
          blue = status['blue'] ?? false;
          green = status['green'] ?? false;
          buzzer = status['buzzer'] ?? false;
        });
      },
    );

    if (mobileToken.isEmpty || mobileSecret.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          duration: Duration(days: 1),
          content: Text(
              'ยังไม่ได้ตั้งค่า NETPIE_CONTROL_TOKEN / NETPIE_MOBILE_SECRET — '
              'รันด้วย --dart-define-from-file=dart_defines.json'),
        ));
      });
    } else {
      _mqtt.connect();
    }

    /// load sensor
    loadWeather();

    /// refresh sensor every 5 sec
    Timer.periodic(
      const Duration(seconds: 5),
      (timer) => loadWeather(),
    );
  }

  Future<void> loadWeather() async {

    try {

      final data = await _service.getWeatherData();

      setState(() {
        temperature = data["temperature"];
        humidity = data["humidity"];
        analogValue = data["analogValue"];
        status = data["status"];
      });

    } catch (e) {
      debugPrint("Weather error: $e");
    }

  }

  @override
  void dispose() {
    _mqtt.disconnect();
    super.dispose();
  }

  /// toggle device
  void _toggleDevice(String device, bool value) async {

    setState(() {
      if (device == 'red') red = value;
      if (device == 'blue') blue = value;
      if (device == 'green') green = value;
      if (device == 'buzzer') buzzer = value;
    });

    await _service.setDeviceStatus(device, value);

  }

  Widget _buildSwitch(String title, bool value, String device) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [

        Text(
          title,
          style: const TextStyle(fontSize: 18),
        ),

        Switch(
          value: value,
          onChanged: (val) => _toggleDevice(device, val),
        ),

      ],
    );
  }

  Widget _sensorCard(String title, String value, IconData icon) {

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [

            Icon(icon,size:30),

            const SizedBox(height:5),

            Text(
              value,
              style: const TextStyle(
                fontSize:18,
                fontWeight: FontWeight.bold,
              ),
            ),

            Text(title),

          ],
        ),
      ),
    );

  }

  @override
  Widget build(BuildContext context) {

    Color alertColor = Colors.green;

    if (status == "Heavy Rain") {
      alertColor = Colors.red;
    }
    else if (status == "Drizzle") {
      alertColor = Colors.orange;
    }

    return Scaffold(

      appBar: AppBar(
        title: const Text("IoT Weather Dashboard"),
        backgroundColor: Colors.deepPurple,
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),

        child: Column(

          children: [

            /// SENSOR GRID
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,

              children: [

                _sensorCard(
                  "Temperature",
                  "${temperature.toStringAsFixed(1)} °C",
                  Icons.thermostat,
                ),

                _sensorCard(
                  "Humidity",
                  "${humidity.toStringAsFixed(1)} %",
                  Icons.water_drop,
                ),

                _sensorCard(
                  "Rain",
                  "$analogValue",
                  Icons.cloud,
                ),

                _sensorCard(
                  "Status",
                  status,
                  Icons.warning,
                ),

              ],
            ),

            const SizedBox(height:20),

            /// ALERT
            Container(
              padding: const EdgeInsets.all(12),

              decoration: BoxDecoration(
                color: alertColor,
                borderRadius: BorderRadius.circular(10),
              ),

              child: Text(

                status == "Heavy Rain"
                    ? "Heavy Rain Alert"
                    : status == "Drizzle"
                        ? "Rain Warning"
                        : "Weather Normal",

                style: const TextStyle(
                  color: Colors.white,
                  fontSize:16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height:30),

            /// DEVICE CONTROL
            const Text(
              "Device Control",
              style: TextStyle(
                fontSize:20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height:10),

            _buildSwitch("🔴 Red LED", red, 'red'),
            _buildSwitch("🟢 Green LED", green, 'green'),
            _buildSwitch("🔵 Blue LED", blue, 'blue'),
            _buildSwitch("🔔 Buzzer", buzzer, 'buzzer'),

          ],
        ),
      ),
    );
  }
}