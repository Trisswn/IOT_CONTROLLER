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

// Asegúrate que este UUID coincida EXÁCTAMENTE con el del ESP32
// Lo movimos a main.dart, pero lo dejamos aquí comentado por referencia si fuera necesario
// final Guid PROFILE_CONFIG_UUID = Guid("c1d2e3f4-a5b6-c7d8-e9f0-a1b2c3d4e5f6");

class BluetoothControlScreen extends StatefulWidget {
  const BluetoothControlScreen({super.key});

  @override
  State<BluetoothControlScreen> createState() => _BluetoothControlScreenState();
}

class _BluetoothControlScreenState extends State<BluetoothControlScreen> {

  BluetoothDevice? _targetDevice;
  BluetoothCharacteristic? _ledCharacteristic;
  BluetoothCharacteristic? _sensorCharacteristic;
  BluetoothCharacteristic? _profileConfigCharacteristic; // Característica para perfiles

  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  StreamSubscription<List<int>>? _sensorDataSubscription;
  StreamSubscription<List<int>>? _ledStateSubscription; // <<< NUEVO: Listener para el estado del LED
  bool _isScanning = false;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _sensorDataSubscription?.cancel();
    _ledStateSubscription?.cancel(); // <<< NUEVO: Cancelar listener del LED
    try {
     _targetDevice?.disconnect();
    } catch (e) {
      debugPrint("Error al desconectar en dispose: $e");
    }
    super.dispose();
  }

  // Helper para acceder al estado
  SmartHomeState get state => Provider.of<SmartHomeState>(context, listen: false);

  // --- Lógica Bluetooth ---

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
        _ledStateSubscription?.cancel(); // <<< NUEVO: Cancelar al desconectar
        _ledStateSubscription = null;   // <<< NUEVO: Poner a null
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
    _ledStateSubscription?.cancel(); // <<< NUEVO: Cancelar al desconectar manualmente
    _ledStateSubscription = null;   // <<< NUEVO: Poner a null
    _connectionStateSubscription?.cancel();
    _targetDevice?.disconnect();
     state.setStatusMessage("Desconectando...");
  }

  // --- _discoverServices (MODIFICADO) ---
  Future<void> _discoverServices() async {
    if (_targetDevice == null || !state.isConnected) return;
    state.setStatusMessage("Descubriendo servicios...");
    try {
      List<BluetoothService> services = await _targetDevice!.discoverServices();
      bool foundLed = false; bool foundSensor = false; bool foundProfile = false;

      // Limpiar listeners anteriores por si acaso (reconexión)
      _ledStateSubscription?.cancel();
      _ledStateSubscription = null;
      _sensorDataSubscription?.cancel();
      _sensorDataSubscription = null;

      for (var service in services) {
        if (service.uuid == SERVICE_UUID) {
          debugPrint("Servicio principal encontrado.");
          for (var characteristic in service.characteristics) {
            // Característica LED
            if (characteristic.uuid == LED_CHARACTERISTIC_UUID) {
               _ledCharacteristic = characteristic; foundLed = true; debugPrint("Característica LED encontrada.");
              // --- INICIO MODIFICACIÓN LED ---
              try {
                // Habilitar notificaciones para el LED
                await _ledCharacteristic!.setNotifyValue(true);
                // Escuchar cambios de estado notificados por el ESP32
                _ledStateSubscription = _ledCharacteristic!.lastValueStream.listen((value) {
                  if (value.isNotEmpty) {
                    String ledStateStr = String.fromCharCodes(value);
                    bool actualLedState = (ledStateStr == "1");
                    debugPrint("<<< Notificación LED recibida: ${actualLedState ? 'ON' : 'OFF'}");
                    // Actualiza el estado de la app con el valor REAL del ESP32
                    if (mounted) { // Asegurarse que el widget aún existe
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
                 // Considera si desconectar o solo mostrar error
              }
              // --- FIN MODIFICACIÓN LED ---
            }

            // Característica Sensor
            if (characteristic.uuid == SENSOR_CHARACTERISTIC_UUID) {
              _sensorCharacteristic = characteristic; foundSensor = true; debugPrint("Característica Sensor encontrada.");
              try {
                  await _sensorCharacteristic!.setNotifyValue(true);
                  _sensorDataSubscription = _sensorCharacteristic!.lastValueStream.listen((value) {
                    // Solo procesar si el perfil permite sensores (o no hay perfil)
                    if (state.activeProfile?.sensorsEnabled ?? true) {
                      if (value.isEmpty) return;
                      try {
                        String data = String.fromCharCodes(value);
                        List<String> parts = data.split(',');
                        if (parts.length == 3) {
                          double temp = double.tryParse(parts[0]) ?? double.nan;
                          double hum = double.tryParse(parts[1]) ?? double.nan;
                          // Corrección: El valor de luz es entero
                          double light = double.tryParse(parts[2]) ?? double.nan;
                          if (mounted) {
                            state.updateSensorReadings(temp, hum, light);
                          }
                        } else {
                          debugPrint("Datos sensor formato incorrecto: $data");
                        }
                      } catch (e) {
                        debugPrint("Error al parsear datos del sensor: $e");
                      }
                    } else {
                      // Si los sensores están deshabilitados por perfil, mostrar NaN o 0
                       if (mounted) {
                         state.updateSensorReadings(double.nan, double.nan, double.nan);
                       }
                    }
                  }, onError: (e) {
                    debugPrint("Error en sensor stream: $e");
                  });
                   debugPrint("Suscripción a notificaciones Sensor activada.");
              } catch(e) {
                  debugPrint("Error al configurar notificaciones Sensor: $e");
                  _showErrorDialog("Error", "No se pudieron activar las notificaciones para el Sensor: ${e.toString()}");
              }
            }

            // Característica Perfil
            if (characteristic.uuid == PROFILE_CONFIG_UUID) {
              _profileConfigCharacteristic = characteristic; foundProfile = true; debugPrint("Característica de Perfil encontrada!");
            }
          }
           break; // Salir del bucle de servicios una vez encontrado el principal
        }
      } // Fin for services

      // Verificar si se encontraron todas
      if (foundLed && foundSensor && foundProfile) {
        state.setStatusMessage("¡Dispositivo listo!");
        // Enviar perfil activo si existe (después de configurar listeners)
        if (state.activeProfile != null) {
          debugPrint("Enviando perfil activo al conectar...");
          await _sendProfileToDevice(state.activeProfile!);
        }
        // (Opcional) Leer estado inicial LED aquí si no se confía en la primera notificación
        // try {
        //   var initialValue = await _ledCharacteristic?.read();
        //   if (initialValue != null && initialValue.isNotEmpty) {
        //       state.setLedState(String.fromCharCodes(initialValue) == "1");
        //       debugPrint("Estado inicial del LED leído: ${state.ledIsOn ? 'ON' : 'OFF'}");
        //   }
        // } catch (e) { debugPrint("Error leyendo estado inicial LED: $e"); }

      } else {
        // Manejo de error si falta alguna característica
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

  // --- _writeToLedCharacteristic (MODIFICADO - Opcional sin actualización optimista) ---
  Future<void> _writeToLedCharacteristic(String value) async {
    UserProfile? activeProfile = state.activeProfile; // Obtener perfil actual
    bool lightsFeatureEnabled = activeProfile?.lightsEnabled ?? true; // Habilitado si no hay perfil
    bool isBlinking = activeProfile?.isBlinkingMode ?? false;

    // Permitir escritura si luces habilitadas Y NO está en modo parpadeo
    bool allowWrite = lightsFeatureEnabled && !isBlinking;

    if (!allowWrite) {
       String message = '';
       if (!lightsFeatureEnabled) message = 'Control de luces deshabilitado por el perfil.';
       else if (isBlinking) message = 'Modo parpadeo activo (Perfil). Control manual bloqueado.';
       if (message.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), duration: const Duration(seconds: 2))
          );
       }
      return; // No hacer nada si no está permitido
    }

    if (_ledCharacteristic == null) {
       if (state.isConnected) { _showErrorDialog("Error", "Característica LED no disponible. Intenta reconectar."); }
      return;
    }
    try {
      debugPrint("--> Enviando comando LED: $value"); // Debug print
      await _ledCharacteristic!.write(value.codeUnits, withoutResponse: false);
      // state.setLedState(value == "1"); // <<< OPCIONAL: COMENTA O ELIMINA ESTA LÍNEA
      debugPrint("<-- Comando LED enviado."); // Debug print
    } catch (e) {
      debugPrint("XXX Error al escribir en LED: ${e.toString()}"); // Debug print
      _showErrorDialog("Error", "No se pudo enviar el comando al LED: ${e.toString()}");
    }
  }

  // --- _sendProfileToDevice (Sin cambios desde la versión anterior) ---
  Future<void> _sendProfileToDevice(UserProfile profile) async {
    if (_profileConfigCharacteristic == null) { _showErrorDialog("Error", "Característica de perfil no encontrada. Intenta reconectar."); return; }
    // Verificar conexión robusta
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
      state.setActiveProfile(profile); // Actualiza el perfil activo en el estado de la app
    } catch (e) {
      debugPrint("XXX Error al escribir en Perfil: ${e.toString()}");
      if (e is FlutterBluePlusException && e.code == 6) { _showErrorDialog("Error de Conexión", "El dispositivo se desconectó durante la escritura del perfil."); if(mounted) { state.updateConnectionState(false);} }
      else { _showErrorDialog("Error al enviar perfil", "No se pudo enviar la configuración: ${e.toString()}"); }
    }
  }

  // --- _showErrorDialog (Sin cambios) ---
  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog( context: context, builder: (ctx) => AlertDialog( title: Text(title), content: Text(message), actions: [ TextButton( child: const Text("OK"), onPressed: () => Navigator.of(ctx).pop(), ) ], ), );
  }

  // --- build (Sin cambios) ---
   @override
  Widget build(BuildContext context) {
    return Consumer<SmartHomeState>(
      builder: (context, homeState, child) {
        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text("Panel de Control IoT"), backgroundColor: Colors.indigo, foregroundColor: Colors.white, centerTitle: true,
            actions: [
              IconButton( icon: const Icon(Icons.person_outline), tooltip: "Gestionar Perfiles",
                onPressed: () async {
                  debugPrint("Navegando a ProfilesScreen...");
                  debugPrint("Estado antes de navegar: isConnected = ${context.read<SmartHomeState>().isConnected}");
                  final selectedProfile = await Navigator.of(context).push<UserProfile?>( MaterialPageRoute(builder: (ctx) => const ProfilesScreen()), );
                  debugPrint("Regresó de ProfilesScreen."); debugPrint("Perfil seleccionado: ${selectedProfile?.name ?? 'Ninguno (null)'}");
                  // Re-leer el estado de conexión por si cambió mientras estaba en la otra pantalla
                  final bool isConnectedNow = context.read<SmartHomeState>().isConnected;
                  debugPrint("Estado después de navegar: isConnected = $isConnectedNow");
                  if (selectedProfile != null) {
                    debugPrint("selectedProfile NO es null. Verificando conexión...");
                    if (isConnectedNow) {
                       debugPrint("Está conectado. Llamando a _sendProfileToDevice...");
                       await _sendProfileToDevice(selectedProfile);
                    } else {
                       debugPrint("NO está conectado. Estableciendo perfil localmente...");
                       context.read<SmartHomeState>().setActiveProfile(selectedProfile);
                       if (mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Perfil "${selectedProfile.name}" se activará al conectar.')) ); }
                    }
                  } else {
                    debugPrint("selectedProfile ES null. ¿Desactivar perfil?");
                    // Opcional: Desactivar el perfil activo si no se seleccionó ninguno nuevo
                    // context.read<SmartHomeState>().setActiveProfile(null);
                    // if (isConnectedNow) { /* Quizás enviar un perfil "default" o comando para desactivar */ }
                  }
                },
              )
            ],
          ),
          body: ListView( padding: const EdgeInsets.all(16.0), children: <Widget>[
              _buildStatusCard(homeState), const SizedBox(height: 20),
              const Text("Controles", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
              // Usar GridView para permitir más controles en el futuro
              GridView.count( crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.1, // Ajusta esto para el tamaño deseado
                children: [
                  _buildLightControlCard(homeState),
                  // Aquí podrías añadir más tarjetas de control si tuvieras más actuadores
                ],
              ),
              const SizedBox(height: 20),
              const Text("Sensores Ambientales", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
              // Mostrar gauges solo si está conectado Y los sensores están habilitados por perfil (o no hay perfil)
              if (homeState.isConnected && (homeState.activeProfile?.sensorsEnabled ?? true))
                GridView.count( crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 0.85, // Ajusta para el tamaño de los gauges
                  children: [
                    _buildSensorGauge("Temperatura", homeState.temperature, "°C", 0, 50, Colors.redAccent),
                    _buildSensorGauge("Humedad", homeState.humidity, "%", 0, 100, Colors.blueAccent),
                    _buildSensorGauge("Luz", homeState.lightLevel, "", 0, 4095, Colors.amber), // Asumiendo LDR da 0-4095
                  ],
                )
              else
                _buildSensorPlaceholder(homeState.isConnected, homeState.activeProfile?.sensorsEnabled ?? true), // Pasa el estado de habilitación
            ],
          ),
        );
      },
    );
  }

  // --- Widgets Auxiliares ---

  // Tarjeta de Estado y Conexión
  Widget _buildStatusCard(SmartHomeState homeState) {
     return Card( elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding( padding: const EdgeInsets.all(16.0), child: Column( children: [
            Row( mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon( homeState.isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled, size: 30, color: homeState.isConnected ? Colors.indigo : Colors.grey, ), const SizedBox(width: 10),
                Expanded( child: Text( homeState.statusMessage, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500), textAlign: TextAlign.center, ), ), ], ),
            // Mostrar perfil activo si existe
            if (homeState.activeProfile != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
                child: Row( mainAxisAlignment: MainAxisAlignment.center, children: [
                     const Icon(Icons.label_important_outline, size: 18, color: Colors.deepPurple), const SizedBox(width: 5),
                     Text( 'Perfil Activo: ${homeState.activeProfile!.name}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple, fontSize: 15), ),
                   ],
                 ),
              ),
            const SizedBox(height: 16),
            ElevatedButton( onPressed: _isScanning ? _stopScan : (homeState.isConnected ? _disconnectFromDevice : _startScan),
              style: ElevatedButton.styleFrom( backgroundColor: _isScanning ? Colors.orangeAccent : (homeState.isConnected ? Colors.redAccent : Colors.indigo), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), minimumSize: const Size(200, 45) ),
              child: _isScanning
                  ? const Row( mainAxisSize: MainAxisSize.min, children: [ SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)), SizedBox(width: 10), Text("Buscando... (Cancelar)") ],)
                  : Text(homeState.isConnected ? "Desconectar" : "Buscar y Conectar"),
            ),
          ],
        ),
      ),
    );
  }

  // Tarjeta de Control de Luz (Sin cambios respecto a la versión anterior con lógica onTap corregida)
  Widget _buildLightControlCard(SmartHomeState homeState) {
    bool isConnected = homeState.isConnected;
    UserProfile? activeProfile = homeState.activeProfile;
    bool lightsFeatureEnabled = activeProfile?.lightsEnabled ?? true;
    bool isBlinking = activeProfile?.isBlinkingMode ?? false;
    bool isAutoOff = activeProfile?.isAutoOffMode ?? false;
    // Permitir tap si está conectado, la función está habilitada Y NO está en modo parpadeo.
    bool allowTap = isConnected && lightsFeatureEnabled && !isBlinking;
    bool isOn = homeState.ledIsOn; // Usa el estado REAL del LED

    Color cardColor = Colors.grey.shade200; Color contentColor = Colors.grey.shade400;
    IconData iconData = Icons.lightbulb_outline; String statusText = "Desconectado";

    if (isConnected) {
      if (lightsFeatureEnabled) {
          if (isBlinking) { cardColor = Colors.lightBlue.shade100; contentColor = Colors.lightBlue.shade800; iconData = Icons.wb_incandescent_outlined; statusText = "Parpadeo (Perfil)"; }
          else if (isAutoOff) { cardColor = isOn ? Colors.orange.shade100 : Colors.white; contentColor = isOn ? Colors.orange.shade800 : Colors.grey.shade600; iconData = isOn ? Icons.timer_outlined : Icons.lightbulb_outline; statusText = "Auto-Apagado (Perfil)"; }
          else { cardColor = isOn ? Colors.amber.shade100 : Colors.white; contentColor = isOn ? Colors.amber.shade800 : Colors.grey.shade600; iconData = isOn ? Icons.lightbulb : Icons.lightbulb_outline; statusText = isOn ? "Encendida" : "Apagada"; }
      } else { cardColor = Colors.grey.shade300; contentColor = Colors.grey.shade500; iconData = Icons.lightbulb_outline; statusText = "Deshab. (Perfil)"; }
    }

    return Card( elevation: 4, color: cardColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: allowTap
            ? () => _writeToLedCharacteristic(isOn ? "0" : "1") // Envía comando para cambiar estado
            : () { // Mensaje si no está permitido
               String message = '';
               if (!isConnected) message = 'Conéctate al dispositivo primero.';
               else if (!lightsFeatureEnabled) message = 'Control de luces deshabilitado por el perfil.';
               else if (isBlinking) message = 'Modo parpadeo activo (Perfil). Control manual bloqueado.';
               if (message.isNotEmpty && mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text(message), duration: const Duration(seconds: 2)) ); }
             },
        borderRadius: BorderRadius.circular(15),
        child: Padding( padding: const EdgeInsets.all(8.0),
          child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(iconData, size: 40, color: contentColor), const SizedBox(height: 8),
              Text( "Luz", style: TextStyle( fontSize: 18, fontWeight: FontWeight.bold, color: contentColor, ), textAlign: TextAlign.center, ), const SizedBox(height: 4),
              Text( statusText, style: TextStyle(fontSize: 14, color: contentColor.withOpacity(0.8)), textAlign: TextAlign.center, ),
            ],
          ),
        ),
      ),
    );
 }

  // Widget Sensor Gauge (Sin cambios)
  Widget _buildSensorGauge(String title, double value, String unit, double min, double max, Color color) {
     bool isInvalid = value.isNaN;
     // Asegurar que el valor esté dentro de los límites para el gauge, incluso si es inválido
     double displayValue = isInvalid ? min : value.clamp(min, max);

     return Card( elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: Padding( padding: const EdgeInsets.all(12.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 5),
            Expanded( child: SfRadialGauge( axes: <RadialAxis>[ RadialAxis( minimum: min, maximum: max, showLabels: false, showTicks: false, axisLineStyle: const AxisLineStyle( thickness: 0.15, cornerStyle: CornerStyle.bothCurve, color: Color.fromARGB(255, 224, 224, 224), thicknessUnit: GaugeSizeUnit.factor, ),
                    pointers: <GaugePointer>[ RangePointer( value: displayValue, // Usa el valor ajustado
                                                             cornerStyle: CornerStyle.bothCurve, width: 0.15, sizeUnit: GaugeSizeUnit.factor, color: isInvalid ? Colors.grey.shade400 : color, enableAnimation: true, animationDuration: 800, animationType: AnimationType.ease, ) ],
                    annotations: <GaugeAnnotation>[ GaugeAnnotation( positionFactor: 0.1, angle: 90, widget: Text( isInvalid ? "-- $unit" : "${value.toStringAsFixed(title == "Luz" ? 0 : 1)} $unit", // Muestra el valor original (o --)
                                                                                                                   style: TextStyle( fontSize: 18, fontWeight: FontWeight.bold, color: isInvalid ? Colors.grey.shade600 : color, ), ), ) ],
                  ) ], ), ),
          ],
        ),
      ),
    );
  }

 // Placeholder Sensores (Sin cambios)
  Widget _buildSensorPlaceholder(bool isConnected, bool sensorsEnabledByProfile) {
     String message; IconData icon; Color color = Colors.grey.shade500;
     if (!isConnected) { message = "Conecta el dispositivo para ver los sensores."; icon = Icons.bluetooth_disabled; }
     else if (!sensorsEnabledByProfile) { message = "Sensores deshabilitados por el perfil activo."; icon = Icons.sensors_off_outlined; color = Colors.orange.shade700; }
     else { message = "Esperando datos de los sensores..."; icon = Icons.sensors_outlined; }
     return Card( elevation: 2, color: Colors.grey.shade100, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: Container( height: 200, alignment: Alignment.center, padding: const EdgeInsets.all(16.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
             Icon(icon, size: 40, color: color), const SizedBox(height: 12),
             Text( message, textAlign: TextAlign.center, style: TextStyle(color: color, fontSize: 16), ),
           ]
         ),
       ),
     );
  }

} // Fin de _BluetoothControlScreenState