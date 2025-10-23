// lib/profile_model.dart
class UserProfile {
  String name;
  bool lightsEnabled;
  int lightOnInterval; // en milisegundos
  int lightOffInterval; // en milisegundos
  bool sensorsEnabled;
  int sensorReadInterval; // en milisegundos

  UserProfile({
    required this.name,
    this.lightsEnabled = true,
    this.lightOnInterval = 0, // 0 significa control manual
    this.lightOffInterval = 0,
    this.sensorsEnabled = true,
    this.sensorReadInterval = 2000,
  });

  // Métodos para convertir a y desde JSON (para guardar en SharedPreferences)
  Map<String, dynamic> toJson() => {
        'name': name,
        'lightsEnabled': lightsEnabled,
        'lightOnInterval': lightOnInterval,
        'lightOffInterval': lightOffInterval,
        'sensorsEnabled': sensorsEnabled,
        'sensorReadInterval': sensorReadInterval,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        name: json['name'],
        lightsEnabled: json['lightsEnabled'],
        lightOnInterval: json['lightOnInterval'],
        lightOffInterval: json['lightOffInterval'],
        sensorsEnabled: json['sensorsEnabled'],
        sensorReadInterval: json['sensorReadInterval'],
      );
}