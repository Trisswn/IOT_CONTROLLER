import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_gauges/gauges.dart';

import 'smart_home_state.dart';
import 'main.dart';

class BluetoothControlScreen extends StatefulWidget {
  const BluetoothControlScreen({super.key});

  @override
  State<BluetoothControlScreen> createState() => _BluetoothControlScreenState();
}

class _BluetoothControlScreenState extends State<BluetoothControlScreen> {

  BluetoothDevice? _targetDevice;
  BluetoothCharacteristic? _ledCharacteristic;
  BluetoothCharacteristic? _sensorCharacteristic;
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

  SmartHomeState get state => Provider.of<SmartHomeState>(context, listen: false);

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
        _sensorDataSubscription?.cancel();
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
              });
            }
          }
        }
      }
      if (_ledCharacteristic != null && _sensorCharacteristic != null) {
        state.setStatusMessage("¡Dispositivo listo!");
      } else {
        state.setStatusMessage("Error: Faltan características.");
      }
    } catch (e) {
      _showErrorDialog("Error", "No se pudieron descubrir los servicios: $e");
    }
  }

  Future<void> _writeToLedCharacteristic(String value) async {
    if (_ledCharacteristic == null) return;
    try {
      await _ledCharacteristic!.write(value.codeUnits);
      state.setLedState(value == "1");
    } catch (e) {
      _showErrorDialog("Error", "No se pudo enviar el comando: $e");
    }
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(title), content: Text(message), actions: [TextButton(child: const Text("OK"), onPressed: () => Navigator.of(ctx).pop())]));
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SmartHomeState>(
      builder: (context, homeState, child) {
        return Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            title: const Text("Panel de Control"),
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            centerTitle: true,
          ),
          body: ListView(
            padding: const EdgeInsets.all(16.0),
            children: <Widget>[
              _buildStatusCard(homeState),
              const SizedBox(height: 20),

              const Text("Controles", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              
              
              GridView.count(
                crossAxisCount: 2, // Dos columnas
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _buildLightControlCard(homeState),
                  
                ],
              ),
              
              const SizedBox(height: 20),

              const Text("Sensores Ambientales", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),

              if (homeState.isConnected)
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
                _buildDisconnectedSensorPlaceholder(),
            ],
          ),
        );
      },
    );
  }

  // --- Widgets Auxiliares ---

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
  
  
  Widget _buildLightControlCard(SmartHomeState homeState) {
    bool isConnected = homeState.isConnected;
    bool isOn = homeState.ledIsOn;

    // Colores dinámicos según el estado
    Color cardColor = isConnected ? (isOn ? Colors.amber.shade100 : Colors.white) : Colors.grey.shade200;
    Color contentColor = isConnected ? (isOn ? Colors.amber.shade800 : Colors.grey.shade600) : Colors.grey.shade400;
    IconData iconData = isOn ? Icons.lightbulb : Icons.lightbulb_outline;

    return Card(
      elevation: 4,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        onTap: isConnected
            // Lógica para encender/apagar: si está encendido, manda "0"; si no, manda "1"
            ? () => _writeToLedCharacteristic(isOn ? "0" : "1")
            : null, // Deshabilitado si no está conectado
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
              isConnected ? (isOn ? "Encendida" : "Apagada") : "Desconectado",
              style: TextStyle(fontSize: 14, color: contentColor.withOpacity(0.8)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSensorGauge(String title, double value, String unit, double min, double max, Color color) {
    // ... (Este widget no cambia)
    double displayValue = title == "Luz" ? max - value : value;
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
                        value: displayValue.isNaN ? min : displayValue,
                        cornerStyle: CornerStyle.bothCurve,
                        width: 0.2,
                        sizeUnit: GaugeSizeUnit.factor,
                        color: color,
                      )
                    ],
                    annotations: <GaugeAnnotation>[
                      GaugeAnnotation(
                        positionFactor: 0.1,
                        angle: 90,
                        widget: Text(
                          "${displayValue.toStringAsFixed(0)} $unit",
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

  Widget _buildDisconnectedSensorPlaceholder() {
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: const SizedBox(
        height: 150,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "Conecta un dispositivo para ver los datos de los sensores",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }
}