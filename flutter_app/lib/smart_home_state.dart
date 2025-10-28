// lib/smart_home_state.dart

import 'dart:convert'; // Necesario para jsonEncode y jsonDecode
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Para guardar datos
import 'profile_model.dart'; // Importa el modelo de perfil que creamos

class SmartHomeState extends ChangeNotifier {
  // --- Estado original ---
  bool _isConnected = false;
  bool _ledIsOn = false;
  String _statusMessage = "Busca un dispositivo para conectar.";
  double _temperature = double.nan; // Inicializar como NaN
  double _humidity = double.nan;    // Inicializar como NaN
  // ELIMINADO: double _lightLevel = 0.0;

  // --- Estado para perfiles ---
  List<UserProfile> _profiles = [];
  UserProfile? _activeProfile;

  // --- Constructor ---
  SmartHomeState() {
    loadProfiles();
  }

  // --- Getters ---
  bool get isConnected => _isConnected;
  bool get ledIsOn => _ledIsOn;
  String get statusMessage => _statusMessage;
  double get temperature => _temperature;
  double get humidity => _humidity;
  // ELIMINADO: double get lightLevel => _lightLevel;

  List<UserProfile> get profiles => _profiles;
  UserProfile? get activeProfile => _activeProfile;

  // --- Métodos para actualizar el estado ---

  void updateConnectionState(bool connected) {
    _isConnected = connected;
    if (!connected) {
      _statusMessage = "Desconectado. Busca para reconectar.";
      _temperature = double.nan; // Resetea valores a NaN si se desconecta
      _humidity = double.nan;
      // ELIMINADO: _lightLevel = 0.0;
      _activeProfile = null;
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

  // MODIFICADO: Aceptar solo temp y hum
  void updateSensorReadings(double temp, double hum) {
    _temperature = temp;
    _humidity = hum;
    // ELIMINADO: _lightLevel = light;
    notifyListeners();
  }

  // --- Métodos para la gestión de perfiles ---

  Future<void> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final String? profilesString = prefs.getString('profiles');
    if (profilesString != null) {
      try {
        final List<dynamic> profilesJson = jsonDecode(profilesString);
        _profiles = profilesJson.map((json) => UserProfile.fromJson(json)).toList();
      } catch (e) {
        print("Error al cargar perfiles: $e");
        _profiles = [];
      }
    }
    notifyListeners();
  }

  Future<void> _saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final String profilesString = jsonEncode(_profiles.map((p) => p.toJson()).toList());
    await prefs.setString('profiles', profilesString);
  }

  void addProfile(UserProfile profile) {
    _profiles.add(profile);
    _saveProfiles();
    notifyListeners();
  }

  void updateProfile(int index, UserProfile profile) {
    if (index >= 0 && index < _profiles.length) {
      // Si el perfil actualizado es el activo, necesitamos encontrarlo por nombre
      // antes de actualizar la lista, para actualizar la referencia _activeProfile
      String? activeProfileName = _activeProfile?.name;
      bool wasActive = activeProfileName != null && activeProfileName == _profiles[index].name;

      _profiles[index] = profile; // Actualiza el perfil en la lista

      // Si era el activo, actualiza la referencia _activeProfile con el nuevo objeto
      if (wasActive) {
         _activeProfile = _profiles[index];
      }

      _saveProfiles();
      notifyListeners();
    }
  }


  void deleteProfile(int index) {
     if (index >= 0 && index < _profiles.length) {
        if (_activeProfile?.name == _profiles[index].name) {
          _activeProfile = null;
        }
        _profiles.removeAt(index);
        _saveProfiles();
        notifyListeners();
     }
  }

  void setActiveProfile(UserProfile? profile) {
    _activeProfile = profile;
    notifyListeners();
    // La lógica para enviar el perfil al dispositivo está en bluetooth_control_screen
  }
}