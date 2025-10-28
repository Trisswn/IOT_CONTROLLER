// lib/profile_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'smart_home_state.dart';
import 'profile_model.dart';
import 'package:flutter/services.dart';
import 'app_colors.dart'; // <<< Importar colores

// Enum para los modos de luz
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
  late bool _lightsEnabled;
  late TextEditingController _lightOnIntervalController;
  late TextEditingController _lightOffIntervalController;
  late TextEditingController _autoOffDurationController;
  late bool _sensorsEnabled;
  late TextEditingController _sensorReadIntervalController;

  late LightMode _selectedLightMode; // Usaremos un enum para el modo

  @override
  void initState() {
    super.initState();
    final state = Provider.of<SmartHomeState>(context, listen: false);
    UserProfile profile;

    if (widget.profileIndex != null) {
      profile = state.profiles[widget.profileIndex!];
    } else {
      // Valores por defecto para un nuevo perfil
      profile = UserProfile(
          name: '',
          lightOnInterval: 0, // Manual por defecto
          lightOffInterval: 0,
          autoOffDuration: 0,
          sensorReadInterval: 2000 // Intervalo de sensor por defecto
      );
    }

    _nameController = TextEditingController(text: profile.name);
    _lightsEnabled = profile.lightsEnabled;
    _lightOnIntervalController = TextEditingController(text: profile.lightOnInterval.toString());
    _lightOffIntervalController = TextEditingController(text: profile.lightOffInterval.toString());
    _autoOffDurationController = TextEditingController(text: profile.autoOffDuration.toString());
    _sensorsEnabled = profile.sensorsEnabled;
    _sensorReadIntervalController = TextEditingController(text: profile.sensorReadInterval.toString());

    // Determinar el modo de luz inicial
    if (profile.isBlinkingMode) {
      _selectedLightMode = LightMode.blink;
    } else if (profile.isAutoOffMode) {
      _selectedLightMode = LightMode.autoOff;
    } else {
      _selectedLightMode = LightMode.manual;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _lightOnIntervalController.dispose();
    _lightOffIntervalController.dispose();
    _autoOffDurationController.dispose();
    _sensorReadIntervalController.dispose();
    super.dispose();
  }

  void _saveForm() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      final name = _nameController.text;

      int lightOnInterval = 0;
      int lightOffInterval = 0;
      int autoOffDuration = 0;
      int sensorReadInterval = 2000; // Valor por defecto

      if (_lightsEnabled) {
        switch (_selectedLightMode) {
          case LightMode.blink:
            lightOnInterval = int.tryParse(_lightOnIntervalController.text) ?? 1000;
            lightOffInterval = int.tryParse(_lightOffIntervalController.text) ?? 1000;
            autoOffDuration = 0; // Asegura que autoOff sea 0 en modo parpadeo
            break;
          case LightMode.autoOff:
            autoOffDuration = int.tryParse(_autoOffDurationController.text) ?? 60;
            lightOnInterval = 0; // Asegura que los intervalos sean 0
            lightOffInterval = 0;
            break;
          case LightMode.manual:
            // Todos los intervalos ya son 0 por defecto
            break;
        }
      }

       if (_sensorsEnabled) {
         sensorReadInterval = int.tryParse(_sensorReadIntervalController.text) ?? 2000;
       }


      final newProfile = UserProfile(
        name: name,
        lightsEnabled: _lightsEnabled,
        lightOnInterval: lightOnInterval,
        lightOffInterval: lightOffInterval,
        autoOffDuration: autoOffDuration,
        sensorsEnabled: _sensorsEnabled,
        sensorReadInterval: sensorReadInterval,
      );

      final state = Provider.of<SmartHomeState>(context, listen: false);
      if (widget.profileIndex != null) {
        state.updateProfile(widget.profileIndex!, newProfile);
      } else {
        state.addProfile(newProfile);
      }
      Navigator.of(context).pop();
    }
  }

  // Helper para construir secciones dentro de las tarjetas
  Widget _buildSectionHeader(String title, IconData icon) {
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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profileIndex == null ? 'Nuevo Perfil' : 'Editar Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined), // Icono actualizado
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
                     border: OutlineInputBorder(), // Estilo de borde
                     filled: true, // Fondo relleno
                     fillColor: AppColors.background, // Color de fondo sutil
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, introduce un nombre.';
                    }
                    final state = Provider.of<SmartHomeState>(context, listen: false);
                    // Comprueba si el nombre ya existe en OTRO perfil
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

            // --- Tarjeta Configuración LED ---
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionHeader('Configuración LED', Icons.lightbulb_outline),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Habilitar control LED', style: textTheme.bodyLarge),
                        Switch(
                          value: _lightsEnabled,
                          onChanged: (val) => setState(() => _lightsEnabled = val),
                          activeColor: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                  // Mostrar opciones solo si el LED está habilitado
                  if (_lightsEnabled) ...[
                    const Divider(height: 20, indent: 16, endIndent: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Text("Modo de Operación:", style: textTheme.titleSmall?.copyWith(color: AppColors.textSecondary)),
                    ),
                    // Usamos SegmentedButton para seleccionar el modo
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: SegmentedButton<LightMode>(
                        segments: const <ButtonSegment<LightMode>>[
                          ButtonSegment<LightMode>(value: LightMode.manual, label: Text('Manual'), icon: Icon(Icons.touch_app_outlined)),
                          ButtonSegment<LightMode>(value: LightMode.blink, label: Text('Parpadeo'), icon: Icon(Icons.wb_incandescent_outlined)),
                          ButtonSegment<LightMode>(value: LightMode.autoOff, label: Text('Auto Off'), icon: Icon(Icons.timer_outlined)),
                        ],
                        selected: {_selectedLightMode},
                        onSelectionChanged: (Set<LightMode> newSelection) {
                          setState(() {
                            _selectedLightMode = newSelection.first;
                            // Ajustar valores por defecto al cambiar modo
                            if (_selectedLightMode == LightMode.blink) {
                               if (_lightOnIntervalController.text == '0') _lightOnIntervalController.text = '1000';
                               if (_lightOffIntervalController.text == '0') _lightOffIntervalController.text = '1000';
                               _autoOffDurationController.text = '0'; // Asegura que auto-off sea 0
                            } else if (_selectedLightMode == LightMode.autoOff) {
                               if (_autoOffDurationController.text == '0') _autoOffDurationController.text = '60';
                               _lightOnIntervalController.text = '0'; // Asegura que parpadeo sea 0
                               _lightOffIntervalController.text = '0';
                            } else { // Manual
                               _lightOnIntervalController.text = '0';
                               _lightOffIntervalController.text = '0';
                               _autoOffDurationController.text = '0';
                            }
                          });
                        },
                        style: SegmentedButton.styleFrom(
                           selectedBackgroundColor: AppColors.primary.withOpacity(0.2),
                           selectedForegroundColor: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    // Campos condicionales según el modo seleccionado
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Column(
                        children: [
                          if (_selectedLightMode == LightMode.blink)
                            Row(
                              children: [
                                Expanded(
                                  child: _buildNumberInput(
                                    controller: _lightOnIntervalController,
                                    labelText: 'Encendido (ms)',
                                    icon: Icons.timer,
                                    minValue: 50, // Mínimo razonable
                                    enabled: _lightsEnabled,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _buildNumberInput(
                                    controller: _lightOffIntervalController,
                                    labelText: 'Apagado (ms)',
                                    icon: Icons.timer_off_outlined,
                                    minValue: 50,
                                    enabled: _lightsEnabled,
                                  ),
                                ),
                              ],
                            ),
                           if (_selectedLightMode == LightMode.autoOff)
                             _buildNumberInput(
                              controller: _autoOffDurationController,
                              labelText: 'Apagar después de (segundos)',
                              icon: Icons.hourglass_bottom,
                              minValue: 1,
                              enabled: _lightsEnabled,
                             ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8), // Espacio al final de la tarjeta
                ],
              ),
            ),
            const SizedBox(height: 20),

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
                          Text('Habilitar lectura sensores', style: textTheme.bodyLarge),
                          Switch(
                            value: _sensorsEnabled,
                            onChanged: (val) => setState(() => _sensorsEnabled = val),
                             activeColor: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                   // Campo de intervalo visible solo si los sensores están habilitados
                   AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: EdgeInsets.fromLTRB(16.0, _sensorsEnabled ? 16.0 : 0.0, 16.0, _sensorsEnabled ? 16.0 : 0.0),
                      constraints: BoxConstraints(maxHeight: _sensorsEnabled ? 100 : 0), // Anima la altura
                      child: Opacity( // Anima la opacidad
                          opacity: _sensorsEnabled ? 1.0 : 0.0,
                          child: _buildNumberInput(
                            controller: _sensorReadIntervalController,
                            labelText: 'Intervalo Lectura (ms)',
                            icon: Icons.speed_outlined,
                            minValue: 500, // Mínimo razonable
                            enabled: _sensorsEnabled,
                          ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget de input numérico reutilizable con mejor estilo
  Widget _buildNumberInput({
      required TextEditingController controller,
      required String labelText,
      required IconData icon,
      int minValue = 0,
      bool enabled = true,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
          labelText: labelText,
          icon: Icon(icon, color: enabled ? AppColors.textSecondary : Colors.grey.shade400),
          suffixText: labelText.contains('(ms)') ? 'ms' : (labelText.contains('(segundos)') ? 's' : ''),
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: enabled ? AppColors.background : Colors.grey.shade200, // Fondo diferente si está deshabilitado
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      enabled: enabled, // Habilita/deshabilita el campo
      validator: (value) {
        // Solo valida si el campo está habilitado
        if (!enabled) return null;

        if (value == null || value.isEmpty) {
          // Requiere valor solo si el modo correspondiente está activo
           bool required = false;
           if (labelText.contains('Encendido') || labelText.contains('Apagado')) {
             required = (_selectedLightMode == LightMode.blink);
           } else if (labelText.contains('Apagar después')) {
             required = (_selectedLightMode == LightMode.autoOff);
           } else if (labelText.contains('Intervalo Lectura')) {
             required = _sensorsEnabled;
           }
           return required ? 'Valor requerido' : null;
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
       onChanged: (_) => _formKey.currentState?.validate(), // Revalida al cambiar
    );
  }
}