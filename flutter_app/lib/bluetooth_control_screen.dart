// lib/bluetooth_control_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

import 'smart_home_state.dart';
import 'main.dart'; // Asegúrate de que los UUIDs globales estén aquí
import 'profile_model.dart';
import 'profiles_screen.dart';
import 'app_colors.dart';

class BluetoothControlScreen extends StatefulWidget {
  const BluetoothControlScreen({super.key});

  @override
  State<BluetoothControlScreen> createState() => _BluetoothControlScreenState();
}

class _BluetoothControlScreenState extends State<BluetoothControlScreen> {
  BluetoothDevice? _targetDevice;
  BluetoothCharacteristic? _ledCharacteristic;
  BluetoothCharacteristic? _sensorCharacteristic;
  BluetoothCharacteristic? _profileConfigCharacteristic;
  BluetoothCharacteristic? _servoCharacteristic; // Variable para Servo

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

  SmartHomeState get state => Provider.of<SmartHomeState>(context, listen: false);

  void _startScan() {
    if (_isScanning || !mounted) return;
    setState(() => _isScanning = true);
    state.setStatusMessage("Buscando '${TARGET_DEVICE_NAME}'...");
    _scanSubscription?.cancel();

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
       if (!mounted || !_isScanning) return;
      for (ScanResult r in results) {
        String deviceName = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.localName;
        if (deviceName.toLowerCase() == TARGET_DEVICE_NAME.toLowerCase()) {
          _targetDevice = r.device;
          debugPrint('Dispositivo encontrado: ${_targetDevice!.remoteId}');
          _stopScan();
          _connectToDevice();
          return;
        }
      }
    }, onError: (e) {
       debugPrint("Error en scan results: $e");
       if (mounted) {
          _stopScan();
          state.setStatusMessage("Error al buscar.");
       }
    });

    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15)).catchError((e){
       debugPrint("Error al iniciar scan: $e");
       if (mounted) {
          _stopScan();
          state.setStatusMessage("Error al iniciar búsqueda.");
       }
    });

    Future.delayed(const Duration(seconds: 16), () {
      if (_isScanning && mounted) {
        debugPrint("Scan timeout manual.");
        _stopScan();
      }
    });
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    _scanSubscription = null;

    if (mounted) {
      if (_isScanning) {
        setState(() => _isScanning = false);
      }
      if (_targetDevice == null && !state.isConnected && !_isScanning) {
         state.setStatusMessage("Dispositivo no encontrado. Toca para reintentar.");
      }
    }
  }


  Future<void> _connectToDevice() async {
    if (_targetDevice == null || !mounted) return;
    state.setStatusMessage("Conectando a ${_targetDevice!.platformName.isNotEmpty ? _targetDevice!.platformName : _targetDevice!.remoteId}...");

    await _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;

    _connectionStateSubscription = _targetDevice!.connectionState.listen(
      (status) {
        debugPrint("${_targetDevice?.remoteId ?? 'Device'} state: ${status.toString()}");
        if (!mounted) return;

        if (status == BluetoothConnectionState.connected) {
          state.updateConnectionState(true);
          state.setStatusMessage("Conectado. Descubriendo servicios...");
          _discoverServices();
        } else if (status == BluetoothConnectionState.disconnected) {
           if (state.isConnected) {
              state.updateConnectionState(false);
              _ledCharacteristic = null;
              _sensorCharacteristic = null;
              _profileConfigCharacteristic = null;
              _servoCharacteristic = null; // Limpiar Servo
              _sensorDataSubscription?.cancel(); _sensorDataSubscription = null;
              _ledStateSubscription?.cancel(); _ledStateSubscription = null;
           }
           _targetDevice = null;
           if (_isScanning) {
             setState(() => _isScanning = false);
           }
        }
      },
      onError: (e) {
        debugPrint("Error en connection state listener: $e");
        if (mounted) {
          state.updateConnectionState(false);
          state.setStatusMessage("Error de conexión.");
           _targetDevice = null;
        }
         _connectionStateSubscription?.cancel(); _connectionStateSubscription = null;
      },
      onDone: () {
         debugPrint("Connection state stream done (probablemente desconectado).");
         if (mounted && state.isConnected) {
            state.updateConnectionState(false);
             _targetDevice = null;
         }
          _connectionStateSubscription = null;
      },
      cancelOnError: true
    );

    try {
      await _targetDevice!.connect(timeout: const Duration(seconds: 20), autoConnect: false);
      debugPrint("Conexión inicial establecida, solicitando MTU...");
      try {
        await _targetDevice!.requestMtu(256);
        debugPrint("MTU solicitado.");
      } catch (mtuError) {
        debugPrint("Advertencia: No se pudo solicitar MTU: ${mtuError.toString()}. Continuando...");
      }
    } catch (e) {
      debugPrint("Error al conectar: ${e.toString()}");
      if (mounted) {
         _showErrorDialog("Error de Conexión", "No se pudo conectar: ${e.toString()}");
         state.setStatusMessage("Fallo al conectar. Toca para reintentar.");
         await _connectionStateSubscription?.cancel(); _connectionStateSubscription = null;
         state.updateConnectionState(false);
          _targetDevice = null;
      }
    }
  }

  Future<void> _disconnectFromDevice() async {
    await _sensorDataSubscription?.cancel(); _sensorDataSubscription = null;
    await _ledStateSubscription?.cancel(); _ledStateSubscription = null;
    await _connectionStateSubscription?.cancel(); _connectionStateSubscription = null;

    final deviceToDisconnect = _targetDevice;
    _targetDevice = null;

    if (deviceToDisconnect != null) {
      if (mounted) state.setStatusMessage("Desconectando...");
      try {
        await deviceToDisconnect.disconnect();
        debugPrint("Desconexión solicitada para ${deviceToDisconnect.remoteId}.");
      } catch (e) {
         debugPrint("Error al solicitar desconexión: $e");
      }
    }

    if (mounted && state.isConnected) {
       state.updateConnectionState(false);
    }
  }

  Future<void> _discoverServices() async {
    if (_targetDevice == null || !state.isConnected || !mounted) return;
    state.setStatusMessage("Descubriendo servicios...");

    try {
      List<BluetoothService> services = await _targetDevice!.discoverServices()
          .timeout(const Duration(seconds: 15), onTimeout: () {
            throw TimeoutException('El descubrimiento de servicios tardó demasiado.');
          });

      debugPrint("Servicios descubiertos: ${services.length}");
      bool foundLed = false;
      bool foundSensor = false;
      bool foundProfile = false;
      bool foundServo = false; // Flag para Servo

      _ledCharacteristic = null;
      _sensorCharacteristic = null;
      _profileConfigCharacteristic = null;
      _servoCharacteristic = null; // Limpiar Servo
      await _ledStateSubscription?.cancel(); _ledStateSubscription = null;
      await _sensorDataSubscription?.cancel(); _sensorDataSubscription = null;

      for (var service in services) {
        if (service.uuid == SERVICE_UUID) {
          debugPrint("Servicio principal encontrado: ${service.uuid}");
          for (var characteristic in service.characteristics) {
             debugPrint("  Característica: ${characteristic.uuid} | Propiedades: ${characteristic.properties}");

            if (characteristic.uuid == LED_CHARACTERISTIC_UUID) {
              if (characteristic.properties.write && characteristic.properties.notify) {
                _ledCharacteristic = characteristic; foundLed = true;
                debugPrint("    -> Característica LED encontrada (Write, Notify).");
                try {
                  await _ledCharacteristic!.setNotifyValue(true);
                  _ledStateSubscription = _ledCharacteristic!.lastValueStream.listen(
                    (value) {
                      if (value.isNotEmpty && mounted) {
                        String combinedStateStr = String.fromCharCodes(value);
                        debugPrint("<<< Notificación LED recibida: '$combinedStateStr'");
                        List<String> statesStr = combinedStateStr.split(',');
                        List<bool> statesBool = statesStr.map((s) => s.trim() == '1').toList();
                        state.updateAllLedStates(statesBool);
                      }
                    },
                    onError: (e) => debugPrint("Error en LED stream: $e"),
                    cancelOnError: true
                  );
                  debugPrint("    Suscripción a notificaciones LED activada.");
                } catch (e) {
                  debugPrint("    Error al configurar notificaciones LED: $e");
                  _showErrorDialog("Error", "No se pudieron activar las notificaciones LED: ${e.toString()}");
                  foundLed = false;
                }
              } else {
                 debugPrint("    Advertencia: Característica LED encontrada pero no tiene propiedades Write Y Notify.");
              }
            }
            else if (characteristic.uuid == SENSOR_CHARACTERISTIC_UUID) {
              if (characteristic.properties.notify) {
                _sensorCharacteristic = characteristic; foundSensor = true;
                debugPrint("    -> Característica Sensor encontrada (Notify).");
                try {
                  await _sensorCharacteristic!.setNotifyValue(true);
                  _sensorDataSubscription = _sensorCharacteristic!.lastValueStream.listen(
                    (value) {
                      if ((state.activeProfile?.sensorsEnabled ?? true) && value.isNotEmpty && mounted) {
                        try {
                          String data = String.fromCharCodes(value);
                          List<String> parts = data.split(',');
                          if (parts.length == 2) {
                            double temp = double.tryParse(parts[0]) ?? double.nan;
                            double hum = double.tryParse(parts[1]) ?? double.nan;
                            state.updateSensorReadings(temp, hum);
                          } else {
                            debugPrint("Datos sensor formato incorrecto: $data (Esperaba 2 valores)");
                          }
                        } catch (e) {
                          debugPrint("Error al parsear datos del sensor: $e");
                        }
                      } else if (mounted) {
                        state.updateSensorReadings(double.nan, double.nan);
                      }
                    },
                    onError: (e) => debugPrint("Error en sensor stream: $e"),
                    cancelOnError: true
                  );
                  debugPrint("    Suscripción a notificaciones Sensor activada.");
                } catch (e) {
                  debugPrint("    Error al configurar notificaciones Sensor: $e");
                  _showErrorDialog("Error", "No se pudieron activar las notificaciones Sensor: ${e.toString()}");
                  foundSensor = false;
                }
              } else {
                 debugPrint("    Advertencia: Característica Sensor encontrada pero no tiene propiedad Notify.");
              }
            }
            else if (characteristic.uuid == PROFILE_CONFIG_UUID) {
               if(characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
                 _profileConfigCharacteristic = characteristic; foundProfile = true;
                 debugPrint("    -> Característica de Perfil encontrada (permite escritura).");
               } else {
                  debugPrint("    Advertencia: Característica de Perfil encontrada pero NO permite escritura.");
               }
            }
            // <<<--- BUSCAR CARACTERÍSTICA SERVO ---
            else if (characteristic.uuid == SERVO_CHARACTERISTIC_UUID) {
               // Verificar si permite escritura (Write o WriteWithoutResponse)
               if(characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
                 _servoCharacteristic = characteristic; foundServo = true;
                 debugPrint("    -> Característica de Servo encontrada (permite escritura).");
               } else {
                  debugPrint("    Advertencia: Característica de Servo encontrada pero NO permite escritura.");
               }
            }
          }
          break;
        }
      }

       debugPrint("Fin búsqueda: foundLed=$foundLed, foundSensor=$foundSensor, foundProfile=$foundProfile, foundServo=$foundServo");

      if (foundLed && foundSensor && foundProfile && foundServo) { // <<<--- AÑADIR foundServo
        if (mounted) {
           state.setStatusMessage("¡Dispositivo listo!");
           final profileToSend = state.activeProfile ?? state.profiles.firstOrNull;
           if (profileToSend != null) {
             await _sendProfileToDevice(profileToSend);
           }
        }
      } else {
        String missing = [
          if (!foundLed) "LED (W+N)", if (!foundSensor) "Sensor (N)", if (!foundProfile) "Perfil (W)", if (!foundServo) "Servo (W/WN)" // Modificado para indicar W o WN
        ].join(", ");
        final errorMessage = "Error: Faltan o fallaron características: $missing";
        debugPrint(errorMessage);
        if (mounted) {
          state.setStatusMessage(errorMessage);
          _showErrorDialog("Error de Servicio", "No se encontraron/configuraron características ($missing). Verifica firmware, UUIDs y propiedades.");
          await _disconnectFromDevice();
        }
      }
    } catch (e) {
      debugPrint("Error durante o después de descubrir servicios: $e");
      if (mounted) {
        String errorMsg = e is TimeoutException
           ? "El dispositivo no respondió a tiempo al buscar servicios (Timeout)."
           : "No se pudieron descubrir los servicios: ${e.toString()}";
        _showErrorDialog("Error de Servicio", errorMsg);
        state.setStatusMessage("Error al descubrir servicios.");
        await _disconnectFromDevice();
      }
    }
  }


  Future<void> _writeToLedCharacteristic(int ledIndex, String value) async {
     if (!mounted) return;
     UserProfile? activeProfile = state.activeProfile;
     LedConfig? ledConfig;
     try {
       ledConfig = (activeProfile != null && ledIndex < activeProfile.ledConfigs.length)
             ? activeProfile.ledConfigs[ledIndex] : null;
     } catch (e) {
       debugPrint("Error accediendo a ledConfig en índice $ledIndex: $e");
       ledConfig = null;
     }

     bool isEnabledByProfile = ledConfig?.enabled ?? true;
     bool isBlinking = ledConfig?.isBlinkingMode ?? false;
     bool allowWrite = state.isConnected && isEnabledByProfile && !isBlinking;

     if (!allowWrite) {
       String message = '';
       if (!state.isConnected) message = 'Dispositivo no conectado.';
       else if (!isEnabledByProfile) message = 'LED deshabilitado por el perfil activo.';
       else if (isBlinking) message = 'Modo parpadeo activo (Perfil). Control manual bloqueado.';
       if (message.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
       }
       return;
     }

     if (_ledCharacteristic == null) {
        _showErrorDialog("Error", "Característica LED no disponible. Intenta reconectar."); return;
     }

     String command = "$ledIndex,$value";

     try {
       debugPrint("--> Enviando comando LED: $command");
       await _ledCharacteristic!.write(command.codeUnits, withoutResponse: false);
       debugPrint("<-- Comando LED enviado.");
     } catch (e) {
       debugPrint("XXX Error al escribir en LED: ${e.toString()}");
       if (mounted) {
          bool isDisconnectError = e is FlutterBluePlusException && e.toString().toLowerCase().contains('disconnect');
          if (isDisconnectError && state.isConnected){
             _showErrorDialog("Error de Conexión", "El dispositivo se desconectó al enviar el comando.");
             state.updateConnectionState(false);
          } else {
             _showErrorDialog("Error", "No se pudo enviar el comando al LED: ${e.toString()}");
          }
       }
     }
  }


  Future<void> _sendProfileToDevice(UserProfile profile) async {
    if (!mounted) return;
    if (_profileConfigCharacteristic == null) {
      _showErrorDialog("Error", "Característica de perfil no encontrada. Intenta reconectar."); return;
    }

    BluetoothConnectionState currentState = BluetoothConnectionState.disconnected;
    try {
      currentState = await _targetDevice?.connectionState.first ?? BluetoothConnectionState.disconnected;
    } catch (e) {
       debugPrint("Error obteniendo connectionState.first: $e");
    }


    if (currentState != BluetoothConnectionState.connected) {
      debugPrint("XXX Abortando escritura perfil: Estado actual NO es conectado ($currentState).");
      _showErrorDialog("Error", "Dispositivo no conectado al intentar enviar perfil."); return;
    }

    String command = profile.generateEsp32ConfigString();
    debugPrint("--> Intentando escribir Perfil en ${_profileConfigCharacteristic!.uuid}...");
    debugPrint("    Comando: $command");

    try {
      await _profileConfigCharacteristic!.write(command.codeUnits, withoutResponse: false);
      debugPrint("<-- Escritura a Perfil enviada.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Perfil "${profile.name}" aplicado al dispositivo.')));
        state.setActiveProfile(profile);
      }
    } catch (e) {
      debugPrint("XXX Error al escribir en Perfil: ${e.toString()}");
      if (mounted) {
        bool isDisconnectError = e is FlutterBluePlusException && e.toString().toLowerCase().contains('disconnect');
        if (isDisconnectError) {
          _showErrorDialog("Error de Conexión", "El dispositivo se desconectó durante el envío del perfil.");
           if (state.isConnected) state.updateConnectionState(false);
        } else {
          _showErrorDialog("Error al enviar perfil", "No se pudo enviar la configuración: ${e.toString()}");
        }
      }
    }
  }


  // <<<--- FUNCIÓN CORREGIDA PARA ESCRIBIR AL SERVO ---
  Future<void> _writeToServoCharacteristic(String command) async {
     if (!mounted || !state.isConnected) {
       _showErrorDialog("Error", "Dispositivo no conectado.");
       return;
     }
     if (_servoCharacteristic == null) {
        _showErrorDialog("Error", "Característica del Servo no disponible. Intenta reconectar."); return;
     }

     try {
       debugPrint("--> Enviando comando Servo: $command");
       // CORRECCIÓN: Usar withoutResponse: true porque añadimos PROPERTY_WRITE_NR en ESP32
       await _servoCharacteristic!.write(command.codeUnits, withoutResponse: true);
       debugPrint("<-- Comando Servo enviado.");
       // Mostrar un SnackBar de confirmación
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Comando "$command" enviado a la puerta.'),
            duration: const Duration(seconds: 2)
         ));
       }
     } catch (e) {
       // Aunque withoutResponse=true, aún podría haber errores (ej. desconexión)
       debugPrint("XXX Error al escribir en Servo: ${e.toString()}");
       if (mounted) {
          bool isDisconnectError = e is FlutterBluePlusException && e.toString().toLowerCase().contains('disconnect');
          if (isDisconnectError && state.isConnected){
             _showErrorDialog("Error de Conexión", "El dispositivo se desconectó al enviar el comando del servo.");
             state.updateConnectionState(false);
          } else {
             _showErrorDialog("Error", "No se pudo enviar el comando al servo: ${e.toString()}");
          }
       }
     }
  }
  // <<<--- FIN FUNCIÓN CORREGIDA ---


  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title), content: Text(message),
        actions: [ TextButton( child: const Text("OK"), onPressed: () => Navigator.of(ctx).pop(), ) ],
      ),
    );
  }

   @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cardTheme = Theme.of(context).cardTheme;

    return Consumer<SmartHomeState>(
      builder: (context, homeState, child) {
        final ledAreaNames = homeState.ledAreaNames;

        return Scaffold(
          appBar: AppBar(
            title: const Text("Panel de Control"),
            actions: [
              IconButton(
                icon: const Icon(Icons.person_outline),
                tooltip: "Gestionar Perfiles",
                onPressed: () async {
                   final result = await Navigator.of(context).push<UserProfile?>(
                     MaterialPageRoute(builder: (ctx) => const ProfilesScreen()),
                   );
                   if (!mounted) return;
                   if (result is UserProfile) {
                      final updatedProfile = result;
                     if (homeState.isConnected) {
                        debugPrint("Reenviando perfil '${updatedProfile.name}' después de editar.");
                        await _sendProfileToDevice(updatedProfile);
                     } else {
                        state.setActiveProfile(updatedProfile);
                        ScaffoldMessenger.of(context).showSnackBar(
                           SnackBar(content: Text('Perfil "${updatedProfile.name}" actualizado. Se aplicará al conectar.'))
                        );
                     }
                   }
                },
              )
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: <Widget>[
              _buildStatusCard(homeState),
              const SizedBox(height: 24),

              Text("Controles", style: textTheme.titleLarge),
              const SizedBox(height: 12),
              GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, crossAxisSpacing: 16, mainAxisSpacing: 16, childAspectRatio: 1.0,
                ),
                itemCount: ledAreaNames.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  if (index < ledAreaNames.length) {
                    String areaName = ledAreaNames[index];
                    return _buildLightControlCard(homeState, index, areaName);
                  }
                  return const SizedBox.shrink();
                },
              ),

              // <<<--- CONTROL DEL SERVO (SIN CAMBIOS EN UI) ---
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
                  child: Row(
                    children: [
                      const Icon(Icons.sensor_door_outlined, size: 30, color: AppColors.primaryDark),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Text("Puerta Automática", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
                      ),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text("Abrir/Cerrar"),
                        onPressed: homeState.isConnected
                                   ? () => _writeToServoCharacteristic("TOGGLE") // Llama a la función corregida
                                   : null,
                        style: ElevatedButton.styleFrom(
                           backgroundColor: AppColors.accentOrange,
                           foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // <<<--- FIN CONTROL DEL SERVO ---


              const SizedBox(height: 24),
              Text("Sensores Ambientales", style: textTheme.titleLarge),
              const SizedBox(height: 12),

              if (homeState.isConnected && (homeState.activeProfile?.sensorsEnabled ?? true))
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  decoration: BoxDecoration(
                    color: cardTheme.color ?? AppColors.card,
                    borderRadius: (cardTheme.shape as RoundedRectangleBorder?)?.borderRadius ?? BorderRadius.circular(16.0),
                    boxShadow: [ BoxShadow( color: Colors.black.withOpacity(0.08), blurRadius: cardTheme.elevation ?? 2.0, offset: const Offset(0, 1),),],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(child: _buildSensorGauge("Temperatura", homeState.temperature, "°C", 0, 50, AppColors.sensorTemp)),
                      Expanded(child: _buildSensorGauge("Humedad", homeState.humidity, "%", 0, 100, AppColors.sensorHumid)),
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

  // --- Widgets Auxiliares (sin cambios) ---
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
                  size: 30, color: homeState.isConnected ? AppColors.primary : AppColors.textSecondary,
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
                       style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryDark, fontSize: 15),
                     ),
                   ],
                 ),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isScanning ? null : (homeState.isConnected ? _disconnectFromDevice : _startScan),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isScanning
                    ? AppColors.accentOrange
                    : (homeState.isConnected ? AppColors.accentRed : AppColors.primary),
                 foregroundColor: Colors.white,
                minimumSize: const Size(200, 48),
                 disabledBackgroundColor: Colors.grey.shade400,
                 disabledForegroundColor: Colors.grey.shade700,
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
                  : Text(homeState.isConnected ? "Desconectar" : "Buscar y Conectar"),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildLightControlCard(SmartHomeState homeState, int ledIndex, String areaName) {
    bool isConnected = homeState.isConnected;
    UserProfile? activeProfile = homeState.activeProfile;
    LedConfig? ledConfig = (activeProfile != null && ledIndex < activeProfile.ledConfigs.length)
                         ? activeProfile.ledConfigs[ledIndex]
                         : LedConfig(areaName: areaName);

    bool isEnabledByProfile = ledConfig.enabled;
    bool isBlinking = ledConfig.isBlinkingMode;
    bool allowTap = isConnected && isEnabledByProfile && !isBlinking;
    bool isOn = homeState.ledStates[areaName] ?? false;

    Color bgColor;
    Color contentColor;
    IconData iconData;
    String statusText;

     if (!isConnected) {
      bgColor = AppColors.card.withOpacity(0.5); contentColor = AppColors.textSecondary.withOpacity(0.5);
      iconData = Icons.lightbulb_outline; statusText = "Desconectado";
    } else if (!isEnabledByProfile) {
      bgColor = AppColors.card.withOpacity(0.8); contentColor = AppColors.textSecondary.withOpacity(0.7);
      iconData = Icons.lightbulb_outline; statusText = "Deshab. (Perfil)";
    } else if (isBlinking) {
      bgColor = AppColors.sensorHumid.withOpacity(0.1); contentColor = AppColors.sensorHumid;
      iconData = Icons.wb_incandescent_outlined; statusText = "Parpadeo (Perfil)";
    } else if (isOn) {
      bgColor = AppColors.primary; contentColor = AppColors.textOnPrimary;
      iconData = Icons.lightbulb; statusText = "Encendida";
    } else {
      bgColor = AppColors.card; contentColor = AppColors.textPrimary;
      iconData = Icons.lightbulb_outline; statusText = "Apagada";
    }

    return Card(
      elevation: isOn && isEnabledByProfile && isConnected ? 4 : 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: InkWell(
        onTap: allowTap
            ? () => _writeToLedCharacteristic(ledIndex, isOn ? "0" : "1")
            : () {
               String message = '';
               if (!isConnected) message = 'Conéctate al dispositivo primero.';
               else if (!isEnabledByProfile) message = 'LED deshabilitado por el perfil.';
               else if (isBlinking) message = 'Modo parpadeo activo. Control manual bloqueado.';
               if (message.isNotEmpty && mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2)));
               }
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
                areaName,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: contentColor),
                textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
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
                axisLineStyle: const AxisLineStyle(
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
                      isInvalid ? "--" : value.toStringAsFixed(1),
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