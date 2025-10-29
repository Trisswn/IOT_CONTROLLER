// lib/profile_model.dart

// Clase para la configuración individual de cada LED dentro de un perfil
class LedConfig {
  String areaName; // Nombre identificador (ej. "Sala", "Cocina")
  bool enabled;      // Si este LED se controla en este perfil
  int onInterval;   // Intervalo ON para parpadeo (ms)
  int offInterval;  // Intervalo OFF para parpadeo (ms)
  int autoOffDuration; // Duración para auto-apagado (segundos)

  LedConfig({
    required this.areaName,
    this.enabled = true,
    this.onInterval = 0,
    this.offInterval = 0,
    this.autoOffDuration = 0,
  });

  // Métodos para JSON
  Map<String, dynamic> toJson() => {
        'areaName': areaName,
        'enabled': enabled,
        'onInterval': onInterval,
        'offInterval': offInterval,
        'autoOffDuration': autoOffDuration,
      };

  factory LedConfig.fromJson(Map<String, dynamic> json) => LedConfig(
        areaName: json['areaName'] ?? 'LED Desconocido', // Nombre por defecto
        enabled: json['enabled'] ?? true,
        onInterval: json['onInterval'] ?? 0,
        offInterval: json['offInterval'] ?? 0,
        autoOffDuration: json['autoOffDuration'] ?? 0,
      );

  // Propiedades calculadas para modo
  bool get isBlinkingMode => enabled && onInterval > 0 && offInterval > 0;
  bool get isAutoOffMode => enabled && autoOffDuration > 0 && !isBlinkingMode;
  bool get isManualMode => enabled && !isBlinkingMode && !isAutoOffMode;
}

// Perfil de usuario principal, ahora contiene una lista de configuraciones de LED
class UserProfile {
  String name;
  List<LedConfig> ledConfigs; // Lista de configuraciones para cada LED
  bool sensorsEnabled;
  int sensorReadInterval;

  UserProfile({
    required this.name,
    required this.ledConfigs, // Requiere la lista al crear
    this.sensorsEnabled = true,
    this.sensorReadInterval = 2000,
  });

  // Métodos para convertir a y desde JSON
  Map<String, dynamic> toJson() => {
        'name': name,
        // Convertir la lista de LedConfig a una lista de JSON
        'ledConfigs': ledConfigs.map((config) => config.toJson()).toList(),
        'sensorsEnabled': sensorsEnabled,
        'sensorReadInterval': sensorReadInterval,
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
     // Decodificar la lista de LedConfig desde JSON
     var ledConfigsFromJson = json['ledConfigs'] as List<dynamic>?;
     List<LedConfig> ledConfigsList = ledConfigsFromJson != null
         ? ledConfigsFromJson.map((configJson) => LedConfig.fromJson(configJson)).toList()
         : getDefaultLedConfigs(); // Usar configuración por defecto si no existe

    // Asegurarse de que siempre tengamos la cantidad correcta de configs (ej. 3)
     if (ledConfigsList.length != 3) { // AJUSTAR ESTE NÚMERO SI CAMBIAS LA CANTIDAD DE LEDS
       print("Advertencia: Número incorrecto de LedConfigs en perfil '${json['name']}'. Usando defaults.");
       ledConfigsList = getDefaultLedConfigs();
     }


     return UserProfile(
        name: json['name'] ?? 'Perfil sin nombre',
        ledConfigs: ledConfigsList,
        sensorsEnabled: json['sensorsEnabled'] ?? true,
        sensorReadInterval: json['sensorReadInterval'] ?? 2000,
      );
   }

   // Helper para obtener una configuración de LED por defecto
   static List<LedConfig> getDefaultLedConfigs() {
     return [
       LedConfig(areaName: "Sala"),
       LedConfig(areaName: "Cocina"),
       LedConfig(areaName: "Dormitorio"),
       // Añade más si controlas más LEDs
     ];
   }

   // ---
   // --- ¡¡¡ESTA ES LA FUNCIÓN MODIFICADA!!! ---
   // ---
   // Método para generar el string de configuración para el ESP32
   String generateEsp32ConfigString() {
     // Esta parte genera "L0,ena,on,off,auto|L1,..."
     String ledConfigString = ledConfigs.asMap().entries.map((entry) {
       int index = entry.key;
       LedConfig config = entry.value;
       // Este formato "L$index,..." coincide con el sscanf(token + 3, ...) de tu .ino
       return "L$index,${config.enabled ? 1:0},${config.onInterval},${config.offInterval},${config.autoOffDuration}";
     }).join("|");

     String sensorConfigString = "S,${sensorsEnabled ? 1:0},$sensorReadInterval";

     // ¡NUEVO! Añadimos el nombre al inicio, separado por "||"
     // El ESP32 buscará "NAME:" y "||" para separar el nombre.
     return "NAME:$name||$ledConfigString|$sensorConfigString";
   }
}