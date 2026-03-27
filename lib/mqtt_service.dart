import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {

  final String clientId;
  final String token;
  final String secret;

  final Function(Map<String, bool>) onStatusChanged;

  late MqttServerClient _client;

  MqttService({
    required this.clientId,
    required this.token,
    required this.secret,
    required this.onStatusChanged,
  });

  Future<void> connect() async {

    _client = MqttServerClient('broker.netpie.io', clientId);

    _client.port = 1883;
    _client.keepAlivePeriod = 20;

    _client.onConnected = _onConnected;
    _client.onDisconnected = _onDisconnected;

    _client.connectionMessage = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(token, secret)
        .startClean();

    try {
      await _client.connect();
    } catch (e) {
      print("MQTT Error: $e");
      _client.disconnect();
      return;
    }

    if (_client.connectionStatus!.state == MqttConnectionState.connected) {

      print("MQTT Connected");

      /// subscribe device status
      _client.subscribe('@msg/weather/device_status', MqttQos.atMostOnce);

      _client.updates!.listen(_onMessage);

    } else {

      print("MQTT connection failed");

      _client.disconnect();

    }
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> events) {

    final recMsg = events[0].payload as MqttPublishMessage;

    final payload = MqttPublishPayload.bytesToStringAsString(
      recMsg.payload.message,
    );

    print("MQTT Message: $payload");

    try {

      final decoded = json.decode(payload);

      final data = decoded['data'];

      onStatusChanged({

        'red': data['red'] == 1,
        'blue': data['blue'] == 1,
        'green': data['green'] == 1,
        'buzzer': data['buzzer'] == 1,

      });

    } catch (e) {

      print("JSON decode error: $e");

    }
  }

  void _onConnected() {
    print("MQTT Connected");
  }

  void _onDisconnected() {
    print("MQTT Disconnected");
  }

  void disconnect() {
    _client.disconnect();
  }
}