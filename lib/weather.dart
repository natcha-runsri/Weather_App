import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'weather_service.dart';

// ข้อมูลสภาพอากาศปัจจุบันค้าบเตง
class WeatherState {
  double rain;
  double rainAcc;
  double temp;
  double feel;
  double humid;
  double dew;
  double wind;
  double windDeg;
  String windDir;
  double heatIndex;

  WeatherState({
    this.rain = 12.4,
    this.rainAcc = 38.2,
    this.temp = 32.5,
    this.feel = 36.8,
    this.humid = 78,
    this.dew = 25.3,
    this.wind = 18,
    this.windDeg = 45,
    this.windDir = 'NE',
    this.heatIndex = 36.8,
  });
}

double rainMmFromAnalog(double analog) =>
    ((4095 - analog) / 4095 * 30).clamp(0.0, 30.0);

// ── หน้าDashboard ──
class WeatherDashboard extends StatefulWidget {
  const WeatherDashboard({super.key});

  @override
  State<WeatherDashboard> createState() => _WeatherDashboardState();
}

class _WeatherDashboardState extends State<WeatherDashboard> {
  final WeatherService _weatherService = WeatherService();
   bool _notificationsEnabled = false;
  bool isAutoMode = true;
  bool showAlert = false;
  String alertText = '';
  String chartType = 'temp';
  Timer? _timer;
  Timer? _clockTimer;
  final WeatherState _state = WeatherState();
  DateTime _lastUpdate = DateTime.now();
  DateTime _now = DateTime.now();

  // ── ข้อมูลย้อนหลัง 7 วัน จาก Firebase ──
  List<DaySummary> _historyDays = [];
  bool _historyLoading = true;
  String? _historyError;
   

  // อันนี้ปุ่มที่ให้เลือกแสดงค่าในแมนนวล
  final Map<String, bool> _visible = {
    'rain': true,
    'temp': true,
    'humid': true,
    'wind': true,
    'heatindex': true,
    'history': true,
  };

  final List<String> _dirs = [
    'เหนือ',
    'ตะวันออกเฉียงเหนือ',
    'ตะวันออก',
    'ตะวันออกเฉียงใต้',
    'ใต้',
    'ตะวันตกเฉียงใต้',
    'ตะวันตก',
    'ตะวันตกเฉียงเหนือ',
  ];

  @override
  void initState() {
    super.initState();

    _tick();
    _loadHistory();

    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());

    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    final data = await _weatherService.getWeatherData();
    setState(() {
      _state.temp = (data["temperature"] ?? 0).toDouble();
      _state.humid = (data["humidity"] ?? 0).toDouble();
      _state.wind = (data["windSpeed"] ?? 0).toDouble();
      _state.windDeg = (data["windDeg"] ?? 0).toDouble();
      _state.rain = (data["analogValue"] ?? 0).toDouble();

      // คำนวณ Heat Index จากอุณหภูมิและความชื้นปัจจุบัน
      _state.heatIndex = _calcHeatIndex(_state.temp, _state.humid);
      _lastUpdate = DateTime.now();

      // แสดง alert เฉพาะเมื่อเปิดการแจ้งเตือนไว้
      if (!_notificationsEnabled) {
        showAlert = false;
      }
    });
  }

  bool buzzer = false;
  bool _isLoading = true;

  Future<void> _loadBuzzerStatus() async {
    try {
      final status = await _weatherService.getWeatherData();

      setState(() {
        buzzer = status['buzzer'] ?? false;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }



  void _toggleNotifications() {
    setState(() {
      _notificationsEnabled = !_notificationsEnabled;
    });

    // ถ้าต้องการส่งไป ESP32 / NETPIE
   _weatherService.setDeviceStatus("buzzer", _notificationsEnabled);
  }

  void _setMode(bool auto) async {
    setState(() {
      isAutoMode = auto;
      showAlert = false;
    });

    /// ปิด buzzer
    if (!auto) {
      await _weatherService.setDeviceStatus("buzzer", false);
    }
  }

  // ── โหลดข้อมูลย้อนหลัง 7 วันจาก Firebase ──
  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final raw = await _weatherService.getHistoryData(7);

      // สร้าง list 7 วัน เรียงจากเก่า → ใหม่
      final List<DaySummary> result = [];
      for (int i = 6; i >= 0; i--) {
        final date = DateTime.now().subtract(Duration(days: i));
        final key =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        result.add(raw[key] ?? DaySummary.empty(key));
      }

      setState(() {
        _historyDays = result;
        _historyLoading = false;
      });
    } catch (e) {
      setState(() {
        _historyError = e.toString();
        _historyLoading = false;
        // fallback: เติม empty 7 วัน เพื่อ UI ไม่พัง
        _historyDays = List.generate(7, (i) {
          final date = DateTime.now().subtract(Duration(days: 6 - i));
          final key =
              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
          return DaySummary.empty(key);
        });
      });
    }
  }

  /// ดึง List<double> ตาม chartType จาก _historyDays
  List<double> _historyValues(String type) {
    if (_historyDays.isEmpty) return List.filled(7, 0.0);
    switch (type) {
      case 'temperature':
        return _historyDays.map((d) => d.tempMax).toList();
      case 'humidity':
        return _historyDays.map((d) => d.humid).toList();
      case 'rain':
        return _historyDays.map((d) => rainMmFromAnalog(d.rain)).toList();
      case 'wind':
        return _historyDays.map((d) => d.wind).toList();
      default:
        return _historyDays.map((d) => d.tempMax).toList();
    }
  }

  List<String> get _historyLabels =>
      _historyDays.isEmpty
          ? List.filled(7, '—')
          : _historyDays.map((d) => d.dayName).toList();

  // ── DateTime helpers ──
  static const List<String> _thaiDays = [
    'วันจันทร์',
    'วันอังคาร',
    'วันพุธ',
    'วันพฤหัสบดี',
    'วันศุกร์',
    'วันเสาร์',
    'วันอาทิตย์',
  ];
  static const List<String> _thaiMonths = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];

  String get _dateString {
    final d = _now;
    final dayName = _thaiDays[d.weekday - 1];
    final month = _thaiMonths[d.month - 1];
    final year = d.year + 543; // พ.ศ.
    return '$dayName ${d.day} $month $year';
  }

  String get _timeString {
    final d = _now;
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    final s = d.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  // ── Heat Index helpers ──
  Color _hiColor() {
    final hi = _state.heatIndex;
    if (hi < 32) return const Color(0xFF059669);
    if (hi < 41) return const Color(0xFFFBBF24);
    if (hi < 54) return const Color(0xFFF87171);
    return const Color(0xFFFCA5A5);
  }

  String _hiLabel() {
    final hi = _state.heatIndex;
    if (hi < 32) return '✅ ปกติ';
    if (hi < 41) return '⚠ ระวัง';
    if (hi < 54) return '🔴 อันตราย';
    return '💀 อันตรายมาก';
  }

  String _hiDesc() {
    final hi = _state.heatIndex;
    if (hi < 32) return 'อุณหภูมิและความชื้นอยู่ในระดับปกติ สบายตัว';
    if (hi < 41)
      return 'อาจรู้สึกร้อนมากและเหนื่อยล้าได้ง่าย ควรดื่มน้ำสม่ำเสมอ';
    if (hi < 54) return 'ความเสี่ยงสูง ควรหลีกเลี่ยงกิจกรรมกลางแจ้ง';
    return 'อันตรายถึงชีวิต! หลีกเลี่ยงการอยู่กลางแจ้งโดยเด็ดขาด';
  }

  double _hiPercent() => ((_state.heatIndex - 27) / (60 - 27)).clamp(0.0, 1.0);

  /// คำนวณ Heat Index จากอุณหภูมิ (°C) และความชื้น (%) — Rothfusz regression
  double _calcHeatIndex(double tempC, double rh) {
    final t = tempC * 9 / 5 + 32; // แปลงเป็น °F
    if (t < 80 || rh < 40) {
      // ถ้าอุณหภูมิต่ำหรือความชื้นน้อย ใช้สูตรง่าย
      final hiF = 0.5 * (t + 61.0 + (t - 68.0) * 1.2 + rh * 0.094);
      return (hiF - 32) * 5 / 9;
    }
    // Rothfusz full regression
    double hi =
        -42.379 + //ค่าพื้นฐานของสมการ
        2.04901523 *
            t + //ค่าคงที่ 2.04901523 เป็นตัวกำหนดความแรงของผลกระทบจากอุณหภูมิ เมื่ออุณหภูมิสูงขึ้น
        10.14333127 * rh - //ความชื้นสูงทำให้จึงทำให้ Heat Index เพิ่มขึ้น
        0.22475541 * t * rh - //ปฏิสัมพันธ์ระหว่างอุณหภูมิและความชื้น
        0.00683783 * t * t - //ผลของอุณหภูมิยกกำลังสอง
        0.05481717 * rh * rh + //ผลของความชื้นยกกำลังสอง
        0.00122874 * t * t * rh + //อุณหภูมิกำลังสอง × ความชื้น
        0.00085282 * t * rh * rh - //ใช้เพิ่มผลกระทบของ ความชื้นสูงมาก
        0.00000199 *
            t *
            t *
            rh *
            rh; //เป็นตัวปรับขั้นสุดท้ายของสมการเพื่อให้ค่าที่คำนวณได้ ใกล้กับข้อมูลทดลองจริงที่สุด
    // adjustment for low humidity
    if (rh < 13 && t >= 80 && t <= 112) {
      hi -= (13 - rh) / 4 * sqrt((17 - (t - 95).abs()) / 17);
    }
    // adjustment for high humidity
    if (rh > 85 && t >= 80 && t <= 87) {
      hi += (rh - 85) / 10 * ((87 - t) / 5);
    }
    return (hi - 32) * 5 / 9; // แปลงกลับ °C
  }

  @override
  Widget build(BuildContext context) {
    final screenW = MediaQuery.of(context).size.width;
    final pad = screenW < 360 ? 10.0 : 16.0;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 12),
              if (showAlert && isAutoMode && _notificationsEnabled)
                _buildAlertBanner(),
              if (!isAutoMode) _buildManualSelector(),
              const SizedBox(height: 12),
              _buildSensorGrid(),
              if (_visible['heatindex']!) ...[
                const SizedBox(height: 12),
                _buildHeatIndex(),
              ],
              if (_visible['history']!) ...[
                const SizedBox(height: 12),
                _buildHistory(),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── Header ──
  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final s = (w / 420).clamp(0.68, 1.0);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 38 * s,
              height: 38 * s,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(9 * s),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.35),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Center(
                child: Text('🌦', style: TextStyle(fontSize: 17 * s)),
              ),
            ),
            SizedBox(width: 8 * s),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ชื่อแอป
                  Text(
                    'WEATHER MONITOR',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: (13 * s).clamp(9.5, 13.0),
                      color: const Color(0xFF0284C7),
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // ชื่อสถานี
                  Text(
                    'สถานีตรวจวัดอากาศ · นครปฐม',
                    style: TextStyle(
                      fontSize: (10.5 * s).clamp(8.0, 11.0),
                      color: const Color(0xFF6366F1),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 3 * s),
                  // วันที่ + เวลา
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '📅',
                        style: TextStyle(fontSize: (9 * s).clamp(7.0, 10.0)),
                      ),
                      SizedBox(width: 3 * s),
                      Flexible(
                        child: Text(
                          _dateString,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: (8.5 * s).clamp(6.5, 9.0),
                            color: const Color(0xFF6366F1),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 8 * s),
                      Text(
                        '🕐',
                        style: TextStyle(fontSize: (9 * s).clamp(7.0, 10.0)),
                      ),
                      SizedBox(width: 3 * s),
                      Text(
                        _timeString,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: (9.5 * s).clamp(7.5, 10.0),
                          color: const Color(0xFF0284C7),
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 8 * s),

            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // LIVE badge
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: (7 * s).clamp(5.0, 8.0),
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withValues(alpha: 0.1),
                    border: Border.all(
                      color: const Color(0xFF059669).withValues(alpha: 0.35),
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LiveDot(),
                      SizedBox(width: 3 * s),
                      Text(
                        'LIVE',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: (9 * s).clamp(7.0, 9.0),
                          color: const Color(0xFF059669),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 6 * s),
                // AUTO / MANUAL toggle
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    border: Border.all(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                    ),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  padding: const EdgeInsets.all(3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _modeBtn('AUTO', isAutoMode, () => _setMode(true), s),
                      _modeBtn('MANUAL', !isAutoMode, () => _setMode(false), s),
                    ],
                  ),
                ),
                SizedBox(width: 6 * s),
                // Notification toggle
                Tooltip(
                  message:
                      _notificationsEnabled
                          ? 'ปิดการแจ้งเตือน'
                          : 'เปิดการแจ้งเตือน',
                  child: GestureDetector(
                    onTap: _toggleNotifications,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 34 * s,
                          height: 34 * s,
                          decoration: BoxDecoration(
                            color:
                                _notificationsEnabled
                                    ? const Color(0xFFFBBF24).withOpacity(0.15)
                                    : const Color(0xFF94A3B8).withOpacity(0.1),
                            border: Border.all(
                              color:
                                  _notificationsEnabled
                                      ? const Color(0xFFFBBF24).withOpacity(0.6)
                                      : const Color(
                                        0xFF94A3B8,
                                      ).withOpacity(0.3),
                            ),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Center(
                            child: Text(
                              _notificationsEnabled ? '🔔' : '🔕',
                              style: TextStyle(
                                fontSize: (15 * s).clamp(12.0, 17.0),
                              ),
                            ),
                          ),
                        ),

                        SizedBox(height: 2 * s),

                        Text(
                          _notificationsEnabled ? 'แจ้งเตือน' : 'ปิดเสียง',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: (7.5 * s).clamp(6.0, 8.0),
                            color:
                                _notificationsEnabled
                                    ? const Color(0xFFF59E0B)
                                    : const Color(0xFF94A3B8),
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _modeBtn(
    String label,
    bool active,
    VoidCallback onTap, [
    double s = 1.0,
  ]) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: (12 * s).clamp(8.0, 14.0),
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF0284C7) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow:
              active
                  ? [
                    BoxShadow(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ]
                  : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: (10 * s).clamp(8.0, 11.0),
            fontWeight: FontWeight.bold,
            color: active ? const Color(0xFFF0F6FF) : const Color(0xFF64748B),
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  // ── Alert Banner ──
  Widget _buildAlertBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x1FFBBF24), Color(0x0FF87171)],
        ),
        border: Border.all(
          color: const Color(0xFFFBBF24).withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Text('⚠️', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'Sarabun',
                  color: Color(0xFF1E293B),
                ),
                children: [
                  const TextSpan(
                    text: 'แจ้งเตือนฝน: ',
                    style: TextStyle(
                      color: Color(0xFFFBBF24),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(text: alertText),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => showAlert = false),
            child: const Text(
              '✕',
              style: TextStyle(fontSize: 16, color: Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Manual Selector ──
  Widget _buildManualSelector() {
    final labels = {
      'rain': '🌧 ฝน',
      'temp': '🌡 อุณหภูมิ',
      'humid': '💧 ความชื้น',
      'wind': '🌬 ลม',
      'heatindex': '🔥 Heat Index',
      'history': '📊 ย้อนหลัง',
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        border: Border.all(
          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'แสดงค่า:',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: Color(0xFF64748B),
              letterSpacing: 1.5,
            ),
          ),
          ...labels.entries.map((e) {
            final isOn = _visible[e.key] ?? true;
            return GestureDetector(
              onTap: () => setState(() => _visible[e.key] = !isOn),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color:
                      isOn
                          ? const Color(0xFF0284C7).withValues(alpha: 0.12)
                          : Colors.transparent,
                  border: Border.all(
                    color:
                        isOn
                            ? const Color(0xFF0284C7)
                            : const Color(0xFF0284C7).withValues(alpha: 0.15),
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        isOn
                            ? const Color(0xFF0284C7)
                            : const Color(0xFF64748B),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Sensor Grid ──
  Widget _buildSensorGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w < 360 ? 1 : (w < 600 ? 2 : 4);
        final ratio = w < 360 ? 2.2 : (w < 600 ? 1.05 : 0.95);
        final cards = <Widget>[];
        if (_visible['rain']!) cards.add(_buildRainCard());
        if (_visible['temp']!) cards.add(_buildTempCard());
        if (_visible['humid']!) cards.add(_buildHumidCard());
        if (_visible['wind']!) cards.add(_buildWindCard());
        if (cards.isEmpty) return const SizedBox();
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: ratio,
          children: cards,
        );
      },
    );
  }

  Widget _sensorCard({
    required String label,
    required String icon,
    required String value,
    required String unit,
    required Widget sub,
    required Color accentColor,
    required Gradient topBorder,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardW = constraints.maxWidth;
        final valueFontSize = cardW < 140 ? 22.0 : (cardW < 180 ? 26.0 : 30.0);
        final labelFontSize = cardW < 140 ? 8.0 : 9.0;
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFF0284C7).withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0284C7).withValues(alpha: 0.07),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: topBorder,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(14),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  cardW < 140 ? 10 : 16,
                  18,
                  cardW < 140 ? 10 : 16,
                  14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: labelFontSize,
                              color: const Color(0xFF64748B),
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        Text(icon, style: const TextStyle(fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: valueFontSize,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                        height: 1,
                      ),
                    ),
                    Text(
                      unit,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const Spacer(),
                    sub,
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRainCard() => _sensorCard(
    label: 'ปริมาณฝน',
    icon: '🌧',
    value: _state.rain.toStringAsFixed(1),
    unit: 'Sensor Value',
    accentColor: const Color(0xFF0284C7),
    topBorder: const LinearGradient(
      colors: [Color(0xFF0284C7), Color(0xFF6366F1)],
    ),
    sub: Wrap(
      children: [
        Text(
          'สะสม: ${_state.rainAcc.toStringAsFixed(1)} มม.',
          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
        ),
      ],
    ),
  );

  Widget _buildTempCard() => _sensorCard(
    label: 'อุณหภูมิ',
    icon: '🌡',
    value: _state.temp.toStringAsFixed(1),
    unit: '°C',
    accentColor: const Color(0xFFF87171),
    topBorder: const LinearGradient(
      colors: [Color(0xFFF87171), Color(0xFFFBBF24)],
    ),
    sub: Text(
      'รู้สึกเหมือน ${_state.feel.toStringAsFixed(1)}°C',
      style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
    ),
  );

  Widget _buildHumidCard() => _sensorCard(
    label: 'ความชื้นสัมพัทธ์',
    icon: '💧',
    value: _state.humid.toStringAsFixed(0),
    unit: '%',
    accentColor: const Color(0xFF059669),
    topBorder: const LinearGradient(
      colors: [Color(0xFF059669), Color(0xFF0284C7)],
    ),
    sub: Text(
      'น้ำค้าง ${_state.dew.toStringAsFixed(1)}°C',
      style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
    ),
  );

  Widget _buildWindCard() {
    return _sensorCard(
      label: 'ความเร็วลม',
      icon: '🌬',
      value: _state.wind.toStringAsFixed(0),
      unit: 'กม./ชม.',
      accentColor: const Color(0xFF6366F1),
      topBorder: const LinearGradient(
        colors: [Color(0xFF6366F1), Color(0xFF0284C7)],
      ),
      sub: LayoutBuilder(
        builder: (context, constraints) {
          final short = constraints.maxWidth < 120;
          return Row(
            children: [
              _CompassWidget(degrees: _state.windDeg),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  short
                      ? _state.windDir.substring(
                        0,
                        _state.windDir.length > 6 ? 6 : _state.windDir.length,
                      )
                      : 'ทิศ${_state.windDir}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6366F1),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Heat Index ──
  Widget _buildHeatIndex() {
    final hiPct = _hiPercent();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 4,
            children: [
              const Text(
                '🔥 ดัชนีความร้อน (Heat Index)',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  letterSpacing: 1,
                ),
              ),
              Text(
                'อัพเดต ${_lastUpdate.hour.toString().padLeft(2, '0')}:${_lastUpdate.minute.toString().padLeft(2, '0')}:${_lastUpdate.second.toString().padLeft(2, '0')}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                _state.heatIndex.toStringAsFixed(1),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: _hiColor(),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _hiColor().withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _hiLabel(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _hiColor(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _hiDesc(),
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          // Bar
          LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF059669),
                          Color(0xFFA3E635),
                          Color(0xFFFBBF24),
                          Color(0xFFF97316),
                          Color(0xFFF87171),
                          Color(0xFFDC2626),
                        ],
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.elasticOut,
                    left: (barWidth * hiPct - 9).clamp(0.0, barWidth - 18),
                    top: -4,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFF0F6FF),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _hiColor().withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '27°',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  color: Color(0xFF64748B),
                ),
              ),
              Text(
                '32°',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  color: Color(0xFF64748B),
                ),
              ),
              Text(
                '41°',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  color: Color(0xFF64748B),
                ),
              ),
              Text(
                '54°',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  color: Color(0xFF64748B),
                ),
              ),
              Text(
                '60°+',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 7-Day History ──
  Widget _buildHistory() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF0284C7).withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '📊 ข้อมูลย้อนหลัง 7 วัน',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  letterSpacing: 1,
                ),
              ),
              // ปุ่ม Refresh
              GestureDetector(
                onTap: _loadHistory,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _historyLoading ? '⏳' : '↻',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        _historyLoading ? 'กำลังโหลด...' : 'รีเฟรช',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 9,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Error banner ──
          if (_historyError != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFF87171).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Text('⚠️', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'โหลดข้อมูลไม่สำเร็จ — ตรวจสอบ Firebase URL',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFDC2626),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 8),
          _buildChartTabs(),
          const SizedBox(height: 12),

          // ── Chart ──
          _historyLoading
              ? const SizedBox(
                height: 160,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF0284C7),
                  ),
                ),
              )
              : SizedBox(
                height: 160,
                child: _LineChart(
                  data: _historyValues(chartType),
                  labels: _historyLabels,
                  color: _chartColor(),
                ),
              ),

          const SizedBox(height: 16),

          // ── Day Cards ──
          _historyLoading ? _buildDayTableSkeleton() : _buildDayTable(),
        ],
      ),
    );
  }

  Color _chartColor() {
    switch (chartType) {
      case 'temp':
        return const Color(0xFFF87171);
      case 'humid':
        return const Color(0xFF059669);
      case 'rain':
        return const Color(0xFF0284C7);
      case 'wind':
        return const Color(0xFF6366F1);
      default:
        return const Color(0xFF0284C7);
    }
  }

  Widget _buildChartTabs() {
    final tabs = {
      'temp': 'อุณหภูมิ',
      'humid': 'ความชื้น',
      'rain': 'ฝน',
      'wind': 'ลม',
    };
    return Wrap(
      spacing: 4,
      children:
          tabs.entries.map((e) {
            final isActive = chartType == e.key;
            return GestureDetector(
              onTap: () => setState(() => chartType = e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color:
                      isActive
                          ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                          : Colors.transparent,
                  border: Border.all(
                    color:
                        isActive
                            ? const Color(0xFF0284C7)
                            : const Color(0xFF0284C7).withValues(alpha: 0.15),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color:
                        isActive
                            ? const Color(0xFF0284C7)
                            : const Color(0xFF64748B),
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }

  // ── Skeleton loader สำหรับ day cards ──
  Widget _buildDayTableSkeleton() {
    return Row(
      children: List.generate(
        7,
        (_) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFEDF4FF),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDayTable() {
    if (_historyDays.isEmpty) return _buildDayTableSkeleton();

    final rainValues =
        _historyDays.map((d) => rainMmFromAnalog(d.rain)).toList();
    final maxRain = rainValues.reduce((a, b) => a > b ? a : b);
    final safeMaxRain = maxRain > 0 ? maxRain : 1.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellW = (constraints.maxWidth - 6 * 4) / 7;
        final tiny = cellW < 38;
        return Row(
          children: List.generate(7, (i) {
            final day = _historyDays[i];
            final isToday = i == 6;
            final rainMm = rainValues[i];
            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: EdgeInsets.symmetric(
                  vertical: tiny ? 5 : 8,
                  horizontal: tiny ? 2 : 4,
                ),
                decoration: BoxDecoration(
                  color:
                      isToday
                          ? const Color(0xFF0284C7).withValues(alpha: 0.07)
                          : const Color(0xFFEDF4FF),
                  border: Border.all(
                    color:
                        isToday
                            ? const Color(0xFF0284C7)
                            : const Color(0xFF0284C7).withValues(alpha: 0.1),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    // ชื่อวัน
                    Text(
                      day.dayName,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: tiny ? 7 : 9,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    SizedBox(height: tiny ? 2 : 4),
                    // ไอคอนสภาพอากาศ
                    Text(day.icon, style: TextStyle(fontSize: tiny ? 10 : 14)),
                    SizedBox(height: tiny ? 2 : 4),
                    // อุณหภูมิสูงสุด
                    Text(
                      day.tempMax > 0
                          ? '${day.tempMax.toStringAsFixed(1)}°'
                          : '—',
                      style: TextStyle(
                        fontSize: tiny ? 7 : 9,
                        color: const Color(0xFFF87171),
                        fontFamily: 'monospace',
                      ),
                    ),
                    // อุณหภูมิต่ำสุด
                    Text(
                      day.tempMin > 0
                          ? '${day.tempMin.toStringAsFixed(1)}°'
                          : '—',
                      style: TextStyle(
                        fontSize: tiny ? 7 : 9,
                        color: const Color(0xFF0284C7),
                        fontFamily: 'monospace',
                      ),
                    ),
                    SizedBox(height: tiny ? 2 : 4),
                    // Progress bar ฝน
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEDF4FF),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (rainMm / safeMaxRain).clamp(0.0, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0284C7), Color(0xFF6366F1)],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: tiny ? 2 : 3),
                    // ปริมาณฝน mm
                    Text(
                      rainMm > 0 ? rainMm.toStringAsFixed(1) : '0',
                      style: TextStyle(
                        fontSize: tiny ? 6 : 8,
                        color: const Color(0xFF64748B),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Live Dot Widget ──
class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 7,
        height: 7,
        decoration: const BoxDecoration(
          color: Color(0xFF059669),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ── Compass Widget ──
class _CompassWidget extends StatelessWidget {
  final double degrees;
  const _CompassWidget({required this.degrees});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF0284C7).withValues(alpha: 0.25),
        ),
      ),
      child: Center(
        child: Transform.rotate(
          angle: degrees * pi / 180,
          child: CustomPaint(
            size: const Size(16, 16),
            painter: _NeedlePainter(),
          ),
        ),
      ),
    );
  }
}

class _NeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;
    final paintN =
        Paint()
          ..color = const Color(0xFFF87171)
          ..style = PaintingStyle.fill;
    final paintS =
        Paint()
          ..color = const Color(0xFF64748B)
          ..style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(cx, 0)
        ..lineTo(cx - 3, cy)
        ..lineTo(cx + 3, cy)
        ..close(),
      paintN,
    );
    canvas.drawPath(
      Path()
        ..moveTo(cx, size.height)
        ..lineTo(cx - 3, cy)
        ..lineTo(cx + 3, cy)
        ..close(),
      paintS,
    );
  }

  @override
  bool shouldRepaint(_NeedlePainter old) => false;
}

// ── Line Chart ──
class _LineChart extends StatelessWidget {
  final List<double> data;
  final List<String> labels;
  final Color color;
  const _LineChart({
    required this.data,
    required this.labels,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _LineChartPainter(data: data, labels: labels, color: color),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> data;
  final List<String> labels;
  final Color color;
  _LineChartPainter({
    required this.data,
    required this.labels,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final padX = 20.0, padY = 24.0;
    final iW = size.width - padX * 2;
    final iH = size.height - padY * 2 - 20;
    final minV = data.reduce(min) * 0.9;
    final maxV = data.reduce(max) * 1.1;

    final pts =
        data.asMap().entries.map((e) {
          final x = padX + e.key * (iW / (data.length - 1));
          final y = padY + iH - (e.value - minV) / (maxV - minV) * iH;
          return Offset(x, y);
        }).toList();

    // Grid
    final gridPaint =
        Paint()
          ..color = const Color(0xFF1E293B).withValues(alpha: 0.1)
          ..strokeWidth = 1;
    for (int i = 0; i < 4; i++) {
      final y = padY + i * (iH / 3);
      canvas.drawLine(Offset(padX, y), Offset(size.width - padX, y), gridPaint);
    }

    // Area fill
    final areaPath = Path()..moveTo(pts.first.dx, size.height - 20);
    for (final p in pts) areaPath.lineTo(p.dx, p.dy);
    areaPath.lineTo(pts.last.dx, size.height - 20);
    areaPath.close();
    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    // Line
    final linePath = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      final cp1 = Offset((pts[i - 1].dx + pts[i].dx) / 2, pts[i - 1].dy);
      final cp2 = Offset((pts[i - 1].dx + pts[i].dx) / 2, pts[i].dy);
      linePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Dots & labels
    final dotPaint = Paint()..color = color;
    final dotInner = Paint()..color = Colors.white;
    final txtStyle = TextStyle(
      color: color,
      fontSize: 9,
      fontFamily: 'monospace',
      fontWeight: FontWeight.bold,
    );
    final lblStyle = const TextStyle(
      color: Color(0xFF64748B),
      fontSize: 9,
      fontFamily: 'monospace',
    );

    for (int i = 0; i < pts.length; i++) {
      canvas.drawCircle(pts[i], 5, dotPaint);
      canvas.drawCircle(pts[i], 2.5, dotInner);

      // Value label
      final vSpan = TextSpan(text: data[i].toString(), style: txtStyle);
      final vPainter = TextPainter(
        text: vSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      vPainter.paint(
        canvas,
        Offset(pts[i].dx - vPainter.width / 2, pts[i].dy - 16),
      );

      // Day label
      final lSpan = TextSpan(text: labels[i], style: lblStyle);
      final lPainter = TextPainter(
        text: lSpan,
        textDirection: TextDirection.ltr,
      )..layout();
      lPainter.paint(
        canvas,
        Offset(pts[i].dx - lPainter.width / 2, size.height - 16),
      );
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter old) =>
      !_listEquals(old.data, data) || old.color != color;

  bool _listEquals(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
