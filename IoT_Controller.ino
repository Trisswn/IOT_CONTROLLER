#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <string>
#include "DHT.h" // Librería para el sensor DHT
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <ESP32Servo.h> // <<<--- LIBRERÍA SERVO AÑADIDA

// --- PINES DE HARDWARE ---
#define DHT_PIN 18         // Pin para el sensor DHT22
#define SERVO_PIN 19       // <<<--- PIN PARA EL SERVO (Elige un GPIO disponible, ej: 19)

// Definimos los pines para 3 LEDs
const int ledPins[] = {25, 26, 27}; // GPIOs para Sala, Cocina, Dormitorio
const int NUM_LEDS = sizeof(ledPins) / sizeof(ledPins[0]); //

// --- CONFIGURACIÓN DEL SENSOR DHT ---
#define DHT_TYPE DHT22   // Define el tipo de sensor DHT
DHT dht(DHT_PIN, DHT_TYPE); //

// --- CONFIGURACIÓN LCD ---
// (Dirección 0x27 es la más común, puede ser 0x3F)
LiquidCrystal_I2C lcd(0x27, 16, 2); // (Dirección I2C, 16 caracteres, 2 filas)

// --- CONFIGURACIÓN SERVO ---
Servo doorServo; // Crear objeto Servo
int servoPos = 0; // Posición inicial (0 grados = cerrado)

// --- UUIDs ---
#define SERVICE_UUID                  "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define LED_CHARACTERISTIC_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define SENSOR_CHARACTERISTIC_UUID    "a1b2c3d4-e5f6-4a5b-6c7d-8e9f0a1b2c3d"
#define PROFILE_CONFIG_UUID           "c1d2e3f4-a5b6-c7d8-e9f0-a1b2c3d4e5f6"
#define SERVO_CHARACTERISTIC_UUID     "f1a2b3c4-d5e6-f7a8-b9c0-d1e2f3a4b5c6" // <<<--- NUEVO UUID PARA EL SERVO

// --- VARIABLE GLOBAL PARA NOMBRE DE PERFIL ---
String currentProfileName = "Desconectado"; // Valor por defecto

// --- Estructura para el estado y configuración de cada LED ---
struct LedState {
  bool profileEnabled = true;
  int profileLightOnInterval = 0;
  int profileLightOffInterval = 0;
  int profileAutoOffDuration = 0;
  unsigned long ledTurnOnTime = 0;
  unsigned long lastBlinkToggleTime = 0;
  bool isLedCurrentlyOnForBlink = false;
};

// Array para guardar el estado de cada LED
LedState ledStates[NUM_LEDS];

// --- Variables Globales para Perfil Actual (Sensores) ---
bool profileSensorsEnabled = true;
int profileSensorReadInterval = 2000; // ms

// --- Punteros a Características y Servidor BLE ---
BLEServer *pServer = nullptr;
BLECharacteristic *pSensorCharacteristic = nullptr;
BLECharacteristic *pLedCharacteristic = nullptr;
BLECharacteristic *pProfileConfigCharacteristic = nullptr;
BLECharacteristic *pServoCharacteristic = nullptr; // <<<--- NUEVO PUNTERO PARA SERVO

// --- Función para Notificar Estado de TODOS los LEDs ---
void notifyLedStates() {
  if (pLedCharacteristic != nullptr && pServer != nullptr && pServer->getConnectedCount() > 0) {
    char combinedState[NUM_LEDS * 2];
    strcpy(combinedState, "");

    for (int i = 0; i < NUM_LEDS; i++) {
      strcat(combinedState, digitalRead(ledPins[i]) == HIGH ? "1" : "0");
      if (i < NUM_LEDS - 1) {
        strcat(combinedState, ",");
      }
    }

    pLedCharacteristic->setValue(combinedState);
    pLedCharacteristic->notify();
    Serial.print("[notifyLedStates] Notificando: "); Serial.println(combinedState);
  }
}

// --- Callbacks para Característica LED ---
class LedCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String value = pCharacteristic->getValue();
      Serial.println("\n--- [LedCallbacks::onWrite] ---");
      Serial.print("Comando LED recibido: '"); Serial.print(value); Serial.println("'");

      int commaIndex = value.indexOf(',');
      if (commaIndex == -1) {
        Serial.println("Error: Formato de comando LED inválido.");
        return;
      }

      int ledIndex = value.substring(0, commaIndex).toInt();
      int ledValue = value.substring(commaIndex + 1).toInt();
      if (ledIndex < 0 || ledIndex >= NUM_LEDS) {
        Serial.printf("Error: Índice de LED inválido (%d).\n", ledIndex);
        return;
      }

      LedState &currentLed = ledStates[ledIndex];

      Serial.printf("Procesando para LED %d. Valor deseado: %d\n", ledIndex, ledValue);
      if (!currentLed.profileEnabled) {
        Serial.println("--> Comando ignorado (LED deshabilitado por perfil).");
        return;
      }

      bool isBlinkingMode = (currentLed.profileLightOnInterval > 0 && currentLed.profileLightOffInterval > 0);
      if (isBlinkingMode) {
         Serial.println("--> Comando ignorado (modo parpadeo activo).");
         return;
      }

      bool turnOn = (ledValue == 1);
      digitalWrite(ledPins[ledIndex], turnOn ? HIGH : LOW);
      Serial.println("   digitalWrite ejecutado.");

      bool isAutoOffMode = (currentLed.profileAutoOffDuration > 0);
      if (turnOn && isAutoOffMode) {
        currentLed.ledTurnOnTime = millis();
        Serial.printf("   Temporizador Auto-Off LED %d iniciado (%d s).\n", ledIndex, currentLed.profileAutoOffDuration);
      } else {
        if (currentLed.ledTurnOnTime != 0) {
           Serial.printf("   Temporizador Auto-Off LED %d reseteado.\n", ledIndex);
           currentLed.ledTurnOnTime = 0;
        }
      }
      notifyLedStates();
      Serial.println("--- Fin [LedCallbacks::onWrite] ---\n");
    }
};

// <<<--- CALLBACK PARA SERVO (SIN CAMBIOS RESPECTO AL ANTERIOR CORREGIDO) ---
class ServoCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        String valueStr = pCharacteristic->getValue(); // Obtener como Arduino String
        std::string value = valueStr.c_str(); // Convertir a std::string si es necesario

        Serial.println("\n--- [ServoCallbacks::onWrite] ---");
        Serial.print("Comando Servo recibido: '"); Serial.print(value.c_str()); Serial.println("'");

        if (value == "TOGGLE") {
            if (servoPos == 0) {
                servoPos = 90;
                doorServo.write(servoPos);
                Serial.println("  Moviendo servo a 90 grados (Abierto).");
            } else {
                servoPos = 0;
                doorServo.write(servoPos);
                Serial.println("  Moviendo servo a 0 grados (Cerrado).");
            }
        } else {
            Serial.print("  Comando no reconocido: "); Serial.println(value.c_str());
        }
         Serial.println("--- Fin [ServoCallbacks::onWrite] ---\n");
    }
};
// <<<--- FIN CALLBACK SERVO ---


// --- Callbacks para Característica de Configuración de Perfil ---
// ... (Sin cambios) ...
class ProfileCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        std::string value = pCharacteristic->getValue().c_str();
        Serial.println("\n--- [ProfileCallbacks::onWrite] ---");
        Serial.print("Config de Perfil recibida: "); Serial.println(value.c_str());

        size_t namePos = value.find("NAME:");
        size_t configPos = value.find("||");

        if (namePos == 0 && configPos != std::string::npos) {
            std::string nameStr = value.substr(5, configPos - 5);
            currentProfileName = nameStr.c_str();
            Serial.print("  Perfil detectado: '"); Serial.print(currentProfileName); Serial.println("'");
            lcd.clear();
            lcd.setCursor(0, 0);
            lcd.print(currentProfileName);
            value = value.substr(configPos + 2);
            Serial.print("  Config restante para strtok: '"); Serial.println(value.c_str());
        } else {
            Serial.println("    Advertencia: Formato de perfil no reconocido (sin 'NAME:||').");
            lcd.clear();
            lcd.setCursor(0, 0);
            lcd.print(currentProfileName);
        }

        for(int i = 0; i < NUM_LEDS; i++) {
            ledStates[i].ledTurnOnTime = 0;
            ledStates[i].lastBlinkToggleTime = 0;
            ledStates[i].isLedCurrentlyOnForBlink = false;
        }
        Serial.println("   Timers de todos los LEDs reseteados.");
        char* profileStr = strdup(value.c_str());
        char* token = strtok(profileStr, "|");
        while (token != NULL) {
            Serial.printf("   Procesando token: '%s'\n", token);
            if (token[0] == 'L' && isdigit(token[1])) {
                int ledIndex = token[1] - '0';
                if (ledIndex >= 0 && ledIndex < NUM_LEDS) {
                    LedState &currentLed = ledStates[ledIndex];
                    int tempEnabled, tempOn, tempOff, tempAuto;
                    int scannedValues = sscanf(token + 3, "%d,%d,%d,%d", &tempEnabled, &tempOn, &tempOff, &tempAuto);
                    if (scannedValues == 4) {
                        currentLed.profileEnabled = (tempEnabled != 0);
                        currentLed.profileLightOnInterval = tempOn;
                        currentLed.profileLightOffInterval = tempOff;
                        currentLed.profileAutoOffDuration = tempAuto;
                        if (currentLed.profileLightOnInterval > 0 && currentLed.profileLightOnInterval < 50) currentLed.profileLightOnInterval = 50;
                        if (currentLed.profileLightOffInterval > 0 && currentLed.profileLightOffInterval < 50) currentLed.profileLightOffInterval = 50;
                        Serial.printf("     LED %d Config: Hab=%d, On=%d, Off=%d, Auto=%d\n", ledIndex,
                                      currentLed.profileEnabled, currentLed.profileLightOnInterval,
                                      currentLed.profileLightOffInterval, currentLed.profileAutoOffDuration);
                        bool isBlinkingNow = currentLed.profileLightOnInterval > 0 && currentLed.profileLightOffInterval > 0;
                        if (!currentLed.profileEnabled || isBlinkingNow) {
                            if (digitalRead(ledPins[ledIndex]) == HIGH) {
                                Serial.printf("     Forzando apagado LED %d (Deshab/Parpadeo)\n", ledIndex);
                                digitalWrite(ledPins[ledIndex], LOW);
                            }
                        } else {
                           if (digitalRead(ledPins[ledIndex]) == HIGH) {
                                Serial.printf("     Forzando apagado LED %d (Manual/AutoOff)\n", ledIndex);
                                digitalWrite(ledPins[ledIndex], LOW);
                           }
                        }
                    } else {
                        Serial.printf("     Error parseando config LED %d: Se esperaban 4 valores, se obtuvieron %d.\n", ledIndex, scannedValues);
                    }
                } else {
                    Serial.printf("     Error: Índice de LED inválido en token '%s'.\n", token);
                }
            }
            else if (token[0] == 'S') {
                int tempEnabled, tempInterval;
                int scannedValues = sscanf(token + 2, "%d,%d", &tempEnabled, &tempInterval);
                if (scannedValues == 2) {
                    profileSensorsEnabled = (tempEnabled != 0);
                    profileSensorReadInterval = tempInterval;
                    if (profileSensorReadInterval < 500) profileSensorReadInterval = 500;
                    Serial.printf("     Sensor Config: Hab=%d, Int=%d\n", profileSensorsEnabled, profileSensorReadInterval);
                } else {
                    Serial.printf("     Error parseando config Sensor: Se esperaban 2 valores, se obtuvieron %d.\n", scannedValues);
                }
            } else {
                Serial.printf("     Token desconocido: '%s'\n", token);
            }
            token = strtok(NULL, "|");
        }
        free(profileStr);
        notifyLedStates();
        Serial.println("--- Fin [ProfileCallbacks::onWrite] ---\n");
    }
};


// --- SETUP ---
void setup() {
  Serial.begin(115200);

  // --- INICIAR LCD ---
  Wire.begin(21, 22);
  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print(currentProfileName);
  lcd.setCursor(0, 1);
  lcd.print("Buscando App...");
  // --- FIN LCD ---

  // --- INICIAR SERVO ---
  doorServo.attach(SERVO_PIN);
  doorServo.write(servoPos);
  Serial.print("Servo iniciado en pin "); Serial.print(SERVO_PIN); Serial.println(" a 0 grados.");
  // --- FIN SERVO ---

  // Configurar pines de LED
  for (int i = 0; i < NUM_LEDS; i++) {
    pinMode(ledPins[i], OUTPUT);
    digitalWrite(ledPins[i], LOW);
  }
  dht.begin();

  Serial.println("Iniciando BLE...");
  BLEDevice::init("ESP32-MultiLED");
  pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Característica LED
  pLedCharacteristic = pService->createCharacteristic(
                         LED_CHARACTERISTIC_UUID,
                         BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_NOTIFY
                       );
  pLedCharacteristic->addDescriptor(new BLE2902());
  pLedCharacteristic->setCallbacks(new LedCallbacks());
  char initialLedState[NUM_LEDS * 2] = {0};
  for(int i=0; i<NUM_LEDS; ++i) {
      strcat(initialLedState, "0");
      if (i < NUM_LEDS - 1) strcat(initialLedState, ",");
  }
  pLedCharacteristic->setValue(initialLedState);

  // Característica Sensores
  pSensorCharacteristic = pService->createCharacteristic(
                            SENSOR_CHARACTERISTIC_UUID,
                            BLECharacteristic::PROPERTY_NOTIFY
                          );
  pSensorCharacteristic->addDescriptor(new BLE2902());

  // Característica Perfil
   pProfileConfigCharacteristic = pService->createCharacteristic(
                                    PROFILE_CONFIG_UUID,
                                    BLECharacteristic::PROPERTY_WRITE
                                );
   pProfileConfigCharacteristic->setCallbacks(new ProfileCallbacks());

  // <<<--- CARACTERÍSTICA SERVO CORREGIDA ---
  pServoCharacteristic = pService->createCharacteristic(
                           SERVO_CHARACTERISTIC_UUID,
                           // AÑADIR PROPERTY_WRITE_NR PARA PERMITIR ESCRITURA SIN RESPUESTA
                           BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_WRITE_NR
                         );
  pServoCharacteristic->setCallbacks(new ServoCallbacks());
  String initialServoPosStr = String(servoPos);
  pServoCharacteristic->setValue(initialServoPosStr); // Valor inicial
  // <<<--- FIN CARACTERÍSTICA SERVO ---

  // Iniciar Servicio y Advertising
  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("Servidor BLE iniciado. Esperando conexiones...");
  Serial.printf("Controlando %d LEDs. Sensores: DHT22. Servo: Pin %d\n", NUM_LEDS, SERVO_PIN);
  delay(300);
}

// --- LOOP ---
// ... (El loop completo sin cambios) ...
void loop() {
  unsigned long currentTime = millis();
  static bool clientConnected = false;
  bool nowConnected = (pServer->getConnectedCount() > 0);

  if (nowConnected && !clientConnected) {
      clientConnected = true;
      Serial.println("Cliente Conectado.");
      lcd.setCursor(0,1);
      lcd.print("Recibiendo...");
      for (int i = 11; i < 16; i++) lcd.print(" ");
  } else if (!nowConnected && clientConnected) {
      clientConnected = false;
      currentProfileName = "Desconectado";
      Serial.println("Cliente Desconectado.");
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(currentProfileName);
      lcd.setCursor(0, 1);
      lcd.print("Buscando App...");
  }


  for (int i = 0; i < NUM_LEDS; i++) {
    LedState &currentLed = ledStates[i];
    if (currentLed.profileEnabled) {
      if (currentLed.profileLightOnInterval > 0 && currentLed.profileLightOffInterval > 0) {
        unsigned long interval = currentLed.isLedCurrentlyOnForBlink ?
                                 currentLed.profileLightOnInterval : currentLed.profileLightOffInterval;
        if (currentTime - currentLed.lastBlinkToggleTime >= interval) {
          currentLed.isLedCurrentlyOnForBlink = !currentLed.isLedCurrentlyOnForBlink;
          digitalWrite(ledPins[i], currentLed.isLedCurrentlyOnForBlink ? HIGH : LOW);
          currentLed.lastBlinkToggleTime = currentTime;
          notifyLedStates();
        }
      }
      else if (currentLed.profileAutoOffDuration > 0 && currentLed.ledTurnOnTime > 0) {
        if (currentTime - currentLed.ledTurnOnTime >= (unsigned long)currentLed.profileAutoOffDuration * 1000) {
          if (digitalRead(ledPins[i]) == HIGH) {
             Serial.printf("[Loop] Auto-Apagado LED %d ejecutándose...\n", i);
             digitalWrite(ledPins[i], LOW);
             currentLed.ledTurnOnTime = 0;
             notifyLedStates();
             Serial.printf("[Loop] Auto-Apagado LED %d completado.\n", i);
          } else {
              currentLed.ledTurnOnTime = 0;
          }
        }
      }
      else {
          if (currentLed.ledTurnOnTime != 0) currentLed.ledTurnOnTime = 0;
          if (currentLed.lastBlinkToggleTime != 0) currentLed.lastBlinkToggleTime = 0;
          if (currentLed.isLedCurrentlyOnForBlink) currentLed.isLedCurrentlyOnForBlink = false;
      }
    } else {
        if (digitalRead(ledPins[i]) == HIGH) {
            Serial.printf("[Loop] LED %d deshabilitado, apagando...\n", i);
            digitalWrite(ledPins[i], LOW);
            notifyLedStates();
        }
        currentLed.ledTurnOnTime = 0;
        currentLed.lastBlinkToggleTime = 0;
        currentLed.isLedCurrentlyOnForBlink = false;
    }
  }

  static unsigned long lastSensorReadTime = 0;
  if (profileSensorsEnabled && (currentTime - lastSensorReadTime >= profileSensorReadInterval)) {
    lastSensorReadTime = currentTime;

    float temp = dht.readTemperature(false);
    float humidity = dht.readHumidity();

    if (isnan(temp) || isnan(humidity)) {
      Serial.println("[Loop] Error al leer del sensor DHT!");
      if(clientConnected) {
         lcd.setCursor(0, 1);
         lcd.print("Error Sensor DHT");
         for (int i = 15; i < 16; i++) lcd.print(" ");
      }

    } else {
      char sensorData[20];
      snprintf(sensorData, sizeof(sensorData), "%.1f,%.1f", temp, humidity);

      if(clientConnected) {
        char lcdLine[17];
        snprintf(lcdLine, sizeof(lcdLine), "T:%.1fC  H:%.0f%%", temp, humidity);
        lcd.setCursor(0, 1);
        lcd.print(lcdLine);
        for (int i = strlen(lcdLine); i < 16; i++) {
           lcd.print(" ");
        }
      }

      if (nowConnected && pSensorCharacteristic != nullptr) {
        pSensorCharacteristic->setValue(sensorData);
        pSensorCharacteristic->notify();
      }
    }
  }

  delay(50); // Pausa general
}