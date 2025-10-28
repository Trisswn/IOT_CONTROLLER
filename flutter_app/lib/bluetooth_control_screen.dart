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
final Guid PROFILE_CONFIG_UUID = Guid("c1d2e3f4-a5b6-c7d8-e9f0-a1b2c3d4e5f6");

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
  StreamSubscription<List<int>>? _sensorDataSubscription; // Cambiado para asegurar que se cancela bien
  bool _isScanning = false;

  @override
  void dispose() {
    // Cancelar todas las suscripciones activas
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _sensorDataSubscription?.cancel();
    // Intentar desconectar si el dispositivo existe
    try {
     _targetDevice?.disconnect();
    } catch (e) {
      // Ignorar errores al desconectar en dispose, puede pasar si ya está desconectado
      debugPrint("Error al desconectar en dispose: $e");
    }
    super.dispose();
  }

  // Helper para acceder al estado
  SmartHomeState get state => Provider.of<SmartHomeState>(context, listen: false);

  // --- Lógica Bluetooth ---

  void _startScan() {
    if (_isScanning) return; // Evitar scans múltiples
    setState(() => _isScanning = true);
    state.setStatusMessage("Buscando '${TARGET_DEVICE_NAME}'...");

    // Cancelar suscripción anterior si existe
    _scanSubscription?.cancel();

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        // Usar platformName o localName según lo que anuncie tu ESP32
        String deviceName = r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.localName;
        if (deviceName == TARGET_DEVICE_NAME) {
          _targetDevice = r.device;
          _stopScan(); // Detiene el escaneo una vez encontrado
          _connectToDevice(); // Intenta conectar
          break; // Salir del bucle una vez encontrado
        }
      }
    }, onError: (e) {
       debugPrint("Error en scan results: $e");
       _stopScan(); // Detener en caso de error
       state.setStatusMessage("Error al buscar.");
    });

    // Iniciar escaneo con timeout
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15)).catchError((e){
       debugPrint("Error al iniciar scan: $e");
       _stopScan(); // Asegura detener si startScan falla
       state.setStatusMessage("Error al iniciar búsqueda.");
    });

    // Añadir un timer por si el timeout de startScan no funciona como esperado
     Future.delayed(const Duration(seconds: 16), () {
        if (_isScanning) {
          debugPrint("Scan timeout manual.");
          _stopScan();
        }
     });
  }

  void _stopScan() {
    // Solo detener si está escaneando
    if (_isScanning) {
      FlutterBluePlus.stopScan();
      _scanSubscription?.cancel(); // Cancelar la suscripción
       setState(() => _isScanning = false);
       // Solo mostrar "no encontrado" si realmente no se encontró
       if (_targetDevice == null) {
          state.setStatusMessage("Dispositivo no encontrado.");
       }
    }
  }

  Future<void> _connectToDevice() async {
    if (_targetDevice == null) return;
    state.setStatusMessage("Conectando a ${_targetDevice!.platformName}...");

    // Cancelar suscripción de estado anterior
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = _targetDevice!.connectionState.listen((status) {
      debugPrint("Connection state update: $status");
      if (status == BluetoothConnectionState.connected) {
        state.updateConnectionState(true);
        state.setStatusMessage("Conectado. Descubriendo servicios...");
        _discoverServices(); // Descubre servicios al conectar
      } else if (status == BluetoothConnectionState.disconnected) {
        state.updateConnectionState(false);
        // Limpiar características y suscripciones al desconectar
        _ledCharacteristic = null;
        _sensorCharacteristic = null;
        _profileConfigCharacteristic = null;
        _sensorDataSubscription?.cancel();
        _sensorDataSubscription = null; // Anular referencia
        // No desactivamos el perfil aquí, para que se reenvíe si se reconecta
        // state.setActiveProfile(null);
      }
    }, onError: (e) {
       debugPrint("Error en connection state listener: $e");
       state.updateConnectionState(false); // Marcar como desconectado en error
       state.setStatusMessage("Error de conexión.");
    });

    try {
      // Conectar con timeout y solicitar MTU (opcional pero recomendado)
      await _targetDevice!.connect(timeout: const Duration(seconds: 15));
      await _targetDevice!.requestMtu(256); // Aumentar MTU puede ayudar con escrituras largas

    } catch (e) {
      debugPrint("Error al conectar: $e");
      _showErrorDialog("Error de Conexión", "No se pudo conectar: ${e.toString()}");
      state.setStatusMessage("Fallo al conectar.");
      // Asegurarse de limpiar en caso de fallo de conexión inicial
      _connectionStateSubscription?.cancel();
      state.updateConnectionState(false);
    }
  }

  void _disconnectFromDevice() {
    _sensorDataSubscription?.cancel();
    _sensorDataSubscription = null; // Anular referencia
    _connectionStateSubscription?.cancel(); // Cancela listener de estado
    _targetDevice?.disconnect(); // Inicia desconexión
     // El listener de estado en _connectToDevice manejará la actualización de estado
     // y la limpieza de características al recibir BluetoothConnectionState.disconnected
     state.setStatusMessage("Desconectando..."); // Mensaje temporal
  }

  Future<void> _discoverServices() async {
    if (_targetDevice == null || !state.isConnected) return;
    state.setStatusMessage("Descubriendo servicios...");
    try {
      List<BluetoothService> services = await _targetDevice!.discoverServices();
      bool foundLed = false;
      bool foundSensor = false;
      bool foundProfile = false;

      for (var service in services) {
        if (service.uuid == SERVICE_UUID) {
          debugPrint("Servicio principal encontrado.");
          for (var characteristic in service.characteristics) {
            // Característica LED
            if (characteristic.uuid == LED_CHARACTERISTIC_UUID) {
              _ledCharacteristic = characteristic;
              foundLed = true;
              debugPrint("Característica LED encontrada.");
            }
            // Característica Sensores
            if (characteristic.uuid == SENSOR_CHARACTERISTIC_UUID) {
              _sensorCharacteristic = characteristic;
              foundSensor = true;
              debugPrint("Característica Sensor encontrada.");
              // Cancelar suscripción anterior si existe
              _sensorDataSubscription?.cancel();
              await _sensorCharacteristic!.setNotifyValue(true);
              _sensorDataSubscription = _sensorCharacteristic!.lastValueStream.listen((value) {
                // Procesa solo si los sensores están habilitados por perfil o no hay perfil activo
                if (state.activeProfile?.sensorsEnabled ?? true) {
                  if (value.isEmpty) return; // Ignorar lecturas vacías
                  try {
                     String data = String.fromCharCodes(value);
                     List<String> parts = data.split(',');
                     if (parts.length == 3) {
                        double temp = double.tryParse(parts[0]) ?? double.nan;
                        double hum = double.tryParse(parts[1]) ?? double.nan;
                        double light = double.tryParse(parts[2]) ?? double.nan;
                        state.updateSensorReadings(temp, hum, light);
                     } else {
                        debugPrint("Datos sensor formato incorrecto: $data");
                     }
                  } catch (e) {
                    debugPrint("Error al parsear datos del sensor: $e");
                  }
                } else {
                   // Si los sensores están desactivados por perfil, poner valores NaN
                   state.updateSensorReadings(double.nan, double.nan, double.nan);
                }
              }, onError: (e) {
                 debugPrint("Error en sensor stream: $e");
                 // Podrías intentar reactivar la notificación aquí o mostrar un error
              });
            }
            // Característica Perfil
            if (characteristic.uuid == PROFILE_CONFIG_UUID) {
              _profileConfigCharacteristic = characteristic;
              foundProfile = true;
              debugPrint("Característica de Perfil encontrada!");
            }
          }
           break; // Salir si ya encontraste el servicio principal
        }
      }

      // Comprobar si todas las características necesarias fueron encontradas
      if (foundLed && foundSensor && foundProfile) {
        state.setStatusMessage("¡Dispositivo listo!");
        // Si hay un perfil activo al conectar, enviarlo
        if (state.activeProfile != null) {
           debugPrint("Enviando perfil activo al conectar...");
           await _sendProfileToDevice(state.activeProfile!); // Usar await
        }
      } else {
        String missing = "";
        if (!foundLed) missing += " LED,";
        if (!foundSensor) missing += " Sensor,";
        if (!foundProfile) missing += " Perfil,";
        missing = missing.isNotEmpty ? missing.substring(0, missing.length - 1) : missing;
        state.setStatusMessage("Error: Faltan características: $missing");
        _showErrorDialog("Error de Servicio", "No se encontraron todas las características necesarias ($missing). Verifica el código del ESP32 y los UUIDs.");
         _disconnectFromDevice(); // Desconectar si faltan características críticas
      }
    } catch (e) {
      debugPrint("Error al descubrir servicios: $e");
      _showErrorDialog("Error", "No se pudieron descubrir los servicios: ${e.toString()}");
      state.setStatusMessage("Error al descubrir servicios.");
       _disconnectFromDevice(); // Desconectar en caso de error
    }
  }

  // Escribe al LED (Control Manual)
  Future<void> _writeToLedCharacteristic(String value) async {
    // Usar la propiedad del perfil activo (si existe) para decidir si permitir el control manual
    bool manualControlAllowed = state.activeProfile?.allowManualLightControl ?? true; // Permitido si no hay perfil

    if (!manualControlAllowed) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Control manual de luz no permitido por perfil activo.'), duration: Duration(seconds: 2))
      );
      return; // No hacer nada si no está permitido
    }

    if (_ledCharacteristic == null) {
       if (state.isConnected) { // Solo mostrar error si se supone que debería estar disponible
         _showErrorDialog("Error", "Característica LED no disponible. Intenta reconectar.");
       }
      return;
    }
    try {
      // Usar 'write' con respuesta para más fiabilidad si el ESP32 lo soporta
      await _ledCharacteristic!.write(value.codeUnits, withoutResponse: false);
      state.setLedState(value == "1"); // Actualiza el estado local de la UI
    } catch (e) {
      _showErrorDialog("Error", "No se pudo enviar el comando al LED: ${e.toString()}");
    }
  }

  // Envía la configuración del perfil al ESP32
  Future<void> _sendProfileToDevice(UserProfile profile) async {
    if (_profileConfigCharacteristic == null) {
       _showErrorDialog("Error", "Característica de perfil no encontrada. Intenta reconectar.");
       return;
    }
    if (!state.isConnected) {
       _showErrorDialog("Error", "Dispositivo no conectado.");
      return;
    }

    // Nuevo Formato: "L,enabled,on_ms,off_ms,auto_off_s|S,enabled,interval_ms"
    String command = "L,${profile.lightsEnabled ? 1:0},${profile.lightOnInterval},${profile.lightOffInterval},${profile.autoOffDuration}|" +
                     "S,${profile.sensorsEnabled ? 1:0},${profile.sensorReadInterval}";

    debugPrint("Enviando perfil: $command");

    try {
      // Es importante usar 'write' (con respuesta) para asegurar que el ESP32 reciba la configuración completa
      await _profileConfigCharacteristic!.write(command.codeUnits, withoutResponse: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Perfil "${profile.name}" aplicado al dispositivo.'))
      );
      // Actualiza el estado activo en SmartHomeState (asegura consistencia)
      state.setActiveProfile(profile);

    } catch (e) {
      _showErrorDialog("Error al enviar perfil", "No se pudo enviar la configuración: ${e.toString()}");
       // Opcional: Desactivar el perfil activo si falla el envío? Podría causar inconsistencia.
       // state.setActiveProfile(null);
    }
  }

  // Muestra un diálogo de error genérico
  void _showErrorDialog(String title, String message) {
    if (!mounted) return; // Evitar mostrar si el widget ya no está en el árbol
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
        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text("Panel de Control IoT"),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.person_outline), // Icono de perfiles
                tooltip: "Gestionar Perfiles",
                onPressed: () async { // Hacer async para esperar el resultado
                   // Navega y espera a que vuelva con un posible perfil seleccionado
                   final selectedProfile = await Navigator.of(context).push<UserProfile?>(
                     MaterialPageRoute(builder: (ctx) => const ProfilesScreen()),
                   );

                   // Si se seleccionó un perfil (no se canceló)
                   if (selectedProfile != null) {
                      if (homeState.isConnected) {
                         // Si estamos conectados, lo enviamos al dispositivo
                         await _sendProfileToDevice(selectedProfile); // Usar await
                      } else {
                         // Si no estamos conectados, lo activamos localmente
                         // Se enviará automáticamente al conectar (en _discoverServices)
                         state.setActiveProfile(selectedProfile);
                         if (mounted) { // Verificar si el widget sigue montado antes de usar context
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Perfil "${selectedProfile.name}" se activará al conectar.'))
                            );
                         }
                      }
                   }
                },
              )
            ],
          ),
          body: ListView( // Usar ListView permite scroll si el contenido es mucho
            padding: const EdgeInsets.all(16.0),
            children: <Widget>[
              _buildStatusCard(homeState), // Pasamos el estado
              const SizedBox(height: 20),

              // Sección de Controles
              const Text("Controles", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2, // Ajusta a 1 si prefieres tarjetas más anchas
                shrinkWrap: true, // Necesario dentro de ListView
                physics: const NeverScrollableScrollPhysics(), // Deshabilita scroll interno
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: 1.1, // Ajusta para que las tarjetas no sean tan altas
                children: [
                  _buildLightControlCard(homeState), // Tarjeta de control de luz
                  // Puedes añadir más tarjetas de control aquí si es necesario
                ],
              ),
              const SizedBox(height: 20),

              // Sección de Sensores
              const Text("Sensores Ambientales", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              // Mostrar sensores basado en conexión y perfil
              // Usamos `homeState.activeProfile?.sensorsEnabled != false` para mostrar
              // si no hay perfil activo (null?sensorsEnabled = null, que no es false)
              // o si el perfil activo tiene sensorsEnabled = true.
              if (homeState.isConnected && homeState.activeProfile?.sensorsEnabled != false)
                GridView.count(
                  crossAxisCount: 2, // Muestra 2 gauges por fila
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.85, // Ajusta el aspecto de los gauges
                  children: [
                    _buildSensorGauge("Temperatura", homeState.temperature, "°C", 0, 50, Colors.redAccent),
                    _buildSensorGauge("Humedad", homeState.humidity, "%", 0, 100, Colors.blueAccent),
                    // Ajustar el gauge de luz si es necesario (ej. invertir valor)
                    _buildSensorGauge("Luz", homeState.lightLevel, "", 0, 4095, Colors.amber),
                  ],
                )
              else
                 _buildSensorPlaceholder(homeState.isConnected, homeState.activeProfile?.sensorsEnabled ?? true), // Pasa el estado de habilitado

            ],
          ),
        );
      },
    );
  }

  // --- Widgets Auxiliares ---

  // Tarjeta de Estado y Conexión (Modificado para mostrar perfil activo)
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
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500), // Tamaño ajustado
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
            // Muestra el nombre del perfil activo si existe
            if (homeState.activeProfile != null)
              Padding(
                padding: const EdgeInsets.only(top: 12.0, bottom: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                     const Icon(Icons.label_important_outline, size: 18, color: Colors.deepPurple),
                     const SizedBox(width: 5),
                     Text(
                      'Perfil Activo: ${homeState.activeProfile!.name}',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple, fontSize: 15),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            // Botón Conectar/Desconectar/Cancelar
            ElevatedButton(
              onPressed: _isScanning
                  ? _stopScan // Si está escaneando, el botón cancela
                  : (homeState.isConnected ? _disconnectFromDevice : _startScan), // Si no, conecta o desconecta
              style: ElevatedButton.styleFrom(
                backgroundColor: _isScanning
                    ? Colors.orangeAccent // Color diferente para cancelar
                    : (homeState.isConnected ? Colors.redAccent : Colors.indigo),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size(200, 45)
              ),
              child: _isScanning
                  ? const Row( // Mostrar icono y texto para cancelar
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),
                        SizedBox(width: 10),
                        Text("Buscando... (Cancelar)")
                      ],
                    )
                  : Text(homeState.isConnected ? "Desconectar" : "Buscar y Conectar"),
            ),
          ],
        ),
      ),
    );
  }

 // Tarjeta de Control de Luz (Modificada para reflejar modos de perfil)
 Widget _buildLightControlCard(SmartHomeState homeState) {
    bool isConnected = homeState.isConnected;
    UserProfile? activeProfile = homeState.activeProfile;
    // Considera las luces habilitadas si no hay perfil o si el perfil lo indica
    bool lightsFeatureEnabled = activeProfile?.lightsEnabled ?? true;
    bool isBlinking = activeProfile?.isBlinkingMode ?? false;
    bool isAutoOff = activeProfile?.isAutoOffMode ?? false;
    // El control manual está permitido si la función está habilitada y no está en modo parpadeo o auto-apagado
    bool manualControlAllowed = isConnected && lightsFeatureEnabled && !isBlinking && !isAutoOff;
    // El estado visual 'isOn' se basa en el estado real reportado (o mantenido localmente)
    bool isOn = homeState.ledIsOn;

    // Determinar colores, icono y texto según el estado
    Color cardColor = Colors.grey.shade200; // Color base desconectado/deshabilitado
    Color contentColor = Colors.grey.shade400;
    IconData iconData = Icons.lightbulb_outline;
    String statusText = "Desconectado";

    if (isConnected) {
      if (lightsFeatureEnabled) {
          if (isBlinking) {
            cardColor = Colors.lightBlue.shade100;
            contentColor = Colors.lightBlue.shade800;
            iconData = Icons.wb_incandescent_outlined; // Icono para parpadeo
            statusText = "Parpadeo (Perfil)";
          } else if (isAutoOff) {
            // En modo auto-off, el color/icono puede depender de si está encendido esperando apagarse
            cardColor = isOn ? Colors.orange.shade100 : Colors.white;
            contentColor = isOn ? Colors.orange.shade800 : Colors.grey.shade600;
            iconData = isOn ? Icons.timer_outlined : Icons.lightbulb_outline; // Icono de timer si está encendido
            statusText = "Auto-Apagado (Perfil)";
             // Podríamos añadir lógica extra aquí si supiéramos el tiempo restante
          } else { // Control Manual
            cardColor = isOn ? Colors.amber.shade100 : Colors.white;
            contentColor = isOn ? Colors.amber.shade800 : Colors.grey.shade600;
            iconData = isOn ? Icons.lightbulb : Icons.lightbulb_outline;
            statusText = isOn ? "Encendida" : "Apagada";
          }
      } else { // Función de luces deshabilitada por el perfil
          cardColor = Colors.grey.shade300;
          contentColor = Colors.grey.shade500;
          iconData = Icons.lightbulb_outline; // Icono específico deshabilitado
          statusText = "Deshab. (Perfil)";
      }
    }


    return Card(
      elevation: 4,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        // Solo permite tap si el control manual está explícitamente permitido por el estado actual
        onTap: manualControlAllowed
            ? () => _writeToLedCharacteristic(isOn ? "0" : "1") // Envía comando para cambiar estado
            : () { // Si no está permitido, mostrar un mensaje al usuario
               String message = '';
               if (!isConnected) message = 'Conéctate al dispositivo primero.';
               else if (!lightsFeatureEnabled) message = 'Control de luces deshabilitado por el perfil.';
               else if (isBlinking) message = 'Modo parpadeo activo (Perfil).';
               else if (isAutoOff) message = 'Modo apagado automático activo (Perfil).';
               // Mostrar el mensaje si hay algo que informar
               if (message.isNotEmpty && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message), duration: const Duration(seconds: 2))
                  );
               }
             },
        borderRadius: BorderRadius.circular(15),
        child: Padding( // Añadir padding interno
          padding: const EdgeInsets.all(8.0),
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
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                statusText,
                style: TextStyle(fontSize: 14, color: contentColor.withOpacity(0.8)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
 }


  // Widget para mostrar los medidores de sensores
  Widget _buildSensorGauge(String title, double value, String unit, double min, double max, Color color) {
    // Si el valor es NaN (Not a Number), muestra el mínimo para evitar errores en el gauge y un texto indicativo
    bool isInvalid = value.isNaN;
    double displayValue = isInvalid ? min : value;

    // Opcional: Invertir valor de luz si 0 es máximo brillo para el sensor
    // if (title == "Luz") {
    //     displayValue = max - displayValue;
    //     if (displayValue < min) displayValue = min;
    // }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5), // Espacio
            Expanded(
              child: SfRadialGauge(
                axes: <RadialAxis>[
                  RadialAxis(
                    minimum: min,
                    maximum: max,
                    showLabels: false, // Ocultar etiquetas del eje
                    showTicks: false,  // Ocultar marcas del eje
                    axisLineStyle: const AxisLineStyle(
                      thickness: 0.15, // Grosor del fondo del gauge
                      cornerStyle: CornerStyle.bothCurve,
                      color: Color.fromARGB(255, 224, 224, 224), // Color gris claro de fondo
                      thicknessUnit: GaugeSizeUnit.factor,
                    ),
                    pointers: <GaugePointer>[
                      RangePointer(
                        value: displayValue, // Usa el valor ajustado
                        cornerStyle: CornerStyle.bothCurve,
                        width: 0.15, // Mismo grosor que el fondo
                        sizeUnit: GaugeSizeUnit.factor,
                        color: isInvalid ? Colors.grey.shade400 : color, // Color gris si es inválido
                        enableAnimation: true,
                        animationDuration: 800, // Duración de la animación
                        animationType: AnimationType.ease, // Tipo de animación
                      )
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                        positionFactor: 0.1, // Posición vertical del texto
                        angle: 90, // Ángulo (90 es centro)
                        widget: Text(
                          // Muestra "--" si el valor es inválido (NaN)
                          isInvalid ? "-- $unit" : "${displayValue.toStringAsFixed(title == "Luz" ? 0 : 1)} $unit",
                          style: TextStyle(
                            fontSize: 18, // Tamaño ajustado
                            fontWeight: FontWeight.bold,
                            color: isInvalid ? Colors.grey.shade600 : color, // Color del texto
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

 // Placeholder para cuando los sensores no están disponibles o deshabilitados
  Widget _buildSensorPlaceholder(bool isConnected, bool sensorsEnabledByProfile) {
    String message;
    IconData icon;
    Color color = Colors.grey.shade500;

    if (!isConnected) {
      message = "Conecta el dispositivo para ver los sensores.";
      icon = Icons.bluetooth_disabled;
    } else if (!sensorsEnabledByProfile) {
       message = "Sensores deshabilitados por el perfil activo.";
       icon = Icons.sensors_off_outlined;
       color = Colors.orange.shade700; // Color diferente para destacar que es por perfil
    } else {
       message = "Esperando datos de los sensores..."; // Caso intermedio mientras llegan los primeros datos
       icon = Icons.sensors_outlined;
    }

    return Card(
      elevation: 2,
      color: Colors.grey.shade100, // Fondo ligeramente diferente
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        height: 200, // Altura fija para el placeholder
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16.0),
        child: Column(
           mainAxisAlignment: MainAxisAlignment.center,
           children: [
             Icon(icon, size: 40, color: color),
             const SizedBox(height: 12),
             Text(
               message,
               textAlign: TextAlign.center,
               style: TextStyle(color: color, fontSize: 16),
            ),
          ]
        ),
      ),
    );
  }
}