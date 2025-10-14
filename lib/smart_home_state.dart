import 'package:flutter/foundation.dart';

class SmartHomeState extends ChangeNotifier {
  bool _isConnected = false;
  bool _ledIsOn = false;
  String _statusMessage = "Busca un dispositivo para conectar.";
  double _temperature = 0.0;
  double _humidity = 0.0;
  double _lightLevel = 0.0; 

  bool get isConnected => _isConnected;
  bool get ledIsOn => _ledIsOn;
  String get statusMessage => _statusMessage;
  double get temperature => _temperature;
  double get humidity => _humidity;
  double get lightLevel => _lightLevel; 

  void updateConnectionState(bool connected) {
    _isConnected = connected;
    if (!connected) {
      _statusMessage = "Desconectado. Busca para reconectar.";
      _temperature = 0.0;
      _humidity = 0.0;
      _lightLevel = 0.0;
    }
    notifyListeners();
  }

  void setLedState(bool isOn) {
    _ledIsOn = isOn;
    notifyListeners();
  }

  void setStatusMessage(String message) {
    _statusMessage = message;
    notifyListeners();
  }


  void updateSensorReadings(double temp, double hum, double light) {
    _temperature = temp;
    _humidity = hum;
    _lightLevel = light;
    notifyListeners();
  }
}