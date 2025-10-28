// lib/profile_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'smart_home_state.dart';
import 'profile_model.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart';

// Enum para los modos de luz (sin cambios)
enum LightMode { manual, blink, autoOff }

class ProfileEditScreen extends StatefulWidget {
  final int? profileIndex;

  const ProfileEditScreen({super.key, this.profileIndex});

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late List<LedConfig> _currentLedConfigs;
  late List<LightMode> _selectedLightModes;

  late bool _sensorsEnabled;
  late TextEditingController _sensorReadIntervalController;

  @override
  void initState() {
    super.initState();
    final state = Provider.of<SmartHomeState>(context, listen: false);
    UserProfile profile;

    if (widget.profileIndex != null && widget.profileIndex! < state.profiles.length) {
      profile = state.profiles[widget.profileIndex!];
      _currentLedConfigs = profile.ledConfigs.map((config) => LedConfig.fromJson(config.toJson())).toList();
    } else {
      profile = UserProfile(
        name: '',
        ledConfigs: UserProfile.getDefaultLedConfigs(),
        sensorsEnabled: true,
        sensorReadInterval: 2000,
      );
      _currentLedConfigs = profile.ledConfigs;
    }

    _nameController = TextEditingController(text: profile.name);
    _sensorsEnabled = profile.sensorsEnabled;
    _sensorReadIntervalController = TextEditingController(text: profile.sensorReadInterval.toString());

    _selectedLightModes = _currentLedConfigs.map((config) {
      if (config.isBlinkingMode) return LightMode.blink;
      if (config.isAutoOffMode) return LightMode.autoOff;
      return LightMode.manual;
    }).toList();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sensorReadIntervalController.dispose();
    super.dispose();
  }

  void _saveForm() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      final name = _nameController.text;
      int sensorReadInterval = int.tryParse(_sensorReadIntervalController.text) ?? 2000;

      // Los valores de _currentLedConfigs se actualizan directamente
      // en los onSaved de los TextFormField dentro de _buildLedConfigSection.

      final newProfile = UserProfile(
        name: name,
        ledConfigs: _currentLedConfigs,
        sensorsEnabled: _sensorsEnabled,
        sensorReadInterval: sensorReadInterval,
      );

      final state = Provider.of<SmartHomeState>(context, listen: false);
      bool wasActive = false;
      String? oldName;

      if (widget.profileIndex != null) {
         oldName = state.profiles[widget.profileIndex!].name;
         wasActive = state.activeProfile?.name == oldName;
        state.updateProfile(widget.profileIndex!, newProfile);
      } else {
        state.addProfile(newProfile);
      }

      if (wasActive && mounted) {
         Navigator.of(context).pop(newProfile); // Devolver el perfil guardado para reenviar
      } else {
         Navigator.of(context).pop();
      }
    }
  }

  // --- Widgets de Construcción ---

  // Header reutilizable
  Widget _buildSectionHeader(String title, IconData icon) {
     // CORRECCIÓN: Añadido return explícito
     return Padding(
      padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }

  // NUEVO: Widget para construir la sección de configuración de UN LED
  Widget _buildLedConfigSection(int index, LedConfig config) {
    // Keys para los TextFormField
    final onIntervalKey = GlobalKey<FormFieldState>();
    final offIntervalKey = GlobalKey<FormFieldState>();
    final autoOffKey = GlobalKey<FormFieldState>();

    // Usar los valores actuales de config como valor inicial
    String onIntervalInitialValue = config.onInterval.toString();
    String offIntervalInitialValue = config.offInterval.toString();
    String autoOffInitialValue = config.autoOffDuration.toString();

    LightMode currentMode = _selectedLightModes[index];

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16.0, right: 8.0, top: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(config.areaName, style: Theme.of(context).textTheme.titleMedium),
                Switch(
                  value: config.enabled,
                  onChanged: (val) => setState(() => config.enabled = val),
                  activeColor: AppColors.primary,
                ),
              ],
            ),
          ),
          if (config.enabled) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 12.0, right: 16.0),
              child: Text("Modo:", style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.textSecondary)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: SegmentedButton<LightMode>(
                 segments: const <ButtonSegment<LightMode>>[
                   ButtonSegment<LightMode>(value: LightMode.manual, label: Text('Manual'), icon: Icon(Icons.touch_app_outlined)),
                   ButtonSegment<LightMode>(value: LightMode.blink, label: Text('Parpadeo'), icon: Icon(Icons.wb_incandescent_outlined)),
                   ButtonSegment<LightMode>(value: LightMode.autoOff, label: Text('Auto Off'), icon: Icon(Icons.timer_outlined)),
                 ],
                 selected: {currentMode},
                 onSelectionChanged: (Set<LightMode> newSelection) {
                   setState(() {
                     _selectedLightModes[index] = newSelection.first;
                     if (_selectedLightModes[index] == LightMode.blink) {
                       config.autoOffDuration = 0;
                       if (config.onInterval == 0) config.onInterval = 1000;
                       if (config.offInterval == 0) config.offInterval = 1000;
                     } else if (_selectedLightModes[index] == LightMode.autoOff) {
                       config.onInterval = 0;
                       config.offInterval = 0;
                       if (config.autoOffDuration == 0) config.autoOffDuration = 60;
                     } else { // Manual
                       config.onInterval = 0;
                       config.offInterval = 0;
                       config.autoOffDuration = 0;
                     }
                     // Forzar reconstrucción de los inputs al cambiar modo usando ValueKey
                   });
                 },
                 style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: AppColors.primary.withOpacity(0.2),
                    selectedForegroundColor: AppColors.primaryDark,
                 ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                // Usar ValueKey para forzar la reconstrucción de los hijos al cambiar de modo
                key: ValueKey('${index}_$currentMode'),
                children: [
                  if (currentMode == LightMode.blink)
                    Row(
                      children: [
                        Expanded(
                          child: _buildNumberInput(
                            // CORRECCIÓN: Pasar key correctamente
                            key: onIntervalKey, // <<<<<< CORREGIDO
                            initialValue: onIntervalInitialValue,
                            labelText: 'Encendido (ms)',
                            icon: Icons.timer,
                            minValue: 50,
                            enabled: config.enabled,
                            onSaved: (value) => config.onInterval = int.tryParse(value ?? '0') ?? 0,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildNumberInput(
                            // CORRECCIÓN: Pasar key correctamente
                            key: offIntervalKey, // <<<<<< CORREGIDO
                            initialValue: offIntervalInitialValue,
                            labelText: 'Apagado (ms)',
                            icon: Icons.timer_off_outlined,
                            minValue: 50,
                            enabled: config.enabled,
                            onSaved: (value) => config.offInterval = int.tryParse(value ?? '0') ?? 0,
                          ),
                        ),
                      ],
                    ),
                  if (currentMode == LightMode.autoOff)
                    _buildNumberInput(
                      // CORRECCIÓN: Pasar key correctamente
                      key: autoOffKey, // <<<<<< CORREGIDO
                      initialValue: autoOffInitialValue,
                      labelText: 'Apagar después de (s)',
                      icon: Icons.hourglass_bottom,
                      minValue: 1,
                      enabled: config.enabled,
                      onSaved: (value) => config.autoOffDuration = int.tryParse(value ?? '0') ?? 0,
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profileIndex == null ? 'Nuevo Perfil' : 'Editar Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined),
            tooltip: "Guardar Perfil",
            onPressed: _saveForm,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // --- Tarjeta Nombre ---
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Perfil',
                    icon: Icon(Icons.label_outline, color: AppColors.primary),
                     border: OutlineInputBorder(),
                     filled: true,
                     fillColor: AppColors.background,
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, introduce un nombre.';
                    }
                    final state = Provider.of<SmartHomeState>(context, listen: false);
                    bool nameExists = state.profiles.asMap().entries.any((entry) {
                       int idx = entry.key;
                       UserProfile p = entry.value;
                       return p.name == value && idx != widget.profileIndex;
                    });
                    if (nameExists) {
                      return 'Este nombre de perfil ya existe.';
                    }
                    return null;
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // --- Título Sección LEDs ---
            // CORRECCIÓN: Usar icono existente
            _buildSectionHeader('Configuración LEDs', Icons.lightbulb_outline), // <<<<<<< CORREGIDO

            // --- Secciones de Configuración para CADA LED ---
            for (int i = 0; i < _currentLedConfigs.length; i++)
               _buildLedConfigSection(i, _currentLedConfigs[i]),

            const SizedBox(height: 4),

            // --- Tarjeta Configuración Sensores ---
            Card(
              child: Column(
                children: [
                   _buildSectionHeader('Monitoreo Sensores', Icons.sensors),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Habilitar lectura sensores', style: Theme.of(context).textTheme.bodyLarge),
                          Switch(
                            value: _sensorsEnabled,
                            onChanged: (val) => setState(() => _sensorsEnabled = val),
                             activeColor: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                   AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: EdgeInsets.fromLTRB(16.0, _sensorsEnabled ? 16.0 : 0.0, 16.0, _sensorsEnabled ? 16.0 : 0.0),
                      constraints: BoxConstraints(maxHeight: _sensorsEnabled ? 100 : 0),
                      child: Opacity(
                          opacity: _sensorsEnabled ? 1.0 : 0.0,
                          child: _buildNumberInput(
                            // CORRECCIÓN: Pasar controller como parámetro nombrado
                            controller: _sensorReadIntervalController, // <<<<<< CORREGIDO
                            labelText: 'Intervalo Lectura (ms)',
                            icon: Icons.speed_outlined,
                            minValue: 500,
                            enabled: _sensorsEnabled,
                            // onSaved no necesario aquí porque usamos controller
                          ),
                      ),
                    ),
                    const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // CORRECCIÓN: Eliminada la definición duplicada de _buildNumberInput

  // Input numérico reutilizable (Definición única y correcta)
   Widget _buildNumberInput({
       required String labelText,
       required IconData icon,
       int minValue = 0,
       bool enabled = true,
       TextEditingController? controller, // Parámetro nombrado opcional
       String? initialValue,
       FormFieldSetter<String>? onSaved,
       Key? key, // Parámetro nombrado opcional para la key
   }) {
     return TextFormField(
       key: key, // Usar la key
       controller: controller, // Usar el controller
       initialValue: controller == null ? initialValue : null,
       decoration: InputDecoration(
           labelText: labelText,
           icon: Icon(icon, color: enabled ? AppColors.textSecondary : Colors.grey.shade400),
           suffixText: labelText.contains('(ms)') ? 'ms' : (labelText.contains('(s)') ? 's' : ''),
           border: const OutlineInputBorder(),
           filled: true,
           fillColor: enabled ? AppColors.background : Colors.grey.shade200,
       ),
       keyboardType: TextInputType.number,
       inputFormatters: [FilteringTextInputFormatter.digitsOnly],
       enabled: enabled,
       validator: (value) {
         if (!enabled) return null;
         if (value == null || value.isEmpty) {
           // Simplificado: si está habilitado, no puede estar vacío
           return 'Valor requerido';
         }
         final number = int.tryParse(value);
         if (number == null) {
           return 'Número inválido';
         }
         if (number < minValue) {
           return 'Mínimo: $minValue';
         }
         return null;
       },
       onSaved: onSaved,
     );
   }
} // Fin _ProfileEditScreenState