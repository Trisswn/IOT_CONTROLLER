// lib/profile_edit_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'smart_home_state.dart';
import 'profile_model.dart';

class ProfileEditScreen extends StatefulWidget {
  final int? profileIndex; // Opcional, para editar un perfil existente

  const ProfileEditScreen({Key? key, this.profileIndex}) : super(key: key);

  @override
  _ProfileEditScreenState createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late bool _lightsEnabled;
  late int _lightOnInterval;
  late int _lightOffInterval;
  late bool _sensorsEnabled;
  late int _sensorReadInterval;
  
  @override
  void initState() {
    super.initState();
    final state = Provider.of<SmartHomeState>(context, listen: false);
    if (widget.profileIndex != null) {
      final profile = state.profiles[widget.profileIndex!];
      _name = profile.name;
      _lightsEnabled = profile.lightsEnabled;
      _lightOnInterval = profile.lightOnInterval;
      _lightOffInterval = profile.lightOffInterval;
      _sensorsEnabled = profile.sensorsEnabled;
      _sensorReadInterval = profile.sensorReadInterval;
    } else {
      // Valores por defecto para un nuevo perfil
      _name = '';
      _lightsEnabled = true;
      _lightOnInterval = 0;
      _lightOffInterval = 0;
      _sensorsEnabled = true;
      _sensorReadInterval = 2000;
    }
  }

  void _saveForm() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final newProfile = UserProfile(
        name: _name,
        lightsEnabled: _lightsEnabled,
        lightOnInterval: _lightOnInterval,
        lightOffInterval: _lightOffInterval,
        sensorsEnabled: _sensorsEnabled,
        sensorReadInterval: _sensorReadInterval,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.profileIndex == null ? 'Nuevo Perfil' : 'Editar Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveForm,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            TextFormField(
              initialValue: _name,
              decoration: const InputDecoration(labelText: 'Nombre del Perfil'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Por favor, introduce un nombre.';
                }
                return null;
              },
              onSaved: (value) => _name = value!,
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text('Control de Luces'),
              value: _lightsEnabled,
              onChanged: (val) => setState(() => _lightsEnabled = val),
            ),
            if (_lightsEnabled) ...[
              TextFormField(
                initialValue: _lightOnInterval.toString(),
                decoration: const InputDecoration(labelText: 'Intervalo Encendido (ms)'),
                keyboardType: TextInputType.number,
                onSaved: (value) => _lightOnInterval = int.tryParse(value!) ?? 0,
              ),
              TextFormField(
                initialValue: _lightOffInterval.toString(),
                decoration: const InputDecoration(labelText: 'Intervalo Apagado (ms)'),
                keyboardType: TextInputType.number,
                onSaved: (value) => _lightOffInterval = int.tryParse(value!) ?? 0,
              ),
            ],
            const SizedBox(height: 20),
             SwitchListTile(
              title: const Text('Monitoreo de Sensores'),
              value: _sensorsEnabled,
              onChanged: (val) => setState(() => _sensorsEnabled = val),
            ),
             if (_sensorsEnabled) ...[
              TextFormField(
                initialValue: _sensorReadInterval.toString(),
                decoration: const InputDecoration(labelText: 'Intervalo de Lectura de Sensor (ms)'),
                keyboardType: TextInputType.number,
                onSaved: (value) => _sensorReadInterval = int.tryParse(value!) ?? 2000,
              ),
            ]
          ],
        ),
      ),
    );
  }
}