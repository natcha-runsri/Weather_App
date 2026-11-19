# weather_app — Weather Monitor

แอป Flutter สำหรับแสดงผลสถานีตรวจวัดอากาศ IoT (หน้าจอแสดงชื่อ "WEATHER MONITOR · สถานีตรวจวัดอากาศ · นครปฐม")
อ่านค่าเซนเซอร์แบบเรียลไทม์จาก **NETPIE** (Device Shadow) และดึงข้อมูลย้อนหลัง 7 วันจาก **Firebase Realtime Database**

🌐 **เว็บที่ deploy แล้ว:** https://natcha-runsri.github.io/Weather_App/

<!-- TODO: เพิ่มคำอธิบายฝั่งฮาร์ดแวร์ (ESP32 + เซนเซอร์ที่ใช้) ถ้ามีเอกสาร -->

---

## ฟีเจอร์หลัก

- **ค่าเซนเซอร์เรียลไทม์** อุณหภูมิ ความชื้น ปริมาณฝน (`analogValue`) ความเร็วลม และทิศทางลม (แสดงเป็นเข็มทิศ) อ่านจาก NETPIE Device Shadow ทุก 5 วินาที
- **Heat Index** คำนวณจากอุณหภูมิและความชื้นด้วยสูตร Rothfusz แบ่งระดับ ปกติ / ระวัง / อันตราย / อันตรายมาก พร้อมคำแนะนำ
- **ข้อมูลย้อนหลัง 7 วัน** จาก Firebase (`/sensorData`) สรุปเป็นรายวัน (อุณหภูมิสูงสุด/ต่ำสุด ความชื้นเฉลี่ย ฝน ลม) และแสดงเป็นกราฟเส้นเลือกได้ว่าจะดูค่าไหน
- **โหมด AUTO / MANUAL** โหมด MANUAL เลือกเปิด/ปิดการ์ดที่แสดงได้ (ฝน อุณหภูมิ ความชื้น ลม Heat Index ย้อนหลัง) และสั่งปิด buzzer
- **ปุ่มเปิด/ปิดการแจ้งเตือน** ส่งคำสั่งเปิด/ปิด `buzzer` ไปยังอุปกรณ์ผ่าน NETPIE REST API (topic `weather/device_control`)
- **ตรวจค่าตั้งค่า** ถ้ายังไม่ได้ใส่ token ของ NETPIE แอปจะแสดงหน้าข้อความบอกว่าขาดค่าอะไร แทนที่จะพังเงียบ ๆ

> หมายเหตุ: ในโปรเจกต์มี `lib/weather_mqtt.dart` + `lib/mqtt_service.dart` (หน้าจอแบบ MQTT) แต่ `main.dart` ไม่ได้เรียกใช้ หน้าจอหลักคือ `lib/weather.dart`
> <!-- TODO: ยืนยันว่าจะเก็บหรือลบหน้าจอ MQTT (mqtt_server_client ใช้ dart:io จึงไม่ทำงานบนเว็บ) -->

## Tech Stack

| รายการ | เวอร์ชัน |
|---|---|
| Dart SDK | `^3.7.2` (จาก `pubspec.yaml`) |
| Flutter | 3.29.3 ใน CI (มาพร้อม Dart 3.7.2) — `pubspec.lock` ต้องการ Flutter `>=3.22.0` |
| http | `^1.5.0` — เรียก NETPIE REST API และ Firebase REST |
| mqtt_client | `^10.8.0` — ใช้ในหน้าจอ MQTT (ไม่ได้ใช้ในหน้าหลัก) |
| firebase_core / firebase_database | `^3.10.1` / `^11.3.0` — มีใน dependencies แต่โค้ดปัจจุบันเรียก Firebase ผ่าน REST (http) |
| cupertino_icons | `^1.0.8` |

แพลตฟอร์มที่มีโฟลเดอร์ในโปรเจกต์: Android, iOS, Web, Windows, macOS, Linux

## โครงสร้างโฟลเดอร์

```
weather_app/
├── lib/
│   ├── main.dart              # จุดเริ่มแอป + หน้าแจ้งเตือนเมื่อยังไม่ได้ตั้งค่า
│   ├── weather.dart           # หน้าจอหลัก (Dashboard, Heat Index, กราฟย้อนหลัง)
│   ├── weather_service.dart   # เรียก NETPIE REST API และ Firebase REST
│   ├── weather_mqtt.dart      # หน้าจอแบบ MQTT (ไม่ได้ใช้ใน main.dart)
│   └── mqtt_service.dart      # MQTT client ไปยัง broker.netpie.io
├── web/                       # ไฟล์สำหรับ build เว็บ (index.html, manifest.json, icons)
├── android/  ios/  windows/  macos/  linux/
├── .github/workflows/pages.yml   # deploy เว็บไป GitHub Pages
├── dart_defines.example.json     # ตัวอย่างไฟล์ตั้งค่า (ค่าปลอม)
├── pubspec.yaml
└── README.md
```

## Prerequisites

- Flutter SDK ที่มาพร้อม Dart 3.7.2 ขึ้นไป (เช่น Flutter 3.29.3) — ตรวจด้วย `flutter --version`
- Google Chrome (สำหรับรันบนเว็บ)
- Android Studio / Android SDK + อุปกรณ์หรือ emulator (สำหรับรันบน Android)
- Xcode บน macOS (สำหรับรันบน iOS)
- บัญชี [NETPIE](https://netpie.io) และ Firebase Realtime Database ของตัวเอง

## การตั้งค่า

### 1) NETPIE

ต้องสร้าง **device ของตัวเอง** บน NETPIE (โค้ดใช้ 2 device)

| Device | ใช้ทำอะไร | Client ID อยู่ที่ |
|---|---|---|
| Mobile App (control) | ส่งคำสั่งไป topic `weather/device_control` | `WeatherService.controlClientId` ใน `lib/weather_service.dart` |
| ESP32 (status) | อ่าน Device Shadow (`temperature`, `humidity`, `analogValue`, `status`, `windSpeed`, `windDeg`, `red`, `green`, `blue`, `buzzer`) | `WeatherService.statusClientId` ใน `lib/weather_service.dart` |

Client ID เขียนอยู่ในโค้ด ถ้าใช้ device ของตัวเองให้แก้ค่าในไฟล์ข้างบน ส่วน **token / secret ห้ามใส่ในโค้ด** ให้ใส่ในไฟล์ `dart_defines.json`

```bash
cp dart_defines.example.json dart_defines.json
```

แล้วแก้ค่าในไฟล์ `dart_defines.json` (ไฟล์นี้อยู่ใน `.gitignore` ห้าม commit):

```json
{
  "NETPIE_CONTROL_TOKEN": "your_token_here",
  "NETPIE_STATUS_TOKEN": "your_token_here",
  "NETPIE_MOBILE_SECRET": "your_token_here"
}
```

| ชื่อค่า | ความหมาย |
|---|---|
| `NETPIE_CONTROL_TOKEN` | Token ของ device Mobile App (ใช้เป็น MQTT username ในหน้าจอ MQTT ด้วย) |
| `NETPIE_STATUS_TOKEN` | Token ของ device ESP32 |
| `NETPIE_MOBILE_SECRET` | Secret ของ device Mobile App (ใช้เฉพาะหน้าจอ MQTT) |

### 2) Firebase Realtime Database

แก้ค่าคงที่ `firebaseUrl` ใน `lib/weather_service.dart` ให้เป็น URL ของ database ตัวเอง
แอปอ่าน node `/sensorData` (query `orderBy="timestamp"`) แต่ละ entry ควรมี `timestamp` (ISO 8601), `temperature`, `humidity`, `analogValue`, `windSpeed`

<!-- TODO: ระบุ Firebase Rules ที่ต้องใช้ (การ query orderBy ต้องมี .indexOn: "timestamp") -->

## วิธีติดตั้งและรัน

```bash
flutter pub get

# เว็บ (Chrome)
flutter run -d chrome --dart-define-from-file=dart_defines.json

# มือถือ (ดูรายชื่ออุปกรณ์ด้วย flutter devices)
flutter run --dart-define-from-file=dart_defines.json
```

ถ้าลืมใส่ `--dart-define-from-file` แอปจะแสดงหน้า "ยังไม่ได้ตั้งค่า: ..." บอกชื่อค่าที่ขาด

## วิธี build

```bash
# เว็บ (ผลลัพธ์อยู่ที่ build/web)
flutter build web --release --base-href "/Weather_App/" --dart-define-from-file=dart_defines.json

# Android APK (ผลลัพธ์อยู่ที่ build/app/outputs/flutter-apk/app-release.apk)
flutter build apk --release --dart-define-from-file=dart_defines.json
```

<!-- TODO: ตั้งค่า release signing ของ Android (ตอนนี้ build.gradle.kts ใช้ค่าเริ่มต้นของ Flutter) -->

## การ deploy อัตโนมัติ (GitHub Actions)

ไฟล์ `.github/workflows/pages.yml` ทำงานเมื่อ push เข้า `main` หรือกด Run workflow เอง (`workflow_dispatch`):

1. checkout → ติดตั้ง Flutter 3.29.3 → `flutter pub get`
2. สร้าง `dart_defines.json` จาก GitHub Secrets (`NETPIE_CONTROL_TOKEN`, `NETPIE_STATUS_TOKEN`, `NETPIE_MOBILE_SECRET`) โดยไม่พิมพ์ค่าลง log
3. `flutter build web --release --base-href "/Weather_App/" --dart-define-from-file=dart_defines.json`
4. ลบ `dart_defines.json` → อัปโหลด `build/web` → deploy ไป GitHub Pages

ตั้งค่าครั้งแรกบน GitHub:
- **Settings → Secrets and variables → Actions** เพิ่ม secret ทั้ง 3 ตัวข้างบน
- **Settings → Pages → Source** เลือก **GitHub Actions**

> ⚠️ **ข้อควรรู้:** `--dart-define` แค่ทำให้ค่าไม่อยู่ใน repo แต่ค่าจะถูก **คอมไพล์เข้าไปใน `main.dart.js`** ของเว็บที่ deploy (และใน APK) ใครก็เปิดดูได้ ควรใช้ device / token ที่จำกัดสิทธิ์ และหมุน (regenerate) token เมื่อจำเป็น ถ้าต้องการซ่อนจริงต้องเรียก NETPIE ผ่าน backend แทน

<!-- TODO: ทดสอบว่า NETPIE REST API อนุญาต CORS จากโดเมน github.io หรือไม่ -->

## ผู้พัฒนา

- [natcha-runsri](https://github.com/natcha-runsri)

<!-- TODO: เพิ่มชื่อ-นามสกุล / สมาชิกในทีม / รายวิชา (ถ้ามี) -->
