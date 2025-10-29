#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <string>
#include "DHT.h" // Librería para el sensor DHT

// --- LIBRERÍAS PARA LCD ---
#include <Wire.h> 
#include <LiquidCrystal_I2C.h>

// --- PINES DE HARDWARE ---
#define DHT_PIN 18         // Pin para el sensor DHT22

// Definimos los pines para 3 LEDs
const int ledPins[] = {25, 26, 27}; // GPIOs para Sala, Cocina, Dormitorio
const int NUM_LEDS = sizeof(ledPins) / sizeof(ledPins[0]);

// --- CONFIGURACIÓN DEL SENSOR DHT ---
#define DHT_TYPE DHT22   // Define el tipo de sensor DHT
DHT dht(DHT_PIN, DHT_TYPE);

// --- CONFIGURACIÓN LCD ---
// La dirección I2C común es 0x27. Si no funciona, prueba 0x3F.
LiquidCrystal_I2C lcd(0x27, 16, 2); // (Dirección I2C, 16 caracteres, 2 filas)

// --- UUIDs ---
#define SERVICE_UUID                  "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define LED_CHARACTERISTIC_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26a8" 
#define SENSOR_CHARACTERISTIC_UUID    "a1b2c3d4-e5f6-4a5b-6c7d-8e9f0a1b2c3d" 
#define PROFILE_CONFIG_UUID           "c1d2e3f4-a5b6-c7d8-e9f0-a1b2c3d4e5f6" 

// --- VARIABLE GLOBAL PARA NOMBRE DE PERFIL ---
String currentProfileName = "Desconectado"; // Valor por defecto

// --- Estructura para el estado y configuración de cada LED ---
struct LedState {
  bool profileEnabled = true;     // ¿Gestionado por el perfil actual?
  int profileLightOnInterval = 0; // ms, 0 = no parpadeo
  int profileLightOffInterval = 0;// ms, 0 = no parpadeo
  int profileAutoOffDuration = 0; // SEGUNDOS, 0 = no auto-apagado

  // Estado dinámico
  unsigned long ledTurnOnTime = 0;       // Timestamp para auto-apagado
  unsigned long lastBlinkToggleTime = 0;// Timestamp para parpadeo
  bool isLedCurrentlyOnForBlink = false;// Estado *interno* para parpadeo
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

// --- Función para Notificar Estado de TODOS los LEDs ---
// Envía el estado actual (0 o 1) de todos los LEDs como "state0,state1,state2"
void notifyLedStates() {
  if (pLedCharacteristic != nullptr && pServer != nullptr && pServer->getConnectedCount() > 0) {
    char combinedState[NUM_LEDS * 2]; // Suficiente espacio para "0,1,0" etc.
    strcpy(combinedState, ""); // Iniciar cadena vacía

    for (int i = 0; i < NUM_LEDS; i++) {
      strcat(combinedState, digitalRead(ledPins[i]) == HIGH ? "1" : "0");
      if (i < NUM_LEDS - 1) {
        strcat(combinedState, ",");
      }
    }

    pLedCharacteristic->setValue(combinedState);
    pLedCharacteristic->notify();
    Serial.print("[notifyLedStates] Notificando: "); Serial.println(combinedState); // DEBUG
  }
}

// --- Callbacks para Característica LED ---
// Se ejecuta cuando la app escribe un comando tipo "index,value"
class LedCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String value = pCharacteristic->getValue();
      Serial.println("\n--- [LedCallbacks::onWrite] ---");
      Serial.print("Comando LED recibido: '"); Serial.print(value); Serial.println("'");

      // Parsear el comando "index,value"
      int commaIndex = value.indexOf(',');
      if (commaIndex == -1) {
        Serial.println("Error: Formato de comando LED inválido (falta coma).");
        Serial.println("--- Fin [LedCallbacks::onWrite] ---\n");
        return;
      }

      int ledIndex = value.substring(0, commaIndex).toInt();
      int ledValue = value.substring(commaIndex + 1).toInt();

      // Validar índice
      if (ledIndex < 0 || ledIndex >= NUM_LEDS) {
        Serial.printf("Error: Índice de LED inválido (%d).\n", ledIndex);
        Serial.println("--- Fin [LedCallbacks::onWrite] ---\n");
        return;
      }

      // Lógica de control basada en perfil (para ESTE LED)
      LedState &currentLed = ledStates[ledIndex]; // Referencia

      Serial.printf("Procesando para LED %d. Valor deseado: %d\n", ledIndex, ledValue);
      Serial.print("¿Habilitado por perfil? "); Serial.println(currentLed.profileEnabled ? "Sí" : "No");

      if (!currentLed.profileEnabled) {
        Serial.println("--> Comando ignorado (LED deshabilitado por perfil).");
        Serial.println("--- Fin [LedCallbacks::onWrite] ---\n");
        return;
      }

      bool isBlinkingMode = (currentLed.profileLightOnInterval > 0 && currentLed.profileLightOffInterval > 0);
      Serial.print("¿Modo parpadeo activo? "); Serial.println(isBlinkingMode ? "Sí" : "No");
      if (isBlinkingMode) {
         Serial.println("--> Comando ignorado (modo parpadeo activo para este LED).");
         Serial.println("--- Fin [LedCallbacks::onWrite] ---\n");
         return;
      }

      // Aplicar comando (Modo Manual o Auto-Apagado)
      bool turnOn = (ledValue == 1);
      Serial.print("Ejecutando digitalWrite...");
      digitalWrite(ledPins[ledIndex], turnOn ? HIGH : LOW);
      Serial.println(" ¡Hecho!");

      // Lógica Auto-Apagado para este LED
      bool isAutoOffMode = (currentLed.profileAutoOffDuration > 0);
      Serial.print("¿Modo Auto-Apagado activo? "); Serial.println(isAutoOffMode ? "Sí" : "No");
      if (turnOn && isAutoOffMode) {
        currentLed.ledTurnOnTime = millis();
        Serial.print("--> Temporizador Auto-Apagado (LED "); Serial.print(ledIndex); Serial.print(") iniciado/reiniciado. Duración: ");
        Serial.print(currentLed.profileAutoOffDuration); Serial.println(" s");
      } else {
        if (currentLed.ledTurnOnTime != 0) {
            Serial.print("--> Temporizador Auto-Apagado (LED "); Serial.print(ledIndex); Serial.println(") reseteado.");
            currentLed.ledTurnOnTime = 0;
        }
      }

      // Notificar el estado de TODOS los LEDs
      Serial.println("Llamando a notifyLedStates()...");
      notifyLedStates();

      Serial.println("--- Fin [LedCallbacks::onWrite] ---\n");
    }
};

// --- Callbacks para Característica de Configuración de Perfil ---
// Formato esperado: "NAME:NombrePerfil||L0,ena,on,off,auto|L1,ena,on,off,auto|L2,ena,on,off,auto|S,ena,int"
class ProfileCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        std::string value = pCharacteristic->getValue().c_str();
        Serial.println("\n--- [ProfileCallbacks::onWrite] ---");
        Serial.print("Config de Perfil recibida: "); Serial.println(value.c_str());

        // --- INICIO DE CORRECCIÓN (Robusto parseo de nombre) ---
        size_t namePos = value.find("NAME:");
        size_t configPos = value.find("||"); // <-- CORREGIDO: Buscar solo "||"

        if (namePos == 0 && configPos != std::string::npos) {
            // Extrae el nombre (ej: "Mi Perfil")
            std::string nameStr = value.substr(5, configPos - 5); 
            currentProfileName = nameStr.c_str(); // Guarda en variable global
            
            Serial.print("  Perfil detectado: '"); Serial.print(currentProfileName); Serial.println("'");
            
            // Actualizar LCD con el nombre
            lcd.clear(); 
            lcd.setCursor(0, 0); 
            lcd.print(currentProfileName); // Muestra el nuevo nombre

            // Recortar 'value' para el resto del parsing
            value = value.substr(configPos + 2); // value ahora es "L0,ena,..."
            Serial.print("  Config restante para strtok: '"); Serial.println(value.c_str());
        } else {
            // Mensaje de error actualizado
            Serial.println("    Advertencia: Formato de perfil no reconocido (sin 'NAME:||').");
            // Limpiar y mostrar el último nombre conocido
            lcd.clear();
            lcd.setCursor(0, 0);
            lcd.print(currentProfileName); // Muestra "Desconectado" o el último nombre
        }
        // --- FIN DE CORRECCIÓN ---


        // Resetear timers de todos los LEDs antes de aplicar el nuevo perfil
        for(int i = 0; i < NUM_LEDS; i++) {
            ledStates[i].ledTurnOnTime = 0;
            ledStates[i].lastBlinkToggleTime = 0;
            ledStates[i].isLedCurrentlyOnForBlink = false;
        }
        Serial.println("   Timers de todos los LEDs reseteados.");

        char* profileStr = strdup(value.c_str()); // Duplicar para poder usar strtok
        char* token = strtok(profileStr, "|");

        while (token != NULL) {
            Serial.printf("   Procesando token: '%s'\n", token);
            // Configuración LED (ej: "L0,1,1000,500,0")
            if (token[0] == 'L' && isdigit(token[1])) {
                int ledIndex = token[1] - '0'; // Convertir char '0', '1', etc. a int
                if (ledIndex >= 0 && ledIndex < NUM_LEDS) {
                    LedState &currentLed = ledStates[ledIndex];
                    int tempEnabled, tempOn, tempOff, tempAuto;

                    // Parsear los 4 valores después de "Lx,"
                    int scannedValues = sscanf(token + 3, "%d,%d,%d,%d",
                                               &tempEnabled, &tempOn, &tempOff, &tempAuto);

                    if (scannedValues == 4) {
                        currentLed.profileEnabled = (tempEnabled != 0);
                        currentLed.profileLightOnInterval = tempOn;
                        currentLed.profileLightOffInterval = tempOff;
                        currentLed.profileAutoOffDuration = tempAuto;

                        // Validar y ajustar intervalos mínimos
                        if (currentLed.profileLightOnInterval > 0 && currentLed.profileLightOnInterval < 50) currentLed.profileLightOnInterval = 50;
                        if (currentLed.profileLightOffInterval > 0 && currentLed.profileLightOffInterval < 50) currentLed.profileLightOffInterval = 50;

                        Serial.printf("     LED %d Config: Hab=%d, On=%d, Off=%d, Auto=%d\n", ledIndex,
                                      currentLed.profileEnabled, currentLed.profileLightOnInterval,
                                      currentLed.profileLightOffInterval, currentLed.profileAutoOffDuration);

                        // Lógica post-perfil para ESTE LED: Apagar si está deshabilitado o si es modo parpadeo
                        bool isBlinkingNow = currentLed.profileLightOnInterval > 0 && currentLed.profileLightOffInterval > 0;
                        if (!currentLed.profileEnabled || isBlinkingNow) {
                            if (digitalRead(ledPins[ledIndex]) == HIGH) {
                                Serial.printf("     Forzando apagado LED %d (Deshab/Parpadeo)\n", ledIndex);
                                digitalWrite(ledPins[ledIndex], LOW);
                            }
                        } else { // Manual o AutoOff -> asegurar que empieza apagado
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
            // Configuración Sensores (ej: "S,1,3000")
            else if (token[0] == 'S') {
                int tempEnabled, tempInterval;
                int scannedValues = sscanf(token + 2, "%d,%d", &tempEnabled, &tempInterval);
                if (scannedValues == 2) {
                    profileSensorsEnabled = (tempEnabled != 0);
                    profileSensorReadInterval = tempInterval;
                    // Validar intervalo mínimo
                    if (profileSensorReadInterval < 500) profileSensorReadInterval = 500;
                    Serial.printf("     Sensor Config: Hab=%d, Int=%d\n", profileSensorsEnabled, profileSensorReadInterval);
                } else {
                    Serial.printf("     Error parseando config Sensor: Se esperaban 2 valores, se obtuvieron %d.\n", scannedValues);
                }
            } else {
                Serial.printf("     Token desconocido: '%s'\n", token);
            }
            token = strtok(NULL, "|"); // Obtener siguiente token
        }

        free(profileStr); // Liberar memoria duplicada

        // Notificar estado inicial de todos los LEDs después de aplicar el perfil
        notifyLedStates();

        Serial.println("--- Fin [ProfileCallbacks::onWrite] ---\n");
    }
};


// --- SETUP ---
void setup() {
  Serial.begin(115200);

  // --- INICIAR LCD ---
  Wire.begin(); // Inicia I2C (SDA=21, SCL=22 por defecto)
  lcd.init();
  lcd.backlight();
  lcd.setCursor(0, 0); 
  lcd.print("Iniciando..."); 
  lcd.setCursor(0, 1); 
  lcd.print(currentProfileName); // Muestra "Desconectado"
  // --- FIN LCD ---

  // Configurar pines de LED como salida y asegurar que empiezan apagados
  for (int i = 0; i < NUM_LEDS; i++) {
    pinMode(ledPins[i], OUTPUT);
    digitalWrite(ledPins[i], LOW);
  }
  dht.begin(); // Inicializar sensor DHT

  Serial.println("Iniciando BLE...");
  BLEDevice::init("ESP32-MultiLED"); // Cambiar nombre si se desea
  pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // --- Configurar Característica LED --- (Misma UUID, nuevo manejo)
  pLedCharacteristic = pService->createCharacteristic(
                         LED_CHARACTERISTIC_UUID,
                         BLECharacteristic::PROPERTY_WRITE |
                         BLECharacteristic::PROPERTY_NOTIFY
                       );
  pLedCharacteristic->addDescriptor(new BLE2902());
  pLedCharacteristic->setCallbacks(new LedCallbacks());
  // Valor inicial representa el estado de todos los LEDs apagados
  char initialLedState[NUM_LEDS * 2] = {0};
  for(int i=0; i<NUM_LEDS; ++i) {
      strcat(initialLedState, "0");
      if (i < NUM_LEDS - 1) strcat(initialLedState, ",");
  }
  pLedCharacteristic->setValue(initialLedState);

  // --- Configurar Característica Sensores --- (Sin cambios aquí)
  pSensorCharacteristic = pService->createCharacteristic(
                            SENSOR_CHARACTERISTIC_UUID,
                            BLECharacteristic::PROPERTY_NOTIFY
                          );
  pSensorCharacteristic->addDescriptor(new BLE2902());

  // --- Configurar Característica Configuración de Perfil --- (Misma UUID, nuevo manejo)
   pProfileConfigCharacteristic = pService->createCharacteristic(
                                    PROFILE_CONFIG_UUID,
                                    BLECharacteristic::PROPERTY_WRITE
                                   );
   pProfileConfigCharacteristic->setCallbacks(new ProfileCallbacks());

  // --- Iniciar Servicio y Advertising ---
  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("Servidor BLE iniciado y anunciando. Esperando conexiones...");
  Serial.printf("Controlando %d LEDs. Sensores: DHT22.\n", NUM_LEDS);

  delay(300); // Espera 300 milisegundos para estabilización del stack BLE
}

// --- LOOP ---
void loop() {
  unsigned long currentTime = millis();

  // --- LÓGICA LCD CONEXIÓN/DESCONEXIÓN (CORREGIDA) ---
  static bool clientConnected = false;
  bool nowConnected = (pServer->getConnectedCount() > 0);

  if (nowConnected && !clientConnected) {
      // Se acaba de conectar
      clientConnected = true;
      Serial.println("Cliente Conectado.");
      lcd.clear();
      lcd.setCursor(0,0);
      lcd.print("Conectado"); // <-- CORREGIDO: Mostrar "Conectado"
      lcd.setCursor(0,1);
      lcd.print("Recibiendo..."); // Esperando perfil
  } else if (!nowConnected && clientConnected) {
      // Se acaba de desconectar
      clientConnected = false;
      currentProfileName = "Desconectado"; // Resetear nombre
      Serial.println("Cliente Desconectado.");
      lcd.clear();
      lcd.setCursor(0, 0);
      lcd.print(currentProfileName);
      lcd.setCursor(0, 1);
      lcd.print("Buscando App...");
  }
  // --- FIN LÓGICA LCD ---


  // --- Lógica de Control para CADA LED basada en su Perfil ---
  for (int i = 0; i < NUM_LEDS; i++) {
    LedState &currentLed = ledStates[i]; // Referencia al estado del LED actual

    if (currentLed.profileEnabled) { // Solo si el LED está habilitado por perfil

      // Modo Parpadeo
      if (currentLed.profileLightOnInterval > 0 && currentLed.profileLightOffInterval > 0) {
        unsigned long interval = currentLed.isLedCurrentlyOnForBlink ? currentLed.profileLightOnInterval : currentLed.profileLightOffInterval;
        if (currentTime - currentLed.lastBlinkToggleTime >= interval) {
          currentLed.isLedCurrentlyOnForBlink = !currentLed.isLedCurrentlyOnForBlink;
          digitalWrite(ledPins[i], currentLed.isLedCurrentlyOnForBlink ? HIGH : LOW);
          currentLed.lastBlinkToggleTime = currentTime;
          notifyLedStates(); // Notificar cambio
        }
      }
      // Modo Auto-Apagado
      else if (currentLed.profileAutoOffDuration > 0 && currentLed.ledTurnOnTime > 0) {
        if (currentTime - currentLed.ledTurnOnTime >= (unsigned long)currentLed.profileAutoOffDuration * 1000) {
          if (digitalRead(ledPins[i]) == HIGH) {
             Serial.printf("[Loop] Auto-Apagado LED %d ejecutándose...\n", i);
             digitalWrite(ledPins[i], LOW);
             currentLed.ledTurnOnTime = 0;
             notifyLedStates(); // Notificar cambio
             Serial.printf("[Loop] Auto-Apagado LED %d completado.\n", i);
          } else {
              currentLed.ledTurnOnTime = 0; // Timer expiró, pero ya estaba apagado
          }
        }
      }
      // Modo Manual (o Auto-Apagado inactivo) - Resetear timers si es necesario
      else {
          if (currentLed.ledTurnOnTime != 0) currentLed.ledTurnOnTime = 0;
          if (currentLed.lastBlinkToggleTime != 0) currentLed.lastBlinkToggleTime = 0;
          if (currentLed.isLedCurrentlyOnForBlink) currentLed.isLedCurrentlyOnForBlink = false;
      }
    } else { // Si este LED está deshabilitado por perfil
        if (digitalRead(ledPins[i]) == HIGH) {
            Serial.printf("[Loop] LED %d deshabilitado por perfil, apagando...\n", i);
            digitalWrite(ledPins[i], LOW);
            notifyLedStates(); // Notificar cambio
        }
        // Asegurar timers reseteados
        currentLed.ledTurnOnTime = 0;
        currentLed.lastBlinkToggleTime = 0;
        currentLed.isLedCurrentlyOnForBlink = false;
    }
  } // Fin del bucle for para LEDs

  // --- Lógica de Lectura y Envío/Display de Sensores ---
  static unsigned long lastSensorReadTime = 0;
  // Comprobar si los sensores están habilitados Y si ha pasado el intervalo definido
  if (profileSensorsEnabled && (currentTime - lastSensorReadTime >= profileSensorReadInterval)) {
    lastSensorReadTime = currentTime; // Actualizar timestamp

    float temp = dht.readTemperature(false);
    float humidity = dht.readHumidity();

    if (isnan(temp) || isnan(humidity)) {
      Serial.println("[Loop] Error al leer del sensor DHT!");
      
      // Mostrar error en LCD si está conectado
      if(clientConnected) {
         lcd.setCursor(0, 1);
         lcd.print("Error Sensor DHT");
         // Limpiar el resto de la línea
         for (int i = 15; i < 16; i++) lcd.print(" ");
      }

    } else {
      // Preparar datos para BLE
      char sensorData[20];
      snprintf(sensorData, sizeof(sensorData), "%.1f,%.1f", temp, humidity);

      // Actualizar LCD con Temp/Hum si está conectado
      if(clientConnected) {
        char lcdLine[17]; // 16 chars + null
        // Formateamos la línea 1 del LCD
        snprintf(lcdLine, sizeof(lcdLine), "T:%.1fC  H:%.0f%%", temp, humidity);
        lcd.setCursor(0, 1);
        lcd.print(lcdLine);
        // Rellenar con espacios si es más corto
        for (int i = strlen(lcdLine); i < 16; i++) {
           lcd.print(" ");
        }
      }
      
      // Enviar datos por BLE si está conectado
      if (nowConnected && pSensorCharacteristic != nullptr) {
        pSensorCharacteristic->setValue(sensorData);
        pSensorCharacteristic->notify();
      }
    }
  }

  delay(50); // Pausa general del loop
}