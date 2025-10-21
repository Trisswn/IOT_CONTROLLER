import 'package:flutter/material.dart';

// --- Modelo de Datos para un Perfil ---
class UserProfile {
  final String name;
  final IconData icon;
  final bool? ledPreference; // true para ON, false para OFF, null para no cambiar
  final bool? monitorTemperatureHumidity; // true para ON, false para OFF

  UserProfile({
    required this.name,
    required this.icon,
    this.ledPreference,
    this.monitorTemperatureHumidity,
  });

  // Sobrescribimos el operador == y hashCode para comparar perfiles por nombre
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfile &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;
}

// --- La Pantalla de Perfiles ---
class ProfilesScreen extends StatefulWidget {
  const ProfilesScreen({super.key});

  @override
  State<ProfilesScreen> createState() => _ProfilesScreenState();
}

class _ProfilesScreenState extends State<ProfilesScreen> {
  // Lista de perfiles de ejemplo con preferencias
  final List<UserProfile> _profiles = [
    UserProfile(
      name: "Default",
      icon: Icons.home,
      // Default podría tener todo activo o un estado base
      ledPreference: null, // O true si quieres que por defecto estén prendidos
      monitorTemperatureHumidity: true,
    ),
    UserProfile(
      name: "Papá",
      icon: Icons.person,
      ledPreference: false, // LEDs OFF
      monitorTemperatureHumidity: true, // Temp/Humedad ON (asumimos que si no dice OFF, es ON)
    ),
    UserProfile(
      name: "Mamá",
      icon: Icons.person_outline,
      ledPreference: true, // LEDs ON
      monitorTemperatureHumidity: false, // Temp/Humedad OFF
    ),
    UserProfile(
      name: "Hermano",
      icon: Icons.child_care,
      // Añade las preferencias que desees para este perfil
      ledPreference: null,
      monitorTemperatureHumidity: true,
    ),
  ];

  UserProfile? _selectedProfile; // Para saber cuál está activo

  @override
  void initState() {
    super.initState();
    // Seleccionar el perfil "Default" al inicio
    if (_profiles.isNotEmpty) {
      _selectedProfile = _profiles.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Perfiles de Usuario"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: ListView.builder(
        itemCount: _profiles.length,
        itemBuilder: (context, index) {
          final profile = _profiles[index];
          final bool isSelected = profile == _selectedProfile;

          // Crear texto para el subtitulo con las preferencias
          List<String> preferencesText = [];
          if (profile.ledPreference != null) {
            preferencesText.add("LEDs: ${profile.ledPreference! ? 'ON' : 'OFF'}"); //
          }
          if (profile.monitorTemperatureHumidity != null) {
            preferencesText.add("Temp/Hum: ${profile.monitorTemperatureHumidity! ? 'ON' : 'OFF'}"); //
          }

          return ListTile(
            leading: Icon(
              profile.icon,
              color: isSelected ? Colors.indigo : Colors.grey,
            ),
            title: Text(
              profile.name,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            // Mostrar preferencias en el subtitulo si existen
            subtitle: preferencesText.isNotEmpty
                ? Text(preferencesText.join(', '))
                : null,
            trailing: isSelected
                ? const Icon(Icons.check_circle, color: Colors.indigo)
                : null,
            onTap: () {
              setState(() {
                _selectedProfile = profile;
                // --- LÓGICA PARA APLICAR PREFERENCIAS (Pendiente) ---
                // Esta sección es donde integrarías la lógica real
                // para interactuar con tu SmartHomeState o directamente
                // con las funciones de Bluetooth.
                print('Aplicando perfil: ${profile.name}');
                if (profile.ledPreference != null) {
                  print('  - Preferencia LED: ${profile.ledPreference}');
                  // Ejemplo: Llamarías a una función para enviar comando BLE LED
                  // Provider.of<SmartHomeState>(context, listen: false)
                  //     .sendLedCommand(profile.ledPreference!);
                }
                if (profile.monitorTemperatureHumidity != null) {
                  print('  - Pref. Temp/Hum: ${profile.monitorTemperatureHumidity}');
                  // Ejemplo: Activar/desactivar la escucha del sensor en la app
                  // Provider.of<SmartHomeState>(context, listen: false)
                  //     .setSensorMonitoring(profile.monitorTemperatureHumidity!);
                }
                // --- FIN LÓGICA ---

                // Muestra una confirmación visual al usuario
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Perfil "${profile.name}" seleccionado.'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              });
            },
          );
        },
      ),
    );
  }
}