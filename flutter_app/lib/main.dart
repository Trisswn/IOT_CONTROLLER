// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:io';

import 'smart_home_state.dart';
import 'bluetooth_control_screen.dart';

// --- IDs GLOBALES PARA BLUETOOTH ---

final Guid SERVICE_UUID = Guid("4fafc201-1fb5-459e-8fcc-c5c9c331914b");

// Este es para controlar el LED (escribir datos).
final Guid LED_CHARACTERISTIC_UUID = Guid("beb5483e-36e1-4688-b7f5-ea07361b26a8");

// Este es para recibir datos de los sensores (notificaciones).
final Guid SENSOR_CHARACTERISTIC_UUID = Guid("a1b2c3d4-e5f6-4a5b-6c7d-8e9f0a1b2c3d");

final Guid PROFILE_CONFIG_UUID = Guid("c1d2e3f4-a5b6-c7d8-e9f0-a1b2c3d4e5f6");

const String TARGET_DEVICE_NAME = "ESP32-LED";


void main() {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isAndroid) {
    FlutterBluePlus.turnOn();
  }

  runApp(
    ChangeNotifierProvider(
      create: (context) => SmartHomeState(),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Control Smart Home',
      debugShowCheckedModeBanner: false, 
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const BluetoothControlScreen(),
    );
  }
}