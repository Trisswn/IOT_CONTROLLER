import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// IDs únicos para el servicio y la característica BLE del ESP32.
// Deben coincidir con los que definiste en el código de Arduino para el ESP32.
final Guid SERVICE_UUID = Guid("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
final Guid CHARACTERISTIC_UUID = Guid("beb5483e-36e1-4688-b7f5-ea07361b26a8");
// Nombre del dispositivo que buscamos
const String TARGET_DEVICE_NAME = "ESP32-LED";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control LED ESP32',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const BluetoothControlScreen(),
    );
  }
}

class BluetoothControlScreen extends StatefulWidget {
  const BluetoothControlScreen({super.key});

  @override
  State<BluetoothControlScreen> createState() => _BluetoothControlScreenState();
}

class _BluetoothControlScreenState extends State<BluetoothControlScreen> {
  BluetoothDevice? _targetDevice;
  BluetoothCharacteristic? _ledCharacteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;

  bool _isScanning = false;
  bool _isConnected = false;
  String _statusMessage = "Presiona el botón de búsqueda para encontrar tu ESP32.";

  @override
  void initState() {
    super.initState();
    // Revisa si el Bluetooth está disponible en el dispositivo.
    if (Platform.isAndroid) {
      FlutterBluePlus.turnOn();
    }
  }

  @override
  void dispose() {
    // Limpia las suscripciones para evitar fugas de memoria.
    _scanSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    _targetDevice?.disconnect();
    super.dispose();
  }
  
  // Inicia o detiene el escaneo de dispositivos BLE
  void _toggleScan() {
    if (_isScanning) {
      _stopScan();
    } else {
      _startScan();
    }
  }
  
  void _startScan() {
    setState(() {
      _isScanning = true;
      _statusMessage = "Buscando dispositivo '${TARGET_DEVICE_NAME}'...";
    });

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      // Busca en los resultados un dispositivo con el nombre que definimos.
      for (ScanResult r in results) {
        if (r.device.platformName == TARGET_DEVICE_NAME) {
          _targetDevice = r.device;
          _stopScan();
          _connectToDevice();
          break; // Salimos del bucle una vez que lo encontramos.
        }
      }
    }, onError: (e) {
      _showErrorDialog("Error de Escaneo", "No se pudo iniciar el escaneo: $e");
      _stopScan();
    });
    
    // Inicia el escaneo. Se detendrá automáticamente después de 15 segundos si no se encuentra nada.
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 15));
  }

  void _stopScan() {
    FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();
    setState(() {
      _isScanning = false;
      if (_targetDevice == null) {
        _statusMessage = "No se encontró el dispositivo. Asegúrate de que esté encendido y cerca.";
      }
    });
  }

  void _connectToDevice() async {
    if (_targetDevice == null) return;

    setState(() {
      _statusMessage = "Conectando a ${_targetDevice!.platformName}...";
    });

    _connectionStateSubscription = _targetDevice!.connectionState.listen((BluetoothConnectionState state) {
      if (state == BluetoothConnectionState.connected) {
        setState(() {
          _isConnected = true;
          _statusMessage = "Conectado. Descubriendo servicios...";
        });
        _discoverServices();
      } else if (state == BluetoothConnectionState.disconnected) {
        setState(() {
          _isConnected = false;
          _statusMessage = "Desconectado. Vuelve a buscar para reconectar.";
          _ledCharacteristic = null;
        });
      }
    });
    
    try {
      // Intenta conectar al dispositivo. Timeout de 15 segundos.
      await _targetDevice!.connect(timeout: const Duration(seconds: 15));
    } catch (e) {
      _showErrorDialog("Error de Conexión", "No se pudo conectar al dispositivo: $e");
       setState(() {
          _statusMessage = "Fallo al conectar. Inténtalo de nuevo.";
        });
    }
  }

  void _disconnectFromDevice() {
    _connectionStateSubscription?.cancel();
    _targetDevice?.disconnect();
  }

  void _discoverServices() async {
    if (_targetDevice == null) return;

    try {
      List<BluetoothService> services = await _targetDevice!.discoverServices();
      for (BluetoothService service in services) {
        if (service.uuid == SERVICE_UUID) {
          for (BluetoothCharacteristic characteristic in service.characteristics) {
            if (characteristic.uuid == CHARACTERISTIC_UUID) {
              setState(() {
                _ledCharacteristic = characteristic;
                _statusMessage = "¡Dispositivo listo para controlar!";
              });
              return; // Salimos de la función una vez encontrada la característica.
            }
          }
        }
      }
       _statusMessage = "Característica del LED no encontrada.";
    } catch (e) {
       _showErrorDialog("Error de Servicios", "No se pudieron descubrir los servicios: $e");
       _statusMessage = "Error al buscar servicios.";
    }
  }
  
  // Escribe un valor en la característica del LED para encenderlo o apagarlo.
  void _writeToLedCharacteristic(String value) async {
    if (_ledCharacteristic == null) {
      _showErrorDialog("Error", "La característica del LED no está disponible.");
      return;
    }
    
    try {
      // Escribimos el valor como una lista de bytes.
      await _ledCharacteristic!.write(value.codeUnits);
    } catch (e) {
       _showErrorDialog("Error de Escritura", "No se pudo enviar el comando al LED: $e");
    }
  }
  
  // Muestra un diálogo de error genérico.
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text("OK"),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Controlador LED Bluetooth"),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Indicador de estado y mensaje
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                   Icon(
                    _isConnected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                    size: 80,
                    color: _isConnected ? Colors.blue : Colors.grey,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const Spacer(),

            // Botones de control del LED, solo visibles si estamos conectados.
            if (_isConnected && _ledCharacteristic != null)
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.lightbulb_outline, color: Colors.white),
                      label: const Text("Encender LED"),
                      onPressed: () => _writeToLedCharacteristic("1"),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 60),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontSize: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.lightbulb, color: Colors.white),
                      label: const Text("Apagar LED"),
                      onPressed: () => _writeToLedCharacteristic("0"),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 60),
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(fontSize: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            
            const Spacer(),

            // Botón principal de acción (Buscar/Desconectar)
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: ElevatedButton(
                onPressed: _isConnected ? _disconnectFromDevice : _toggleScan,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(200, 50),
                  backgroundColor: _isScanning || _isConnected ? Colors.grey : Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isScanning
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_isConnected ? "Desconectar" : "Buscar Dispositivo"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
