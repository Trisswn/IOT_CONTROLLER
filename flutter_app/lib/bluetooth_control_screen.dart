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
import 'app_colors.dart'; // Importar nuestros colores

class BluetoothControlScreen extends StatefulWidget {
  const BluetoothControlScreen({super.key});

  @override
  State<BluetoothControlScreen> createState() => _BluetoothControlScreenState();
}

class _BluetoothControlScreenState extends State<BluetoothControlScreen> {
  // --- Variables Bluetooth (sin cambios) ---
  BluetoothDevice? _targetDevice;
  BluetoothCharacteristic? _ledCharacteristic;
  BluetoothCharacteristic? _sensorCharacteristic;
  BluetoothCharacteristic? _profileConfigCharacteristic;

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<int>>? _sensorDataSubscription;
  StreamSubscription<List<int>>? _ledStateSubscription;
  bool _isScanning = false;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _sensorDataSubscription?.cancel();
    _ledStateSubscription?.cancel();
    try {
     _targetDevice?.disconnect();
    } catch (e) {
      debugPrint("Error al desconectar en dispose: $e");
    }
    super.dispose();
  }

  // Helper para acceder al estado
  SmartHomeState get state => Provider.of<SmartHomeState>(context, listen: false);

  // --- Lógica Bluetooth (sin cambios funcionales) ---
  // Se mantienen las funciones:
  // _startScan, _stopScan, _connectToDevice, _disconnectFromDevice,
  // _discoverServices, _writeToLedCharacteristic, _sendProfileToDevice,
  // _showErrorDialog

  void _startScan() {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    state.setStatusMessage("Buscando '${TARGET_DEVICE_NAME}'...");
    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        String deviceName = r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.localName;
        if (deviceName == TARGET_DEVICE_NAME) {
          _targetDevice = r.device;
          _stopScan();
          _connectToDevice();
          break;
        }
      }
    }, onError: (e) {
       debugPrint("Error en scan results: $e");
       _stopScan();
       state.setStatusMessage("Error al buscar.");
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15)).catchError((e){
       debugPrint("Error al iniciar scan: $e");
       _stopScan();
       state.setStatusMessage("Error al iniciar búsqueda.");
    });

     Future.delayed(const Duration(seconds: 16), () {
        if (_isScanning) {
          debugPrint("Scan timeout manual.");
          _stopScan();
        }
     });
  }

  void _stopScan() {
    if (_isScanning) {
      FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
       setState(() => _isScanning = false);
       if (_targetDevice == null) {
          state.setStatusMessage("Dispositivo no encontrado.");
       }
    }
  }

  Future<void> _connectToDevice() async {
    if (_targetDevice == null) return;
    state.setStatusMessage("Conectando a ${_targetDevice!.platformName}...");

    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = _targetDevice!.connectionState.listen((status) {
      debugPrint("Connection state update: $status");
      if (status == BluetoothConnectionState.connected) {
        state.updateConnectionState(true);
        state.setStatusMessage("Conectado. Descubriendo servicios...");
        _discoverServices();
      } else if (status == BluetoothConnectionState.disconnected) {
        state.updateConnectionState(false);
        _ledCharacteristic = null;
        _sensorCharacteristic = null;
        _profileConfigCharacteristic = null;
        _sensorDataSubscription?.cancel();
        _sensorDataSubscription = null;
        _ledStateSubscription?.cancel();
        _ledStateSubscription = null;
      }
    }, onError: (e) {
       debugPrint("Error en connection state listener: $e");
       state.updateConnectionState(false);
       state.setStatusMessage("Error de conexión.");
    });

    try {
      await _targetDevice!.connect(timeout: const Duration(seconds: 15));
      await _targetDevice!.requestMtu(256);
    } catch (e) {
      debugPrint("Error al conectar: $e");
      _showErrorDialog("Error de Conexión", "No se pudo conectar: ${e.toString()}");
      state.setStatusMessage("Fallo al conectar.");
      _connectionStateSubscription?.cancel();
      state.updateConnectionState(false);
    }
  }

  void _disconnectFromDevice() {
    _sensorDataSubscription?.cancel();
    _sensorDataSubscription = null;
    _ledStateSubscription?.cancel();
    _ledStateSubscription = null;
    _connectionStateSubscription?.cancel();
    _targetDevice?.disconnect();
     state.setStatusMessage("Desconectando...");
  }

  Future<void> _discoverServices() async {
    if (_targetDevice == null || !state.isConnected) return;
    state.setStatusMessage("Descubriendo servicios...");
    try {
      List<BluetoothService> services = await _targetDevice!.discoverServices();
      bool foundLed = false; bool foundSensor = false; bool foundProfile = false;

      _ledStateSubscription?.cancel();
      _ledStateSubscription = null;
      _sensorDataSubscription?.cancel();
      _sensorDataSubscription = null;

      for (var service in services) {
        if (service.uuid == SERVICE_UUID) {
          debugPrint("Servicio principal encontrado.");
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid == LED_CHARACTERISTIC_UUID) {
               _ledCharacteristic = characteristic; foundLed = true; debugPrint("Característica LED encontrada.");
              try {
                await _ledCharacteristic!.setNotifyValue(true);
                _ledStateSubscription = _ledCharacteristic!.lastValueStream.listen((value) {
                  if (value.isNotEmpty) {
                    String ledStateStr = String.fromCharCodes(value);
                    bool actualLedState = (ledStateStr == "1");
                    debugPrint("<<< Notificación LED recibida: ${actualLedState ? 'ON' : 'OFF'}");
                    if (mounted) {
                        state.setLedState(actualLedState);
                    }
                  }
                }, onError: (e) {
                  debugPrint("Error en LED stream: $e");
                });
                debugPrint("Suscripción a notificaciones LED activada.");
              } catch (e) {
                 debugPrint("Error al configurar notificaciones LED: $e");
                 _showErrorDialog("Error", "No se pudieron activar las notificaciones para el LED: ${e.toString()}");
              }
            }
            if (characteristic.uuid == SENSOR_CHARACTERISTIC_UUID) {
              _sensorCharacteristic = characteristic; foundSensor = true; debugPrint("Característica Sensor encontrada.");
              try {
                  await _sensorCharacteristic!.setNotifyValue(true);
                  _sensorDataSubscription = _sensorCharacteristic!.lastValueStream.listen((value) {
                    if (state.activeProfile?.sensorsEnabled ?? true) {
                      if (value.isEmpty) return;
                      try {
                        String data = String.fromCharCodes(value);
                        List<String> parts = data.split(',');
                        if (parts.length == 3) {
                          double temp = double.tryParse(parts[0]) ?? double.nan;
                          double hum = double.tryParse(parts[1]) ?? double.nan;
                          double light = double.tryParse(parts[2]) ?? double.nan;
                          if (mounted) {
                            state.updateSensorReadings(temp, hum, light);
                          }
                        } else { debugPrint("Datos sensor formato incorrecto: $data"); }
                      } catch (e) { debugPrint("Error al parsear datos del sensor: $e"); }
                    } else {
                       if (mounted) { state.updateSensorReadings(double.nan, double.nan, double.nan); }
                    }
                  }, onError: (e) { debugPrint("Error en sensor stream: $e"); });
                   debugPrint("Suscripción a notificaciones Sensor activada.");
              } catch(e) {
                  debugPrint("Error al configurar notificaciones Sensor: $e");
                  _showErrorDialog("Error", "No se pudieron activar las notificaciones para el Sensor: ${e.toString()}");
              }
            }
            if (characteristic.uuid == PROFILE_CONFIG_UUID) {
              _profileConfigCharacteristic = characteristic; foundProfile = true; debugPrint("Característica de Perfil encontrada!");
            }
          }
           break;
        }
      }

      if (foundLed && foundSensor && foundProfile) {
        state.setStatusMessage("¡Dispositivo listo!");
        if (state.activeProfile != null) {
          debugPrint("Enviando perfil activo al conectar...");
          await _sendProfileToDevice(state.activeProfile!);
        }
      } else {
        String missing = "";
        if (!foundLed) missing += " LED,";
        if (!foundSensor) missing += " Sensor,";
        if (!foundProfile) missing += " Perfil,";
        missing = missing.isNotEmpty ? missing.substring(0, missing.length - 1) : missing;
        state.setStatusMessage("Error: Faltan características: $missing");
        _showErrorDialog("Error de Servicio", "No se encontraron todas las características necesarias ($missing). Verifica el código del ESP32 y los UUIDs.");
         _disconnectFromDevice();
      }
    } catch (e) {
      debugPrint("Error al descubrir servicios: $e");
      _showErrorDialog("Error", "No se pudieron descubrir los servicios: ${e.toString()}");
      state.setStatusMessage("Error al descubrir servicios.");
      _disconnectFromDevice();
    }
  }

  Future<void> _writeToLedCharacteristic(String value) async {
    UserProfile? activeProfile = state.activeProfile;
    bool lightsFeatureEnabled = activeProfile?.lightsEnabled ?? true;
    bool isBlinking = activeProfile?.isBlinkingMode ?? false;
    bool allowWrite = lightsFeatureEnabled && !isBlinking;

    if (!allowWrite) {
       String message = '';
       if (!lightsFeatureEnabled) message = 'Control de luces deshabilitado por el perfil.';
       else if (isBlinking) message = 'Modo parpadeo activo (Perfil). Control manual bloqueado.';
       if (message.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text(message), duration: const Duration(seconds: 2)) );
       }
      return;
    }

    if (_ledCharacteristic == null) {
       if (state.isConnected) { _showErrorDialog("Error", "Característica LED no disponible. Intenta reconectar."); }
      return;
    }
    try {
      debugPrint("--> Enviando comando LED: $value");
      await _ledCharacteristic!.write(value.codeUnits, withoutResponse: false);
      debugPrint("<-- Comando LED enviado.");
    } catch (e) {
      debugPrint("XXX Error al escribir en LED: ${e.toString()}");
      _showErrorDialog("Error", "No se pudo enviar el comando al LED: ${e.toString()}");
    }
  }

  Future<void> _sendProfileToDevice(UserProfile profile) async {
    if (_profileConfigCharacteristic == null) { _showErrorDialog("Error", "Característica de perfil no encontrada. Intenta reconectar."); return; }
    final currentState = await _targetDevice?.connectionState.first ?? BluetoothConnectionState.disconnected;
    if (currentState != BluetoothConnectionState.connected) {
       debugPrint("XXX Abortando escritura perfil: Estado actual NO es conectado ($currentState).");
       _showErrorDialog("Error", "Dispositivo no conectado al intentar escribir perfil."); return;
    }

    String command = "L,${profile.lightsEnabled ? 1:0},${profile.lightOnInterval},${profile.lightOffInterval},${profile.autoOffDuration}|" +
                     "S,${profile.sensorsEnabled ? 1:0},${profile.sensorReadInterval}";
    debugPrint("--> Intentando escribir en Característica de Perfil...");
    debugPrint("    Característica: ${_profileConfigCharacteristic?.uuid}"); debugPrint("    Comando: $command");
    try {
      await _profileConfigCharacteristic!.write(command.codeUnits, withoutResponse: false);
      debugPrint("<-- Escritura a Perfil enviada (esperando respuesta).");
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Perfil "${profile.name}" aplicado al dispositivo.')) ); }
      state.setActiveProfile(profile);
    } catch (e) {
      debugPrint("XXX Error al escribir en Perfil: ${e.toString()}");
      if (e is FlutterBluePlusException && e.code == 6) { _showErrorDialog("Error de Conexión", "El dispositivo se desconectó durante la escritura del perfil."); if(mounted) { state.updateConnectionState(false);} }
      else { _showErrorDialog("Error al enviar perfil", "No se pudo enviar la configuración: ${e.toString()}"); }
    }
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog( context: context, builder: (ctx) => AlertDialog( title: Text(title), content: Text(message), actions: [ TextButton( child: const Text("OK"), onPressed: () => Navigator.of(ctx).pop(), ) ], ), );
  }

   @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cardTheme = Theme.of(context).cardTheme;

    return Consumer<SmartHomeState>(
      builder: (context, homeState, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("Panel de Control"),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_outline),
                tooltip: "Gestionar Perfiles",
                onPressed: () async {
                  final selectedProfile = await Navigator.of(context).push<UserProfile?>(
                    MaterialPageRoute(builder: (ctx) => const ProfilesScreen()),
                  );
                  final bool isConnectedNow = context.read<SmartHomeState>().isConnected;
                  if (selectedProfile != null) {
                    if (isConnectedNow) {
                       await _sendProfileToDevice(selectedProfile);
                    } else {
                       context.read<SmartHomeState>().setActiveProfile(selectedProfile);
                       if (mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Perfil "${selectedProfile.name}" se activará al conectar.')) ); }
                    }
                  }
                },
              )
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: <Widget>[
              _buildStatusCard(homeState), // Tarjeta de estado

              // --- SECCIÓN CONTROLES REINCORPORADA ---
              const SizedBox(height: 24),
              Text("Controles", style: textTheme.titleLarge),
              const SizedBox(height: 12),
              // Usamos GridView aunque solo haya un control, para facilitar añadir más en el futuro
              GridView.count(
                crossAxisCount: 2, // Mantenemos 2 columnas
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.0, // Tarjetas cuadradas
                children: [
                  _buildLightControlCard(homeState), // <<< AQUÍ ESTÁ EL CONTROL DEL LED
                  // Puedes añadir más tarjetas aquí si quieres
                ],
              ),
              // --- FIN SECCIÓN CONTROLES ---

              const SizedBox(height: 24),
              Text("Sensores Ambientales", style: textTheme.titleLarge),
              const SizedBox(height: 12),

              // --- DISEÑO SENSORES EN FILA (SIN LUZ) ---
              if (homeState.isConnected && (homeState.activeProfile?.sensorsEnabled ?? true))
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  decoration: BoxDecoration(
                    color: cardTheme.color ?? AppColors.card,
                    borderRadius: (cardTheme.shape as RoundedRectangleBorder?)?.borderRadius ?? BorderRadius.circular(16.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: cardTheme.elevation ?? 2.0,
                        offset: const Offset(0, 1),
                      ),
                    ]
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Solo incluimos Temperatura y Humedad
                      Expanded(child: _buildSensorGauge("Temperatura", homeState.temperature, "°C", 0, 50, AppColors.sensorTemp)),
                      Expanded(child: _buildSensorGauge("Humedad", homeState.humidity, "%", 0, 100, AppColors.sensorHumid)),
                      // ELIMINADO: Expanded(child: _buildSensorGauge("Luz", homeState.lightLevel, "lx", 0, 4095, AppColors.sensorLight)),
                    ],
                  ),
                )
              else
                _buildSensorPlaceholder(homeState.isConnected, homeState.activeProfile?.sensorsEnabled ?? true),
            ],
          ),
        );
      },
    );
  }

  // --- Widgets Auxiliares ---

  // Tarjeta de Estado y Conexión (sin cambios)
  Widget _buildStatusCard(SmartHomeState homeState) {
     return Card(
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
                  color: homeState.isConnected ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    homeState.statusMessage,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppColors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            if (homeState.activeProfile != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                     const Icon(Icons.label_important_outline, size: 18, color: AppColors.primaryDark),
                     const SizedBox(width: 5),
                     Text(
                       'Perfil: ${homeState.activeProfile!.name}',
                       style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryDark, fontSize: 15),
                     ),
                   ],
                 ),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isScanning ? _stopScan : (homeState.isConnected ? _disconnectFromDevice : _startScan),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isScanning
                    ? AppColors.accentOrange
                    : (homeState.isConnected ? AppColors.accentRed : AppColors.primary),
                minimumSize: const Size(200, 48),
              ),
              child: _isScanning
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),
                        SizedBox(width: 12),
                        Text("Buscando...")
                      ],
                    )
                  : Text(homeState.isConnected ? "Desconectar" : "Conectar"),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGET CONTROL LUZ REINCORPORADO (CON ESTILO ACTUALIZADO) ---
  Widget _buildLightControlCard(SmartHomeState homeState) {
    bool isConnected = homeState.isConnected;
    UserProfile? activeProfile = homeState.activeProfile;
    bool lightsFeatureEnabled = activeProfile?.lightsEnabled ?? true;
    bool isBlinking = activeProfile?.isBlinkingMode ?? false;
    bool allowTap = isConnected && lightsFeatureEnabled && !isBlinking;
    bool isOn = homeState.ledIsOn;

    Color bgColor;
    Color contentColor;
    IconData iconData;
    String statusText;

    if (!isConnected) {
      bgColor = AppColors.card.withOpacity(0.5);
      contentColor = AppColors.textSecondary.withOpacity(0.5);
      iconData = Icons.lightbulb_outline;
      statusText = "Desconectado";
    } else if (!lightsFeatureEnabled) {
      bgColor = AppColors.card.withOpacity(0.8);
      contentColor = AppColors.textSecondary.withOpacity(0.7);
      iconData = Icons.lightbulb_outline;
      statusText = "Deshab. (Perfil)";
    } else if (isBlinking) {
      bgColor = AppColors.sensorHumid.withOpacity(0.1); // Usamos un color distintivo para parpadeo
      contentColor = AppColors.sensorHumid;
      iconData = Icons.wb_incandescent_outlined; // Icono diferente para parpadeo
      statusText = "Parpadeo (Perfil)";
    } else if (isOn) {
      // ESTADO ENCENDIDO
      bgColor = AppColors.primary; // Fondo con color primario
      contentColor = AppColors.textOnPrimary; // Texto/Icono blanco
      iconData = Icons.lightbulb; // Icono relleno
      statusText = "Encendida";
    } else {
      // ESTADO APAGADO
      bgColor = AppColors.card; // Fondo blanco/tarjeta
      contentColor = AppColors.textPrimary; // Texto/Icono oscuro
      iconData = Icons.lightbulb_outline; // Icono contorno
      statusText = "Apagada";
    }

    return Card(
      elevation: isOn ? 4 : 2,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: allowTap
            ? () => _writeToLedCharacteristic(isOn ? "0" : "1")
            : () {
               String message = '';
               if (!isConnected) message = 'Conéctate al dispositivo primero.';
               else if (!lightsFeatureEnabled) message = 'Control de luces deshabilitado por el perfil.';
               else if (isBlinking) message = 'Modo parpadeo activo. Control manual bloqueado.';
               if (message.isNotEmpty && mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text(message), duration: const Duration(seconds: 2)) ); }
             },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          color: bgColor,
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(iconData, size: 40, color: contentColor),
              const SizedBox(height: 12),
              Text(
                "LED", // Cambiado de "Luz" a "LED"
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: contentColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                statusText,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: contentColor.withOpacity(0.8)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
 }
 // --- FIN WIDGET CONTROL LUZ ---


  // Widget Sensor Gauge (sin Card)
  Widget _buildSensorGauge(String title, double value, String unit, double min, double max, Color color) {
     bool isInvalid = value.isNaN;
     double displayValue = isInvalid ? min : value.clamp(min, max);

     return Column(
       mainAxisAlignment: MainAxisAlignment.center,
       children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16)),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: SfRadialGauge(
            axes: <RadialAxis>[
              RadialAxis(
                minimum: min, maximum: max, showLabels: false, showTicks: false,
                axisLineStyle: AxisLineStyle(
                  thickness: 0.15, cornerStyle: CornerStyle.bothCurve,
                  color: AppColors.background, thicknessUnit: GaugeSizeUnit.factor,
                ),
                pointers: <GaugePointer>[
                  RangePointer(
                    value: displayValue, cornerStyle: CornerStyle.bothCurve, width: 0.15,
                    sizeUnit: GaugeSizeUnit.factor, color: isInvalid ? AppColors.textSecondary.withOpacity(0.3) : color,
                    enableAnimation: true, animationDuration: 800, animationType: AnimationType.ease,
                  )
                ],
                annotations: <GaugeAnnotation>[
                  GaugeAnnotation(
                    positionFactor: 0.5, angle: 90,
                    widget: Text(
                      isInvalid ? "--" : value.toStringAsFixed(title == "Luz" ? 0 : 1),
                      style: TextStyle( fontSize: 16, fontWeight: FontWeight.bold, color: isInvalid ? AppColors.textSecondary : color, ),
                    ),
                  ),
                   GaugeAnnotation(
                    positionFactor: 0.75, angle: 90,
                    widget: Text( unit, style: TextStyle( fontSize: 12, fontWeight: FontWeight.normal, color: isInvalid ? AppColors.textSecondary.withOpacity(0.7) : color.withOpacity(0.7), ), ),
                  )
                ],
              )
            ],
          ),
        ),
      ],
    );
  }

 // Placeholder Sensores (Sin cambios)
  Widget _buildSensorPlaceholder(bool isConnected, bool sensorsEnabledByProfile) {
     String message; IconData icon; Color color = AppColors.textSecondary;
     if (!isConnected) { message = "Conecta el dispositivo para ver los sensores."; icon = Icons.bluetooth_disabled; }
     else if (!sensorsEnabledByProfile) { message = "Sensores deshabilitados por el perfil activo."; icon = Icons.sensors_off_outlined; color = AppColors.accentOrange; }
     else { message = "Esperando datos de los sensores..."; icon = Icons.sensors_outlined; }

     return Card(
       color: AppColors.background, elevation: 0,
       child: Container(
         height: 150, alignment: Alignment.center, padding: const EdgeInsets.all(16.0),
         child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
             Icon(icon, size: 40, color: color), const SizedBox(height: 12),
             Text( message, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w500), ),
           ]
         ),
       ),
     );
  }

} // Fin de _BluetoothControlScreenState