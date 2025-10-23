// lib/bluetooth_control_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

import 'smart_home_state.dart';
import 'main.dart'; // Asegúrate de que los UUIDs globales estén aquí
import 'profile_model.dart'; // Importa el modelo de perfil
import 'profiles_screen.dart'; // Importa la pantalla de perfiles

class BluetoothControlScreen extends StatefulWidget {
  const BluetoothControlScreen({super.key});

  @override
  State<BluetoothControlScreen> createState() => _BluetoothControlScreenState();
}

class _BluetoothControlScreenState extends State<BluetoothControlScreen> {

  BluetoothDevice? _targetDevice;
  BluetoothCharacteristic? _ledCharacteristic;
  BluetoothCharacteristic? _sensorCharacteristic;
  // --- Añadido para Perfiles ---
  final Guid PROFILE_CONFIG_UUID = Guid("c1d2e3f4-a5b6-c7d8-e9f0-a1b2c3d4e5f6");
  BluetoothCharacteristic? _profileConfigCharacteristic;
  // ---------------------------

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription? _sensorDataSubscription;
  bool _isScanning = false;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _sensorDataSubscription?.cancel();
    _targetDevice?.disconnect();
    super.dispose();
  }

  // Helper para acceder al estado
  SmartHomeState get state => Provider.of<SmartHomeState>(context, listen: false);

  // --- Lógica Bluetooth ---

  void _startScan() {
    setState(() => _isScanning = true);
    state.setStatusMessage("Buscando '${TARGET_DEVICE_NAME}'...");
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.platformName == TARGET_DEVICE_NAME) {
          _targetDevice = r.device;
          _stopScan();
          _connectToDevice();
          break;
        }
      }
    });
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel(); // Cancela la suscripción aquí también
    setState(() => _isScanning = false);
    if (_targetDevice == null) {
      state.setStatusMessage("Dispositivo no encontrado.");
    }
  }

  Future<void> _connectToDevice() async {
    if (_targetDevice == null) return;
    state.setStatusMessage("Conectando...");
    _connectionStateSubscription = _targetDevice!.connectionState.listen((status) {
      if (status == BluetoothConnectionState.connected) {
        state.updateConnectionState(true);
        _discoverServices();
      } else if (status == BluetoothConnectionState.disconnected) {
        state.updateConnectionState(false);
        _ledCharacteristic = null;
        _sensorCharacteristic = null;
        _profileConfigCharacteristic = null; // Limpia la característica de perfil
        _sensorDataSubscription?.cancel();
        state.setActiveProfile(null); // Desactiva perfil al desconectar
      }
    });
    try {
      await _targetDevice!.connect(timeout: const Duration(seconds: 15));
    } catch (e) {
      _showErrorDialog("Error de Conexión", "No se pudo conectar: $e");
      state.setStatusMessage("Fallo al conectar.");
    }
  }

  void _disconnectFromDevice() {
    _sensorDataSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _targetDevice?.disconnect();
    // El listener en _connectToDevice manejará la actualización del estado
  }

  Future<void> _discoverServices() async {
    if (_targetDevice == null) return;
    state.setStatusMessage("Descubriendo servicios...");
    try {
      List<BluetoothService> services = await _targetDevice!.discoverServices();
      for (var service in services) {
        if (service.uuid == SERVICE_UUID) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid == LED_CHARACTERISTIC_UUID) {
              _ledCharacteristic = characteristic;
            }
            if (characteristic.uuid == SENSOR_CHARACTERISTIC_UUID) {
              _sensorCharacteristic = characteristic;
              await _sensorCharacteristic!.setNotifyValue(true);
              _sensorDataSubscription = _sensorCharacteristic!.lastValueStream.listen((value) {
                // Solo procesa si los sensores están habilitados por perfil o no hay perfil activo
                if (state.activeProfile?.sensorsEnabled ?? true) {
                  String data = String.fromCharCodes(value);
                  List<String> parts = data.split(',');
                  if (parts.length == 3) {
                    try {
                      double temp = double.parse(parts[0]);
                      double hum = double.parse(parts[1]);
                      double light = double.parse(parts[2]);
                      state.updateSensorReadings(temp, hum, light);
                    } catch (e) {
                      debugPrint("Error al parsear datos del sensor: $e");
                    }
                  }
                }
              });
            }
            // --- Encuentra la característica de perfil ---
            if (characteristic.uuid == PROFILE_CONFIG_UUID) {
              _profileConfigCharacteristic = characteristic;
            }
            // ----------------------------------------
          }
        }
      }
      if (_ledCharacteristic != null && _sensorCharacteristic != null && _profileConfigCharacteristic != null) {
        state.setStatusMessage("¡Dispositivo listo!");
        // Si hay un perfil activo al conectar, enviarlo
        if (state.activeProfile != null) {
           _sendProfileToDevice(state.activeProfile!);
        }
      } else {
        String missing = "";
        if (_ledCharacteristic == null) missing += " LED,";
        if (_sensorCharacteristic == null) missing += " Sensor,";
        if (_profileConfigCharacteristic == null) missing += " Perfil,";
        state.setStatusMessage("Error: Faltan características:$missing");
      }
    } catch (e) {
      _showErrorDialog("Error", "No se pudieron descubrir los servicios: $e");
    }
  }

  // Escribe al LED (solo si no hay perfil de intervalo activo)
  Future<void> _writeToLedCharacteristic(String value) async {
    // Verifica si hay un perfil activo y si este deshabilita el control manual
    bool manualControlDisabled = state.activeProfile != null &&
                                 state.activeProfile!.lightsEnabled &&
                                 (state.activeProfile!.lightOnInterval > 0 || state.activeProfile!.lightOffInterval > 0);

    if (manualControlDisabled) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Control manual de luz desactivado por perfil activo.'))
      );
      return;
    }

    if (_ledCharacteristic == null) return;
    try {
      await _ledCharacteristic!.write(value.codeUnits);
      state.setLedState(value == "1");
    } catch (e) {
      _showErrorDialog("Error", "No se pudo enviar el comando: $e");
    }
  }

  // --- Nueva función para enviar el perfil al ESP32 ---
  Future<void> _sendProfileToDevice(UserProfile profile) async {
    if (_profileConfigCharacteristic == null) {
       _showErrorDialog("Error", "Característica de perfil no encontrada.");
      return;
    }
    if (!state.isConnected) {
       _showErrorDialog("Error", "Dispositivo no conectado.");
      return;
    }

    // Formato: "luces,enabled,on_ms,off_ms|sensores,enabled,interval_ms"
    String command = "luces,${profile.lightsEnabled ? 1:0},${profile.lightOnInterval},${profile.lightOffInterval}|" +
                     "sensores,${profile.sensorsEnabled ? 1:0},${profile.sensorReadInterval}";

    debugPrint("Enviando perfil: $command"); // Para depuración

    try {
      await _profileConfigCharacteristic!.write(command.codeUnits, withoutResponse: false); // Usar `withoutResponse: false` si esperas confirmación
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Perfil "${profile.name}" aplicado.'))
      );
      // Actualiza el estado activo en SmartHomeState si aún no lo está
      if (state.activeProfile?.name != profile.name) {
          state.setActiveProfile(profile);
      }
    } catch (e) {
      _showErrorDialog("Error", "No se pudo enviar el perfil: $e");
    }
  }
  // ----------------------------------------------------

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text("OK"),
            onPressed: () => Navigator.of(ctx).pop(),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Usamos Consumer para reconstruir partes específicas cuando cambie el estado
    return Consumer<SmartHomeState>(
      builder: (context, homeState, child) {
        // Verifica si el perfil activo ha cambiado y necesita ser enviado
        // Usamos addPostFrameCallback para evitar llamar setState durante el build
        WidgetsBinding.instance.addPostFrameCallback((_) {
            if (homeState.isConnected && homeState.activeProfile != null && _profileConfigCharacteristic != null) {
              // Comprueba si este perfil ya fue enviado o si necesita ser enviado
              // (Podrías añadir una variable de estado para rastrear esto si es necesario)
              // Por ahora, lo enviaremos si hay un perfil activo
              // _sendProfileToDevice(homeState.activeProfile!); // Cuidado: Esto podría enviarse repetidamente.
              // Mejor manejar el envío solo cuando se *selecciona* el perfil.
            }
        });

        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text("Panel de Control"),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            centerTitle: true,
            // --- Botón para ir a la pantalla de perfiles ---
            actions: [
              IconButton(
                icon: const Icon(Icons.person_outline), // Icono de perfiles
                tooltip: "Gestionar Perfiles",
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (ctx) => const ProfilesScreen()),
                  ).then((selectedProfile) {
                      // Cuando volvemos de la pantalla de perfiles,
                      // comprobamos si se seleccionó un perfil y lo enviamos
                      if (selectedProfile is UserProfile) {
                          _sendProfileToDevice(selectedProfile);
                      }
                  });
                },
              )
            ],
            // --------------------------------------------------
          ),
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: <Widget>[
              _buildStatusCard(homeState), // Pasamos el estado
              const SizedBox(height: 20),

              const Text("Controles", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _buildLightControlCard(homeState), // Pasamos el estado
                ],
              ),

              const SizedBox(height: 20),

              const Text("Sensores Ambientales", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              // Muestra los sensores solo si está conectado Y
              // (no hay perfil activo O el perfil activo los habilita)
              if (homeState.isConnected && (homeState.activeProfile?.sensorsEnabled ?? true))
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.85,
                  children: [
                    _buildSensorGauge("Temperatura", homeState.temperature, "°C", 0, 50, Colors.redAccent),
                    _buildSensorGauge("Humedad", homeState.humidity, "%", 0, 100, Colors.blueAccent),
                    _buildSensorGauge("Luz", homeState.lightLevel, "", 0, 4095, Colors.amber),
                  ],
                )
              else
                 // Muestra un placeholder diferente si los sensores están desactivados por perfil
                _buildSensorPlaceholder(homeState.isConnected, homeState.activeProfile?.sensorsEnabled ?? true),

            ],
          ),
        );
      },
    );
  }

  // --- Widgets Auxiliares ---

  // Modificado para mostrar el perfil activo
  Widget _buildStatusCard(SmartHomeState homeState) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  homeState.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                  size: 30,
                  color: homeState.isConnected ? Colors.indigo : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    homeState.statusMessage,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
             // --- Muestra el nombre del perfil activo ---
            if (homeState.activeProfile != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                     const Icon(Icons.label_important_outline, size: 18, color: Colors.indigo),
                     const SizedBox(width: 5),
                     Text(
                      'Perfil Activo: ${homeState.activeProfile!.name}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo, fontSize: 16),
                    ),
                  ],
                ),
              ),
            // ------------------------------------------
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: homeState.isConnected ? _disconnectFromDevice : _startScan,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isScanning ? Colors.grey : (homeState.isConnected ? Colors.redAccent : Colors.indigo),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size(200, 45)
              ),
              child: _isScanning
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                  : Text(homeState.isConnected ? "Desconectar" : "Buscar Dispositivo"),
            ),
          ],
        ),
      ),
    );
  }

  // Modificado para considerar el perfil activo
  Widget _buildLightControlCard(SmartHomeState homeState) {
    bool isConnected = homeState.isConnected;
    bool profileActive = homeState.activeProfile != null;
    bool lightsEnabledByProfile = profileActive ? homeState.activeProfile!.lightsEnabled : true;
    bool intervalMode = profileActive && lightsEnabledByProfile && (homeState.activeProfile!.lightOnInterval > 0 || homeState.activeProfile!.lightOffInterval > 0);
    bool manualControlAllowed = isConnected && lightsEnabledByProfile && !intervalMode;
    bool isOn = homeState.ledIsOn; // Mantenemos el estado actual del LED

    // Colores dinámicos según el estado
    Color cardColor = isConnected ? (lightsEnabledByProfile ? (isOn ? Colors.amber.shade100 : Colors.white) : Colors.grey.shade300) : Colors.grey.shade200;
    Color contentColor = isConnected ? (lightsEnabledByProfile ? (isOn ? Colors.amber.shade800 : Colors.grey.shade600) : Colors.grey.shade400) : Colors.grey.shade400;
    IconData iconData = lightsEnabledByProfile
    ? (isOn ? Icons.lightbulb : Icons.lightbulb_outline) // Si está habilitado: encendido o apagado
    : Icons.lightbulb_outline; // Si está deshabilitado por perfil: usa el icono de apagado

    String statusText;
    if (!isConnected) {
      statusText = "Desconectado";
    } else if (!lightsEnabledByProfile) {
      statusText = "Deshab. (Perfil)";
    } else if (intervalMode) {
      statusText = "Auto (Perfil)";
    } else {
      statusText = isOn ? "Encendida" : "Apagada";
    }

    return Card(
      elevation: 4,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: manualControlAllowed
            ? () => _writeToLedCharacteristic(isOn ? "0" : "1")
            : null, // Deshabilitado si no está conectado, perfil lo deshabilita o está en modo intervalo
        borderRadius: BorderRadius.circular(15),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(iconData, size: 40, color: contentColor),
            const SizedBox(height: 8),
            Text(
              "Luz",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: contentColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              statusText,
              style: TextStyle(fontSize: 14, color: contentColor.withOpacity(0.8)),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildSensorGauge(String title, double value, String unit, double min, double max, Color color) {
    // Si el valor es NaN (Not a Number), muestra el mínimo para evitar errores en el gauge
    double displayValue = value.isNaN ? min : value;
     // Invierte el valor de luz para la visualización (0 = max luz, 4095 = min luz)
    if (title == "Luz") {
        displayValue = max - displayValue;
        // Asegúrate de que no sea negativo después de invertir
        if (displayValue < min) displayValue = min;
    }


    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Expanded(
              child: SfRadialGauge(
                axes: <RadialAxis>[
                  RadialAxis(
                    minimum: min,
                    maximum: max,
                    showLabels: false,
                    showTicks: false,
                    axisLineStyle: const AxisLineStyle(
                      thickness: 0.2,
                      cornerStyle: CornerStyle.bothCurve,
                      color: Color.fromARGB(255, 224, 224, 224),
                      thicknessUnit: GaugeSizeUnit.factor,
                    ),
                    pointers: <GaugePointer>[
                      RangePointer(
                        value: displayValue, // Usa el valor ajustado
                        cornerStyle: CornerStyle.bothCurve,
                        width: 0.2,
                        sizeUnit: GaugeSizeUnit.factor,
                        color: color,
                        enableAnimation: true, // Añade una animación suave
                        animationDuration: 1000,
                        animationType: AnimationType.linear,
                      )
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                        positionFactor: 0.1,
                        angle: 90,
                        widget: Text(
                          // Muestra "--" si el valor original era NaN
                          value.isNaN ? "-- $unit" : "${displayValue.toStringAsFixed(title == "Luz" ? 0 : 1)} $unit",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      )
                    ],
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

 // Placeholder mejorado para sensores
  Widget _buildSensorPlaceholder(bool isConnected, bool sensorsEnabled) {
    String message;
    IconData icon;
    if (!isConnected) {
      message = "Conecta un dispositivo para ver los datos de los sensores";
      icon = Icons.bluetooth_disabled;
    } else if (!sensorsEnabled) {
       message = "Sensores deshabilitados por el perfil activo";
       icon = Icons.sensors_off;
    } else {
       message = "Esperando datos de los sensores..."; // Caso intermedio
       icon = Icons.sensors;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container( // Usamos Container para centrar mejor
        height: 200, // Ajusta la altura si es necesario
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
             mainAxisAlignment: MainAxisAlignment.center,
             children: [
               Icon(icon, size: 40, color: Colors.grey),
               const SizedBox(height: 10),
               Text(
                 message,
                 textAlign: TextAlign.center,
                 style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ]
          ),
        ),
      ),
    );
  }
}