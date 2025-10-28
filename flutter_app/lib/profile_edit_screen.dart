// lib/profile_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'smart_home_state.dart';
import 'profile_model.dart';
import 'package:flutter/services.dart';

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

  bool _isBlinking = false;
  bool _isAutoOff = false;

  @override
  void initState() {
    super.initState();
    final state = Provider.of<SmartHomeState>(context, listen: false);
    UserProfile profile;

    if (widget.profileIndex != null) {
      profile = state.profiles[widget.profileIndex!];
    } else {
      profile = UserProfile(name: '');
    }

    _nameController = TextEditingController(text: profile.name);
    _lightsEnabled = profile.lightsEnabled;
    _lightOnIntervalController = TextEditingController(text: profile.lightOnInterval.toString());
    _lightOffIntervalController = TextEditingController(text: profile.lightOffInterval.toString());
    _autoOffDurationController = TextEditingController(text: profile.autoOffDuration.toString());
    _sensorsEnabled = profile.sensorsEnabled;
    _sensorReadIntervalController = TextEditingController(text: profile.sensorReadInterval.toString());

    _updateLightModes(profile.lightOnInterval, profile.lightOffInterval, profile.autoOffDuration);
  }

  void _updateLightModes(int onInterval, int offInterval, int autoOff) {
     _isBlinking = onInterval > 0 && offInterval > 0;
     _isAutoOff = autoOff > 0 && !_isBlinking;
     if (_isBlinking) {
       _autoOffDurationController.text = '0';
     }
     if (_isAutoOff) {
       _lightOnIntervalController.text = '0';
       _lightOffIntervalController.text = '0';
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
      
      // ✅ CORRECCIÓN CRÍTICA: Asegurar que los valores sean 0 cuando no están en uso
      int lightOnInterval = 0;
      int lightOffInterval = 0;
      int autoOffDuration = 0;
      
      if (_lightsEnabled) {
        if (_isBlinking) {
          // Solo parpadeo
          lightOnInterval = int.tryParse(_lightOnIntervalController.text) ?? 0;
          lightOffInterval = int.tryParse(_lightOffIntervalController.text) ?? 0;
          autoOffDuration = 0; // ⭐ Importante: asegurar que sea 0
        } else if (_isAutoOff) {
          // Solo auto-apagado
          lightOnInterval = 0; // ⭐ Importante: asegurar que sea 0
          lightOffInterval = 0; // ⭐ Importante: asegurar que sea 0
          autoOffDuration = int.tryParse(_autoOffDurationController.text) ?? 0;
        }
        // Si no es ninguno, todos quedan en 0 (control manual)
      }
      
      final sensorReadInterval = int.tryParse(_sensorReadIntervalController.text) ?? 2000;

      final newProfile = UserProfile(
        name: name,
        lightsEnabled: _lightsEnabled,
        lightOnInterval: lightOnInterval,
        lightOffInterval: lightOffInterval,
        autoOffDuration: autoOffDuration,
        sensorsEnabled: _sensorsEnabled,
        sensorReadInterval: sensorReadInterval,
      );

      // ✅ DEBUG: Imprimir el perfil antes de guardar
      debugPrint("📝 Guardando perfil:");
      debugPrint("  Nombre: $name");
      debugPrint("  Luces habilitadas: $_lightsEnabled");
      debugPrint("  ON interval: $lightOnInterval ms");
      debugPrint("  OFF interval: $lightOffInterval ms");
      debugPrint("  Auto-off: $autoOffDuration s");
      debugPrint("  Modo parpadeo: ${newProfile.isBlinkingMode}");
      debugPrint("  Modo auto-off: ${newProfile.isAutoOffMode}");
      debugPrint("  Modo manual: ${newProfile.allowManualLightControl}");

      final state = Provider.of<SmartHomeState>(context, listen: false);
      if (widget.profileIndex != null) {
        state.updateProfile(widget.profileIndex!, newProfile);
      } else {
        state.addProfile(newProfile);
      }
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profileIndex == null ? 'Nuevo Perfil' : 'Editar Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
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
            // --- Tarjeta de Información General ---
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del Perfil',
                    icon: Icon(Icons.label),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor, introduce un nombre.';
                    }
                    final state = Provider.of<SmartHomeState>(context, listen: false);
                    bool nameExists = state.profiles.any((p) => p.name == value && state.profiles.indexOf(p) != widget.profileIndex);
                    if (nameExists) {
                      return 'Este nombre de perfil ya existe.';
                    }
                    return null;
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),

            // --- Tarjeta de Configuración de Luces ---
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: const Text('Gestión de Luces'),
                      value: _lightsEnabled,
                      secondary: const Icon(Icons.lightbulb_outline),
                      onChanged: (val) => setState(() => _lightsEnabled = val),
                    ),
                    if (_lightsEnabled) ...[
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Text("Modo de Operación:", style: Theme.of(context).textTheme.titleMedium),
                      ),
                      
                      // ✅ Control Manual
                      RadioListTile<String>(
                        title: const Text('Control Manual'),
                        subtitle: const Text('Encender/apagar manualmente'),
                        value: 'manual',
                        groupValue: _isBlinking ? 'blink' : (_isAutoOff ? 'autooff' : 'manual'),
                        onChanged: (val) {
                          setState(() {
                            _isBlinking = false;
                            _isAutoOff = false;
                            _lightOnIntervalController.text = '0';
                            _lightOffIntervalController.text = '0';
                            _autoOffDurationController.text = '0';
                          });
                        },
                      ),
                      
                      // ✅ Parpadeo
                      RadioListTile<String>(
                        title: const Text('Parpadeo Automático'),
                        subtitle: const Text('LED parpadeará continuamente'),
                        value: 'blink',
                        groupValue: _isBlinking ? 'blink' : (_isAutoOff ? 'autooff' : 'manual'),
                        onChanged: (val) {
                          setState(() {
                            _isBlinking = true;
                            _isAutoOff = false;
                            _autoOffDurationController.text = '0';
                            if (_lightOnIntervalController.text == '0') _lightOnIntervalController.text = '1000';
                            if (_lightOffIntervalController.text == '0') _lightOffIntervalController.text = '1000';
                          });
                        },
                      ),
                      
                      if (_isBlinking)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: _buildNumberInput(
                                  controller: _lightOnIntervalController,
                                  labelText: 'Encendido (ms)',
                                  minValue: 100,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _buildNumberInput(
                                  controller: _lightOffIntervalController,
                                  labelText: 'Apagado (ms)',
                                  minValue: 100,
                                ),
                              ),
                            ],
                          ),
                        ),
                      
                      // ✅ Auto-apagado
                      RadioListTile<String>(
                        title: const Text('Apagado Automático'),
                        subtitle: const Text('Encenderá y se apagará después de X segundos'),
                        value: 'autooff',
                        groupValue: _isBlinking ? 'blink' : (_isAutoOff ? 'autooff' : 'manual'),
                        onChanged: (val) {
                          setState(() {
                            _isAutoOff = true;
                            _isBlinking = false;
                            _lightOnIntervalController.text = '0';
                            _lightOffIntervalController.text = '0';
                            if (_autoOffDurationController.text == '0') _autoOffDurationController.text = '60';
                          });
                        },
                      ),
                      
                      if (_isAutoOff)
                         Padding(
                           padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                           child: _buildNumberInput(
                            controller: _autoOffDurationController,
                            labelText: 'Apagar después de (segundos)',
                            minValue: 1,
                           ),
                         ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // --- Tarjeta de Configuración de Sensores ---
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('Monitoreo de Sensores'),
                      value: _sensorsEnabled,
                      secondary: const Icon(Icons.sensors),
                      onChanged: (val) => setState(() => _sensorsEnabled = val),
                    ),
                    if (_sensorsEnabled) ...[
                       const Divider(),
                       Padding(
                         padding: const EdgeInsets.all(16.0),
                         child: _buildNumberInput(
                          controller: _sensorReadIntervalController,
                          labelText: 'Intervalo Lectura (ms)',
                          minValue: 500,
                         ),
                       ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberInput({
      required TextEditingController controller,
      required String labelText,
      int minValue = 0
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
          labelText: labelText,
          suffixText: labelText.contains('(ms)') ? 'ms' : (labelText.contains('(segundos)') ? 's' : ''),
          border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (value) {
        if (value == null || value.isEmpty) {
          if (labelText.contains('Encendido') || labelText.contains('Apagado')) {
             if (_isBlinking) return 'Valor requerido';
          } else if (labelText.contains('Apagar después')) {
             if (_isAutoOff) return 'Valor requerido';
          } else if (labelText.contains('Intervalo Lectura')) {
             if (_sensorsEnabled) return 'Valor requerido';
          }
          return null;
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
    );
  }
}