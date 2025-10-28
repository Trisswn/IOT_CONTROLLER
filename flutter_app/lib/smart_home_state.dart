// lib/smart_home_state.dart

import 'dart:convert'; // Necesario para jsonEncode y jsonDecode
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Para guardar datos
import 'profile_model.dart'; // Importa el modelo de perfil que creamos

class SmartHomeState extends ChangeNotifier {
  // --- Estado Conexión y Sensores ---
  bool _isConnected = false;
  String _statusMessage = "Busca un dispositivo para conectar.";
  double _temperature = double.nan;
  double _humidity = double.nan;

  // --- Estado LEDs (Mapa para identificarlos por nombre de área) ---
  Map<String, bool> _ledStates = {
    "Sala": false,
    "Cocina": false,
    "Dormitorio": false,
     // Coincidir con los nombres en getDefaultLedConfigs()
  };

  // --- Estado Perfiles ---
  List<UserProfile> _profiles = [];
  UserProfile? _activeProfile;

  // --- Constructor ---
  SmartHomeState() {
    loadProfiles();
  }

  // --- Getters ---
  bool get isConnected => _isConnected;
  String get statusMessage => _statusMessage;
  double get temperature => _temperature;
  double get humidity => _humidity;
  Map<String, bool> get ledStates => Map.unmodifiable(_ledStates); // Devuelve copia inmutable
  List<String> get ledAreaNames => _ledStates.keys.toList(); // Lista de nombres de área

  List<UserProfile> get profiles => _profiles;
  UserProfile? get activeProfile => _activeProfile;

  // --- Métodos para actualizar el estado ---

  void updateConnectionState(bool connected) {
    _isConnected = connected;
    if (!connected) {
      _statusMessage = "Desconectado. Busca para reconectar.";
      _temperature = double.nan;
      _humidity = double.nan;
      // Resetear estado de todos los LEDs a false al desconectar
      _ledStates.updateAll((key, value) => false);
      _activeProfile = null;
    }
    notifyListeners();
  }

  // Actualiza el estado de un LED específico por su nombre de área
  void setLedState(String areaName, bool isOn) {
    if (_ledStates.containsKey(areaName)) {
      _ledStates[areaName] = isOn;
      notifyListeners();
    } else {
      print("Advertencia: Intento de actualizar estado para área desconocida '$areaName'");
    }
  }

  // Actualiza el estado de TODOS los LEDs a partir de una lista de booleanos
  // (útil para procesar notificaciones BLE)
  void updateAllLedStates(List<bool> states) {
     if (states.length == _ledStates.length) {
       List<String> keys = _ledStates.keys.toList();
       for (int i = 0; i < keys.length; i++) {
         _ledStates[keys[i]] = states[i];
       }
       notifyListeners();
     } else {
        print("Error: La lista de estados recibida (${states.length}) no coincide con la cantidad de LEDs (${_ledStates.length}).");
     }
  }


  void setStatusMessage(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  void updateSensorReadings(double temp, double hum) {
    _temperature = temp;
    _humidity = hum;
    notifyListeners();
  }

  // --- Métodos Perfiles (sin cambios funcionales, pero ahora usan el nuevo UserProfile) ---

  Future<void> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final String? profilesString = prefs.getString('profiles');
    if (profilesString != null) {
      try {
        final List<dynamic> profilesJson = jsonDecode(profilesString);
        _profiles = profilesJson.map((json) => UserProfile.fromJson(json)).toList();

        // Asegurarse que los perfiles cargados tengan la estructura correcta de LEDs
        // (Esto ayuda si se añaden/quitan LEDs después de haber guardado perfiles)
        int expectedLedCount = UserProfile.getDefaultLedConfigs().length;
        _profiles.forEach((profile) {
          if(profile.ledConfigs.length != expectedLedCount) {
             print("Advertencia: Perfil '${profile.name}' tiene ${profile.ledConfigs.length} configs de LED, se esperaban $expectedLedCount. Reemplazando con defaults.");
             profile.ledConfigs = UserProfile.getDefaultLedConfigs();
          }
        });

      } catch (e) {
        print("Error al cargar perfiles: $e");
        _profiles = [];
      }
    }
    // Si no hay perfiles, crear uno por defecto? (Opcional)
    // if (_profiles.isEmpty) {
    //   addProfile(UserProfile(name: "Default", ledConfigs: UserProfile.getDefaultLedConfigs()));
    // }
    notifyListeners();
  }

  Future<void> _saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final String profilesString = jsonEncode(_profiles.map((p) => p.toJson()).toList());
    await prefs.setString('profiles', profilesString);
  }

  // Añade un perfil (asegúrate de que tenga la configuración de LEDs por defecto si es nuevo)
  void addProfile(UserProfile profile) {
     // Si es un perfil totalmente nuevo, asegurar que tenga la lista de LedConfig correcta
     if (profile.ledConfigs.isEmpty) {
        profile.ledConfigs = UserProfile.getDefaultLedConfigs();
     }
    _profiles.add(profile);
    _saveProfiles();
    notifyListeners();
  }

  void updateProfile(int index, UserProfile profile) {
    if (index >= 0 && index < _profiles.length) {
      String? activeProfileName = _activeProfile?.name;
      bool wasActive = activeProfileName != null && activeProfileName == _profiles[index].name;

      _profiles[index] = profile;

      if (wasActive) {
         _activeProfile = _profiles[index]; // Actualizar la referencia del perfil activo
      }

      _saveProfiles();
      notifyListeners();

       // Si el perfil actualizado era el activo y estamos conectados,
       // podríamos querer reenviar la configuración al ESP32.
       // Esto se manejará en bluetooth_control_screen al volver de la edición.
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

  // Establece el perfil activo y potencialmente envía su configuración
  void setActiveProfile(UserProfile? profile) {
    _activeProfile = profile;
    notifyListeners();
    // La lógica de envío está en bluetooth_control_screen
  }
}