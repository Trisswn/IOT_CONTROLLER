#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <string>
#include "DHT.h"

// --- PINES DE HARDWARE ---
#define LED_PIN 23
#define DHT_PIN 22
#define LDR_PIN 18

// --- CONFIGURACIÓN DEL SENSOR DHT ---
#define DHT_TYPE DHT22
DHT dht(DHT_PIN, DHT_TYPE);

// --- UUIDs ---
#define SERVICE_UUID                  "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define LED_CHARACTERISTIC_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define SENSOR_CHARACTERISTIC_UUID    "a1b2c3d4-e5f6-4a5b-6c7d-8e9f0a1b2c3d"
#define PROFILE_CONFIG_UUID           "c1d2e3f4-a5b6-c7d8-e9f0-a1b2c3d4e5f6"

// --- Variables Globales para Perfil Actual ---
bool profileLightsEnabled = true;
int profileLightOnInterval = 0; // ms, 0 = no parpadeo
int profileLightOffInterval = 0; // ms, 0 = no parpadeo
int profileAutoOffDuration = 0; // SEGUNDOS, 0 = no auto-apagado
bool profileSensorsEnabled = true;
int profileSensorReadInterval = 2000; // ms

// --- Variables de Estado para Lógica de Tiempo ---
unsigned long ledTurnOnTime = 0; // Para auto-apagado
unsigned long lastBlinkToggleTime = 0; // Para parpadeo
bool isLedCurrentlyOnForBlink = false; // Estado actual en parpadeo

// --- Punteros a Características y Servidor BLE ---
BLEServer *pServer = nullptr; // <<< Declarado globalmente
BLECharacteristic *pSensorCharacteristic = nullptr;
BLECharacteristic *pLedCharacteristic = nullptr;
BLECharacteristic *pProfileConfigCharacteristic = nullptr;

// --- Función para Notificar Estado del LED ---
void notifyLedState() {
  // Asegurarse que pLedCharacteristic no sea null antes de usarlo
  if (pLedCharacteristic != nullptr && pServer != nullptr && pServer->getConnectedCount() > 0) { // <<< Añadida verificación de conexión
    pLedCharacteristic->setValue(digitalRead(LED_PIN) == HIGH ? "1" : "0");
    pLedCharacteristic->notify();
    Serial.print("Notificando estado LED: ");
    Serial.println(digitalRead(LED_PIN) == HIGH ? "1" : "0");
  } else {
     Serial.println("No se notifica estado LED (no conectado o característica no lista).");
  }
}

// --- Callbacks para Característica LED ---
class LedCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      const char* value_cstr = pCharacteristic->getValue().c_str();
      String value = value_cstr;
      Serial.print("Comando LED recibido: ");
      Serial.println(value);

      // 1. Verificar si las luces están habilitadas en el perfil
      if (!profileLightsEnabled) {
        Serial.println("Comando LED ignorado (luces deshabilitadas por perfil).");
        return;
      }

      // 2. Verificar si estamos en modo parpadeo
      if (profileLightOnInterval > 0 && profileLightOffInterval > 0) {
         Serial.println("Comando LED ignorado (modo parpadeo activo).");
         return;
      }

      // 3. Si es modo Manual o Auto-Apagado, procesar "1" o "0"
      if (value.length() > 0) {
        bool turnOn = (value.indexOf("1") != -1);

        // --- SIMPLIFICACIÓN: Siempre llama a digitalWrite ---
        digitalWrite(LED_PIN, turnOn ? HIGH : LOW);
        Serial.print("--> digitalWrite ejecutado para: ");
        Serial.println(turnOn ? "ON" : "OFF");
        // --- FIN SIMPLIFICACIÓN ---

        // Lógica específica para Auto-Apagado
        if (turnOn && profileAutoOffDuration > 0) {
          ledTurnOnTime = millis(); // Iniciar/reiniciar temporizador SOLO al encender
          Serial.print("Modo Auto-Apagado activado/reiniciado. Duración: ");
          Serial.print(profileAutoOffDuration);
          Serial.println(" s");
        } else {
          ledTurnOnTime = 0; // Desactivar temporizador si se apaga o no es modo auto-off
        }

        // Siempre notificar el estado resultante a la app
        notifyLedState();
      } else {
          Serial.println("Comando LED ignorado (valor vacío recibido)."); // Log si llega vacío
      }
    }
};

// --- Callbacks para Característica de Configuración de Perfil ---
class ProfileCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        // <<< CORRECCIÓN: Convertir de Arduino String a std::string
        std::string value = pCharacteristic->getValue().c_str();
        Serial.print("Configuración de perfil recibida: ");
        Serial.println(value.c_str());

        size_t lightPos = value.find("L,");
        size_t sensorPos = value.find("S,");
        size_t separatorPos = value.find("|");

        // Variables temporales para sscanf
        int tempLightsEnabled = profileLightsEnabled;
        int tempSensorsEnabled = profileSensorsEnabled;


        if (lightPos != std::string::npos && separatorPos != std::string::npos) {
            std::string lightConfig = value.substr(lightPos + 2, separatorPos - (lightPos + 2));
            // Usar variables temporales int para sscanf
            sscanf(lightConfig.c_str(), "%d,%d,%d,%d",
                   &tempLightsEnabled, &profileLightOnInterval, &profileLightOffInterval, &profileAutoOffDuration);
            profileLightsEnabled = (tempLightsEnabled != 0); // Convertir int a bool
            Serial.printf("  Luces: Hab=%d, On=%d, Off=%d, Auto=%d\n",
                          profileLightsEnabled, profileLightOnInterval, profileLightOffInterval, profileAutoOffDuration);
             ledTurnOnTime = 0;
             lastBlinkToggleTime = 0;
             isLedCurrentlyOnForBlink = false;
             if (!profileLightsEnabled || profileLightOnInterval > 0) {
                 if (digitalRead(LED_PIN) == HIGH) { // Solo notificar si realmente cambia
                    digitalWrite(LED_PIN, LOW);
                    notifyLedState();
                 }
             }
        } else {
          Serial.println("  Error: No se encontró la configuración de luces ('L,...|').");
        }


        if (sensorPos != std::string::npos) {
            std::string sensorConfig = value.substr(sensorPos + 2);
             // Usar variables temporales int para sscanf
            sscanf(sensorConfig.c_str(), "%d,%d",
                   &tempSensorsEnabled, &profileSensorReadInterval);
            profileSensorsEnabled = (tempSensorsEnabled != 0); // Convertir int a bool
            Serial.printf("  Sensores: Hab=%d, Int=%d\n", profileSensorsEnabled, profileSensorReadInterval);
        } else {
          Serial.println("  Error: No se encontró la configuración de sensores ('S,...').");
        }

        // Asegurarse que los intervalos no sean menores a un umbral razonable
        if (profileLightOnInterval > 0 && profileLightOnInterval < 50) profileLightOnInterval = 50;
        if (profileLightOffInterval > 0 && profileLightOffInterval < 50) profileLightOffInterval = 50;
        if (profileSensorReadInterval < 500) profileSensorReadInterval = 500;

        ledTurnOnTime = 0;
        lastBlinkToggleTime = 0;
        isLedCurrentlyOnForBlink = false;
        if (!profileLightsEnabled || (profileLightOnInterval > 0 && profileLightOffInterval > 0)) {
            if (digitalRead(LED_PIN) == HIGH) {
                digitalWrite(LED_PIN, LOW);
                notifyLedState();
            }
        }
    }
};

// --- SETUP ---
void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);
  dht.begin();

  Serial.println("Iniciando BLE...");
  BLEDevice::init("ESP32-LED");
  pServer = BLEDevice::createServer(); // <<< Inicializa el pServer global
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Característica LED
  pLedCharacteristic = pService->createCharacteristic(
                                         LED_CHARACTERISTIC_UUID,
                                         BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY
                                       );
  pLedCharacteristic->addDescriptor(new BLE2902());
  pLedCharacteristic->setCallbacks(new LedCallbacks());
  pLedCharacteristic->setValue("0");

  // Característica Sensores
  pSensorCharacteristic = pService->createCharacteristic(
                                         SENSOR_CHARACTERISTIC_UUID,
                                         BLECharacteristic::PROPERTY_NOTIFY
                                        );
  pSensorCharacteristic->addDescriptor(new BLE2902());

  // Característica Configuración de Perfil
   pProfileConfigCharacteristic = pService->createCharacteristic(
                                         PROFILE_CONFIG_UUID,
                                         BLECharacteristic::PROPERTY_WRITE
                                        );
   pProfileConfigCharacteristic->setCallbacks(new ProfileCallbacks());

  // Iniciar servicio y advertising
  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising(); // Correcto

  Serial.println("Servidor BLE iniciado y anunciando. Esperando conexiones...");
  Serial.println("Sensores: DHT22 y LDR.");
}

// --- LOOP ---
void loop() {
  unsigned long currentTime = millis();

  // Lógica de Control del LED
  if (profileLightsEnabled) {
    if (profileLightOnInterval > 0 && profileLightOffInterval > 0) { // Parpadeo
      unsigned long interval = isLedCurrentlyOnForBlink ? profileLightOnInterval : profileLightOffInterval;
      if (currentTime - lastBlinkToggleTime >= interval) {
        isLedCurrentlyOnForBlink = !isLedCurrentlyOnForBlink;
        digitalWrite(LED_PIN, isLedCurrentlyOnForBlink ? HIGH : LOW);
        lastBlinkToggleTime = currentTime;
        notifyLedState();
        // Serial.print("Parpadeo - LED: "); Serial.println(isLedCurrentlyOnForBlink ? "ON" : "OFF"); // Opcional: reducir logs
      }
    }
    else if (profileAutoOffDuration > 0 && ledTurnOnTime > 0) { // Auto-Apagado
      if (currentTime - ledTurnOnTime >= (unsigned long)profileAutoOffDuration * 1000) {
        if (digitalRead(LED_PIN) == HIGH) {
           digitalWrite(LED_PIN, LOW);
           ledTurnOnTime = 0;
           notifyLedState();
           Serial.println("Auto-Apagado ejecutado.");
        }
      }
    }
    else { // Manual o Deshabilitado (resetea timers)
        if (ledTurnOnTime != 0) ledTurnOnTime = 0;
        if (lastBlinkToggleTime != 0) lastBlinkToggleTime = 0;
        if (isLedCurrentlyOnForBlink) isLedCurrentlyOnForBlink = false; // Asegura estado correcto si salimos de parpadeo
    }
  } else { // Luces deshabilitadas
      if (digitalRead(LED_PIN) == HIGH) {
          digitalWrite(LED_PIN, LOW);
          notifyLedState();
      }
      ledTurnOnTime = 0;
      lastBlinkToggleTime = 0;
      isLedCurrentlyOnForBlink = false;
  }

  // Lógica de Lectura y Envío de Sensores
  static unsigned long lastSensorReadTime = 0;

  // Solo leer/enviar si el perfil lo permite Y ha pasado el intervalo
  if (profileSensorsEnabled && (currentTime - lastSensorReadTime >= profileSensorReadInterval)) {
    lastSensorReadTime = currentTime;

    float temp = dht.readTemperature(false);
    float humidity = dht.readHumidity();
    int lightValue = analogRead(LDR_PIN);

    if (isnan(temp) || isnan(humidity)) {
      Serial.println("Error al leer del sensor DHT!");
    } else {
      char sensorData[30];
      snprintf(sensorData, sizeof(sensorData), "%.1f,%.1f,%d", temp, humidity, lightValue);

      // <<< CORRECCIÓN: Quitar la comprobación getSubscribedCount() >>>
      // Verificar pServer y pSensorCharacteristic antes de usar
      if (pServer != nullptr && pSensorCharacteristic != nullptr && pServer->getConnectedCount() > 0) {
        pSensorCharacteristic->setValue(sensorData);
        pSensorCharacteristic->notify();
        // Serial.print("Enviando datos sensores: "); Serial.println(sensorData); // Opcional: reducir logs
      } else {
        // Serial.print("Datos sensores (no enviados - sin conexión): "); Serial.println(sensorData); // Opcional: reducir logs
      }
    }
  }

  delay(50); // Delay corto para estabilidad
}