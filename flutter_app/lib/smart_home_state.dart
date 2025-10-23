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
  double _temperature = 0.0;
  double _humidity = 0.0;
  double _lightLevel = 0.0;

  // --- Estado para perfiles ---
  List<UserProfile> _profiles = [];
  UserProfile? _activeProfile;

  // --- Constructor ---
  // Llama a loadProfiles cuando se crea una instancia del estado
  SmartHomeState() {
    loadProfiles();
  }

  // --- Getters (para acceder a los valores desde la UI) ---
  bool get isConnected => _isConnected;
  bool get ledIsOn => _ledIsOn;
  String get statusMessage => _statusMessage;
  double get temperature => _temperature;
  double get humidity => _humidity;
  double get lightLevel => _lightLevel;

  List<UserProfile> get profiles => _profiles;
  UserProfile? get activeProfile => _activeProfile;

  // --- Métodos para actualizar el estado ---

  // Actualiza el estado de la conexión Bluetooth
  void updateConnectionState(bool connected) {
    _isConnected = connected;
    if (!connected) {
      _statusMessage = "Desconectado. Busca para reconectar.";
      _temperature = 0.0; // Resetea valores si se desconecta
      _humidity = 0.0;
      _lightLevel = 0.0;
      _activeProfile = null; // Desactiva el perfil al desconectar
    }
    notifyListeners(); // Notifica a los widgets que escuchan
  }

  // Actualiza el estado del LED (cuando se controla manualmente)
  void setLedState(bool isOn) {
    _ledIsOn = isOn;
    notifyListeners();
  }

  // Establece un mensaje de estado para mostrar al usuario
  void setStatusMessage(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  // Actualiza las lecturas de los sensores
  void updateSensorReadings(double temp, double hum, double light) {
    _temperature = temp;
    _humidity = hum;
    _lightLevel = light;
    notifyListeners();
  }

  // --- Métodos para la gestión de perfiles ---

  // Carga los perfiles guardados desde SharedPreferences
  Future<void> loadProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    final String? profilesString = prefs.getString('profiles'); // Lee la cadena JSON guardada
    if (profilesString != null) {
      try {
        final List<dynamic> profilesJson = jsonDecode(profilesString); // Decodifica el JSON
        // Convierte cada objeto JSON en un UserProfile
        _profiles = profilesJson.map((json) => UserProfile.fromJson(json)).toList();
      } catch (e) {
        // Maneja el caso de que el JSON guardado esté corrupto
        print("Error al cargar perfiles: $e");
        _profiles = []; // Resetea a una lista vacía
      }
    }
    notifyListeners(); // Actualiza la UI
  }

  // Guarda la lista actual de perfiles en SharedPreferences
  Future<void> _saveProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    // Convierte la lista de UserProfile a una lista de Map (JSON) y luego a una cadena
    final String profilesString = jsonEncode(_profiles.map((p) => p.toJson()).toList());
    await prefs.setString('profiles', profilesString); // Guarda la cadena
  }

  // Añade un nuevo perfil a la lista y lo guarda
  void addProfile(UserProfile profile) {
    _profiles.add(profile);
    _saveProfiles(); // Guarda después de añadir
    notifyListeners();
  }

  // Actualiza un perfil existente en la lista y lo guarda
  void updateProfile(int index, UserProfile profile) {
    if (index >= 0 && index < _profiles.length) {
      _profiles[index] = profile;
      _saveProfiles(); // Guarda después de actualizar
      notifyListeners();
      // Si el perfil actualizado es el activo, actualiza la referencia
      if (_activeProfile?.name == _profiles[index].name) { // Compara por nombre o un ID si lo tuvieras
          setActiveProfile(_profiles[index]);
      }
    }
  }

  // Elimina un perfil de la lista y lo guarda
  void deleteProfile(int index) {
     if (index >= 0 && index < _profiles.length) {
        // Si el perfil a eliminar es el activo, desactívalo primero
        if (_activeProfile?.name == _profiles[index].name) {
          _activeProfile = null;
        }
        _profiles.removeAt(index);
        _saveProfiles(); // Guarda después de eliminar
        notifyListeners();
     }
  }

  // Establece el perfil activo
  void setActiveProfile(UserProfile? profile) {
    _activeProfile = profile;
    notifyListeners();
    // Aquí puedes añadir la lógica para enviar la configuración del perfil al ESP32
    // Ejemplo: if (profile != null && _isConnected) { _sendProfileToDevice(profile); }
  }
}