// lib/main.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:io';

import 'smart_home_state.dart';
import 'bluetooth_control_screen.dart';
import 'app_colors.dart'; // <<< 1. IMPORTAR NUEVOS COLORES

// --- IDs GLOBALES PARA BLUETOOTH ---
// ... (Sin cambios aquí)
final Guid SERVICE_UUID = Guid("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
final Guid LED_CHARACTERISTIC_UUID = Guid("beb5483e-36e1-4688-b7f5-ea07361b26a8");
final Guid SENSOR_CHARACTERISTIC_UUID = Guid("a1b2c3d4-e5f6-4a5b-6c7d-8e9f0a1b2c3d");
final Guid PROFILE_CONFIG_UUID = Guid("c1d2e3f4-a5b6-c7d8-e9f0-a1b2c3d4e5f6");
const String TARGET_DEVICE_NAME = "ESP32-MultiLED";


void main() {
  // ... (Sin cambios aquí)
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
      // --- 2. ACTUALIZAR THEMEDATA ---
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          background: AppColors.background,
          onBackground: AppColors.textPrimary,
          surface: AppColors.card,
          onSurface: AppColors.textPrimary,
          primary: AppColors.primary,
          onPrimary: AppColors.textOnPrimary,
          secondary: AppColors.sensorHumid, // Color secundario
          error: AppColors.accentRed, // Color de error
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        // Definir estilos globales para AppBar, Tarjetas y Botones
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.background, // Fondo limpio
          foregroundColor: AppColors.textPrimary, // Texto oscuro
          elevation: 0, // Sin sombra
          centerTitle: true,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600, // Semi-bold
            color: AppColors.textPrimary,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 2, // Sombra suave
          color: AppColors.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.0), // Esquinas redondeadas
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary, // Color primario
            foregroundColor: AppColors.textOnPrimary, // Texto blanco
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0), // Botones redondeados
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 22), // Para "Controles"
          titleMedium: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600, fontSize: 18), // Para títulos de tarjetas
          bodyMedium: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          labelLarge: TextStyle(color: AppColors.textOnPrimary, fontWeight: FontWeight.w600, fontSize: 16), // Texto de botones
        ),
      ),
      // --- Fin de THEMEDATA ---
      home: const BluetoothControlScreen(),
    );
  }
}