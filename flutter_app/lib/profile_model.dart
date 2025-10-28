// lib/profile_model.dart
class UserProfile {
  String name;
  bool lightsEnabled; // Controlar si las luces se gestionan en este perfil
  int lightOnInterval; // Intervalo de parpadeo encendido (ms). 0 = control manual/apagado automático
  int lightOffInterval; // Intervalo de parpadeo apagado (ms). 0 = control manual/apagado automático
  int autoOffDuration; // Duración en segundos para apagado automático. 0 = desactivado
  bool sensorsEnabled; // Controlar si los sensores se leen en este perfil
  int sensorReadInterval; // Intervalo lectura sensores (ms)

  UserProfile({
    required this.name,
    this.lightsEnabled = true,
    this.lightOnInterval = 0,
    this.lightOffInterval = 0,
    this.autoOffDuration = 0, // Valor por defecto: apagado automático desactivado
    this.sensorsEnabled = true,
    this.sensorReadInterval = 2000,
  });

  // Métodos para convertir a y desde JSON (para guardar en SharedPreferences)
  Map<String, dynamic> toJson() => {
        'name': name,
        'lightsEnabled': lightsEnabled,
        'lightOnInterval': lightOnInterval,
        'lightOffInterval': lightOffInterval,
        'autoOffDuration': autoOffDuration, // Añadir al JSON
        'sensorsEnabled': sensorsEnabled,
        'sensorReadInterval': sensorReadInterval,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        name: json['name'],
        lightsEnabled: json['lightsEnabled'] ?? true, // Valor por defecto si no existe
        lightOnInterval: json['lightOnInterval'] ?? 0,
        lightOffInterval: json['lightOffInterval'] ?? 0,
        autoOffDuration: json['autoOffDuration'] ?? 0, // Leer del JSON, con valor por defecto
        sensorsEnabled: json['sensorsEnabled'] ?? true,
        sensorReadInterval: json['sensorReadInterval'] ?? 2000,
      );

  // Propiedad para saber si el perfil usa parpadeo
  bool get isBlinkingMode => lightsEnabled && lightOnInterval > 0 && lightOffInterval > 0;

  // Propiedad para saber si el perfil usa apagado automático
  bool get isAutoOffMode => lightsEnabled && autoOffDuration > 0 && !isBlinkingMode;

  // Propiedad para saber si el control manual de luces está permitido
  bool get allowManualLightControl => lightsEnabled && !isBlinkingMode && !isAutoOffMode;
}