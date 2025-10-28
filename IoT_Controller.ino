#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <string>
#include "DHT.h" // Asegúrate de tener la librería DHT instalada

// --- PINES DE HARDWARE ---
#define LED_PIN 23       // Pin donde está conectado el LED
#define DHT_PIN 22       // Pin donde está conectado el sensor DHT22
#define LDR_PIN 18       // Pin donde está conectado el LDR (Fotoresistencia)

// --- CONFIGURACIÓN DEL SENSOR DHT ---
#define DHT_TYPE DHT22   // Define el tipo de sensor DHT
DHT dht(DHT_PIN, DHT_TYPE);

// --- UUIDs --- (Deben coincidir EXACTAMENTE con los de la app Flutter)
#define SERVICE_UUID                  "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define LED_CHARACTERISTIC_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26a8" // Para controlar el LED (Write, Notify)
#define SENSOR_CHARACTERISTIC_UUID    "a1b2c3d4-e5f6-4a5b-6c7d-8e9f0a1b2c3d" // Para enviar datos de sensores (Notify)
#define PROFILE_CONFIG_UUID           "c1d2e3f4-a5b6-c7d8-e9f0-a1b2c3d4e5f6" // Para recibir configuración del perfil (Write)

// --- Variables Globales para Perfil Actual ---
// Valores por defecto (modo manual, sensores activados cada 2s)
bool profileLightsEnabled = true;
int profileLightOnInterval = 0; // ms, 0 = no parpadeo
int profileLightOffInterval = 0; // ms, 0 = no parpadeo
int profileAutoOffDuration = 0; // SEGUNDOS, 0 = no auto-apagado
bool profileSensorsEnabled = true;
int profileSensorReadInterval = 2000; // ms

// --- Variables de Estado para Lógica de Tiempo ---
unsigned long ledTurnOnTime = 0;       // Timestamp (millis()) cuando se encendió el LED para auto-apagado
unsigned long lastBlinkToggleTime = 0; // Timestamp del último cambio de estado en modo parpadeo
bool isLedCurrentlyOnForBlink = false; // Estado actual del LED *solo* para la lógica de parpadeo

// --- Punteros a Características y Servidor BLE ---
BLEServer *pServer = nullptr;                     // Puntero al servidor BLE
BLECharacteristic *pSensorCharacteristic = nullptr; // Puntero a la característica de sensores
BLECharacteristic *pLedCharacteristic = nullptr;    // Puntero a la característica del LED
BLECharacteristic *pProfileConfigCharacteristic = nullptr; // Puntero a la característica de perfil

// --- Función para Notificar Estado del LED ---
// Envía el estado actual del LED (0 o 1) a la app si está conectada.
void notifyLedState() {
  Serial.println("[notifyLedState] Intentando notificar..."); // DEBUG
  if (pLedCharacteristic != nullptr && pServer != nullptr) {
      int connectedCount = pServer->getConnectedCount(); // Obtener número de clientes conectados
      Serial.printf("[notifyLedState] Conexiones: %d\n", connectedCount); // DEBUG
      if (connectedCount > 0) { // Solo notificar si hay alguien conectado
        // Leer el estado actual del pin del LED
        const char* currentState = digitalRead(LED_PIN) == HIGH ? "1" : "0";
        Serial.printf("[notifyLedState] Estado actual: %s. Estableciendo valor...\n", currentState); // DEBUG
        pLedCharacteristic->setValue(currentState); // Establecer el valor en la característica
        Serial.println("[notifyLedState] Notificando..."); // DEBUG
        pLedCharacteristic->notify(); // Enviar la notificación
        Serial.println("[notifyLedState] Notificación enviada."); // DEBUG
      } else {
         Serial.println("[notifyLedState] No se notifica (no hay conexiones activas)."); // DEBUG
      }
  } else {
     // Mensaje de error si los punteros no están inicializados
     Serial.print("[notifyLedState] No se notifica (pLedCharacteristic: "); // DEBUG
     Serial.print(pLedCharacteristic != nullptr ? "OK" : "NULL"); // DEBUG
     Serial.print(", pServer: "); // DEBUG
     Serial.print(pServer != nullptr ? "OK" : "NULL"); // DEBUG
     Serial.println(")."); // DEBUG
  }
}

// --- Callbacks para Característica LED ---
// Se ejecuta cuando la app escribe un valor en la característica del LED.
class LedCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      // --- INICIO DE CORRECCIÓN ---
      String value = pCharacteristic->getValue(); // Obtener directamente como String de Arduino
      int rxLength = value.length(); // Obtener la longitud del String de Arduino
      // --- FIN DE CORRECCIÓN ---

      Serial.println("\n--- [LedCallbacks::onWrite] ---"); // DEBUG: Inicio del callback
      Serial.print("Arduino String length recibida: "); Serial.println(rxLength); // DEBUG: Ver longitud
      Serial.print("Valor recibido (Arduino String): '"); Serial.print(value); Serial.println("'"); // DEBUG: Mostrar valor recibido

      // 1. Verificar si las luces están habilitadas en el perfil actual
      Serial.print("¿Luces habilitadas por perfil? "); Serial.println(profileLightsEnabled ? "Sí" : "No"); // DEBUG
      if (!profileLightsEnabled) {
        Serial.println("--> Comando ignorado (luces deshabilitadas por perfil)."); // DEBUG
        Serial.println("--- Fin [LedCallbacks::onWrite] ---\n"); // DEBUG
        return; // Salir si están deshabilitadas
      }

      // 2. Verificar si estamos en modo parpadeo (definido por intervalos > 0)
      bool isBlinkingMode = (profileLightOnInterval > 0 && profileLightOffInterval > 0);
      Serial.print("¿Modo parpadeo activo? "); Serial.println(isBlinkingMode ? "Sí" : "No"); // DEBUG
      if (isBlinkingMode) {
         Serial.println("--> Comando ignorado (modo parpadeo activo)."); // DEBUG
         // En modo parpadeo, el ESP32 controla el LED, ignoramos comandos manuales
         Serial.println("--- Fin [LedCallbacks::onWrite] ---\n"); // DEBUG
         return; // Salir si está en parpadeo
      }

      // 3. Si es modo Manual o Auto-Apagado, procesar "1" o "0"
      // Procesar solo si recibimos un valor no vacío
      if (value.length() > 0) { // <<< Esta condición ahora usa el String de Arduino
        bool turnOn = (value == "1"); // Determinar si el comando es para encender
        Serial.print("¿Comando es para encender (turnOn)? "); Serial.println(turnOn ? "Sí" : "No"); // DEBUG

        // Realizar la acción física sobre el LED
        Serial.print("Ejecutando digitalWrite..."); // DEBUG
        digitalWrite(LED_PIN, turnOn ? HIGH : LOW); // Encender o apagar el pin
        Serial.println(" ¡Hecho!"); // DEBUG

        // Lógica específica para Auto-Apagado
        bool isAutoOffMode = (profileAutoOffDuration > 0);
        Serial.print("¿Modo Auto-Apagado activo? "); Serial.println(isAutoOffMode ? "Sí" : "No"); // DEBUG
        if (turnOn && isAutoOffMode) {
          // Si se enciende Y estamos en modo auto-apagado, iniciar/reiniciar el temporizador
          ledTurnOnTime = millis();
          Serial.print("--> Temporizador Auto-Apagado iniciado/reiniciado. Duración: "); // DEBUG
          Serial.print(profileAutoOffDuration); Serial.println(" s"); // DEBUG
        } else {
          // Si se apaga manualmente o no estamos en modo auto-off, desactivar el temporizador
          if (ledTurnOnTime != 0) {
              Serial.println("--> Temporizador Auto-Apagado reseteado (ledTurnOnTime = 0)."); // DEBUG
              ledTurnOnTime = 0;
          }
        }

        // Después de cambiar el estado, notificar a la app
        Serial.println("Llamando a notifyLedState()..."); // DEBUG
        notifyLedState();

      } else {
          // Si el valor recibido estaba vacío (longitud 0)
          Serial.println("--> Comando ignorado (valor vacío o longitud 0 recibido)."); // DEBUG
      }
      Serial.println("--- Fin [LedCallbacks::onWrite] ---\n"); // DEBUG: Fin del callback
    }
};

// --- Callbacks para Característica de Configuración de Perfil ---
// Se ejecuta cuando la app escribe la configuración de un perfil.
class ProfileCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        // Aquí std::string SÍ funciona porque la librería lo maneja internamente para la comparación y substr
        std::string value = pCharacteristic->getValue().c_str(); // Obtener configuración como std::string
        Serial.println("\n--- [ProfileCallbacks::onWrite] ---"); // DEBUG: Inicio del callback
        Serial.print("Configuración recibida: "); Serial.println(value.c_str()); // DEBUG: Mostrar configuración cruda

        // Buscar las secciones de configuración de Luces (L,...) y Sensores (S,...)
        size_t lightPos = value.find("L,");
        size_t sensorPos = value.find("S,");
        size_t separatorPos = value.find("|"); // Separador entre luces y sensores

        // Variables temporales para usar con sscanf (que espera ints)
        int tempLightsEnabled = profileLightsEnabled;
        int tempSensorsEnabled = profileSensorsEnabled;

        // --- Procesar Configuración de Luces ---
        // Asegurarse que 'L,' y '|' existen y están en orden correcto
        if (lightPos != std::string::npos && separatorPos != std::string::npos && separatorPos > lightPos) {
            // Extraer la subcadena de configuración de luces
            std::string lightConfig = value.substr(lightPos + 2, separatorPos - (lightPos + 2));
            Serial.print("  Procesando luces: '"); Serial.print(lightConfig.c_str()); Serial.println("'"); // DEBUG
            // Intentar parsear los 4 valores separados por comas
            int scannedValues = sscanf(lightConfig.c_str(), "%d,%d,%d,%d",
                   &tempLightsEnabled, &profileLightOnInterval, &profileLightOffInterval, &profileAutoOffDuration);

            if (scannedValues == 4) { // Verificar si se parsearon los 4 valores esperados
                profileLightsEnabled = (tempLightsEnabled != 0); // Convertir el int parseado a bool
                Serial.printf("    Valores luces parseados: Hab=%d, On=%d, Off=%d, Auto=%d\n",
                              profileLightsEnabled, profileLightOnInterval, profileLightOffInterval, profileAutoOffDuration); // DEBUG
            } else {
                 // Error si no se parsearon 4 valores
                 Serial.printf("    Error: Se esperaban 4 valores de luz, se obtuvieron %d.\n", scannedValues); // DEBUG
            }
        } else {
          // Error si no se encontró la sección 'L,...|'
          Serial.println("    Error: No se encontró la sección de configuración de luces ('L,...|')."); // DEBUG
        }

        // --- Procesar Configuración de Sensores ---
        // Asegurarse que 'S,' existe y está después del separador (o es la única sección)
        if (sensorPos != std::string::npos && (separatorPos == std::string::npos || sensorPos > separatorPos)) {
            // Extraer la subcadena de configuración de sensores (desde 'S,' hasta el final)
            std::string sensorConfig = value.substr(sensorPos + 2);
             Serial.print("  Procesando sensores: '"); Serial.print(sensorConfig.c_str()); Serial.println("'"); // DEBUG
            // Intentar parsear los 2 valores separados por comas
            int scannedValues = sscanf(sensorConfig.c_str(), "%d,%d",
                   &tempSensorsEnabled, &profileSensorReadInterval);

             if (scannedValues == 2) { // Verificar si se parsearon los 2 valores esperados
                profileSensorsEnabled = (tempSensorsEnabled != 0); // Convertir el int parseado a bool
                Serial.printf("    Valores sensores parseados: Hab=%d, Int=%d\n", profileSensorsEnabled, profileSensorReadInterval); // DEBUG
             } else {
                 // Error si no se parsearon 2 valores
                 Serial.printf("    Error: Se esperaban 2 valores de sensor, se obtuvieron %d.\n", scannedValues); // DEBUG
             }
        } else {
          // Error si no se encontró la sección 'S,...'
          Serial.println("    Error: No se encontró la sección de configuración de sensores ('S,...')."); // DEBUG
        }

        // --- Aplicar Lógica Post-Perfil ---
        // Se ejecuta después de parsear (o intentar parsear) ambas secciones
        Serial.println("  Aplicando lógica post-perfil:"); // DEBUG
        // Asegurarse que los intervalos no sean menores a un umbral mínimo razonable
        if (profileLightOnInterval > 0 && profileLightOnInterval < 50) {
            Serial.printf("    Ajustando OnInterval de %d a 50 ms.\n", profileLightOnInterval); // DEBUG
            profileLightOnInterval = 50; // Mínimo 50ms para parpadeo
        }
        if (profileLightOffInterval > 0 && profileLightOffInterval < 50) {
            Serial.printf("    Ajustando OffInterval de %d a 50 ms.\n", profileLightOffInterval); // DEBUG
             profileLightOffInterval = 50; // Mínimo 50ms para parpadeo
        }
        if (profileSensorReadInterval < 500) {
            Serial.printf("    Ajustando SensorInterval de %d a 500 ms.\n", profileSensorReadInterval); // DEBUG
             profileSensorReadInterval = 500; // Mínimo 500ms para lectura de sensores
        }

        // Resetear timers y estado de parpadeo siempre que se cambia un perfil
        Serial.println("    Reseteando timers de LED (ledTurnOnTime=0, lastBlinkToggleTime=0, isLedCurrentlyOnForBlink=false)."); // DEBUG
        ledTurnOnTime = 0;
        lastBlinkToggleTime = 0;
        isLedCurrentlyOnForBlink = false;

        // Determinar si el LED debe apagarse al aplicar el nuevo perfil
        // Se apaga si: las luces están deshabilitadas O si el nuevo modo es parpadeo
        bool shouldTurnOffLed = !profileLightsEnabled || (profileLightOnInterval > 0 && profileLightOffInterval > 0);
        Serial.print("    ¿Debería apagarse el LED ahora? "); Serial.println(shouldTurnOffLed ? "Sí" : "No"); // DEBUG
        if (shouldTurnOffLed) {
            // Solo apagar y notificar si estaba encendido
            if (digitalRead(LED_PIN) == HIGH) {
                Serial.println("    Apagando LED y notificando..."); // DEBUG
                digitalWrite(LED_PIN, LOW);
                notifyLedState(); // Notificar el cambio forzado por el perfil
            } else {
                Serial.println("    LED ya está apagado, no se notifica."); // DEBUG
            }
        } else {
             // Si las luces están habilitadas Y NO es modo parpadeo (es Manual o AutoOff),
             // forzamos a OFF para empezar limpio en estos modos.
             if (digitalRead(LED_PIN) == HIGH) {
                 Serial.println("    Modo Manual/AutoOff detectado, forzando LED a OFF y notificando..."); // DEBUG
                 digitalWrite(LED_PIN, LOW); // Forzar a OFF al cambiar perfil a Manual/AutoOff
                 notifyLedState();
             } else {
                 Serial.println("    Modo Manual/AutoOff detectado, LED ya apagado."); // DEBUG
             }
        }
        Serial.println("--- Fin [ProfileCallbacks::onWrite] ---\n"); // DEBUG: Fin del callback
    }
};


// --- SETUP ---
// Se ejecuta una vez al iniciar el ESP32
void setup() {
  Serial.begin(115200); // Iniciar comunicación serial para depuración
  pinMode(LED_PIN, OUTPUT); // Configurar pin del LED como salida
  digitalWrite(LED_PIN, LOW); // Asegurar que el LED empieza apagado
  dht.begin(); // Inicializar sensor DHT

  Serial.println("Iniciando BLE...");
  BLEDevice::init("ESP32-LED"); // Iniciar BLE con el nombre del dispositivo
  pServer = BLEDevice::createServer(); // Crear el servidor BLE
  BLEService *pService = pServer->createService(SERVICE_UUID); // Crear el servicio principal

  // --- Configurar Característica LED ---
  pLedCharacteristic = pService->createCharacteristic(
                         LED_CHARACTERISTIC_UUID,
                         BLECharacteristic::PROPERTY_WRITE | // Permite escribir desde la app
                         BLECharacteristic::PROPERTY_NOTIFY   // Permite enviar notificaciones a la app
                       );
  pLedCharacteristic->addDescriptor(new BLE2902()); // Descriptor estándar necesario para notificaciones
  pLedCharacteristic->setCallbacks(new LedCallbacks()); // Asociar los callbacks de escritura
  pLedCharacteristic->setValue("0"); // Establecer valor inicial (apagado)

  // --- Configurar Característica Sensores ---
  pSensorCharacteristic = pService->createCharacteristic(
                            SENSOR_CHARACTERISTIC_UUID,
                            BLECharacteristic::PROPERTY_NOTIFY // Solo envía notificaciones
                          );
  pSensorCharacteristic->addDescriptor(new BLE2902()); // Descriptor para notificaciones

  // --- Configurar Característica Configuración de Perfil ---
   pProfileConfigCharacteristic = pService->createCharacteristic(
                                    PROFILE_CONFIG_UUID,
                                    BLECharacteristic::PROPERTY_WRITE // Solo recibe escrituras
                                  );
   pProfileConfigCharacteristic->setCallbacks(new ProfileCallbacks()); // Asociar callbacks de escritura
   // No necesita valor inicial, solo recibe escrituras

  // --- Iniciar Servicio y Advertising ---
  pService->start(); // Iniciar el servicio (hace visibles las características)
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising(); // Obtener objeto de advertising
  pAdvertising->addServiceUUID(SERVICE_UUID); // Anunciar el UUID del servicio principal
  pAdvertising->setScanResponse(true); // Permitir respuestas a escaneos activos
  // Configuraciones para mejorar compatibilidad (especialmente iOS)
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising(); // Empezar a anunciarse

  Serial.println("Servidor BLE iniciado y anunciando. Esperando conexiones...");
  Serial.println("Sensores: DHT22 y LDR.");
}

// --- LOOP ---
// Se ejecuta repetidamente después de setup()
void loop() {
  unsigned long currentTime = millis(); // Obtener tiempo actual para lógica de temporización

  // --- Lógica de Control del LED basada en el Perfil Actual ---
  if (profileLightsEnabled) { // Solo ejecutar si las luces están habilitadas por el perfil

    // Modo Parpadeo: Si ambos intervalos son mayores que 0
    if (profileLightOnInterval > 0 && profileLightOffInterval > 0) {
      // Determinar cuánto tiempo debe estar en el estado actual (ON u OFF)
      unsigned long interval = isLedCurrentlyOnForBlink ? profileLightOnInterval : profileLightOffInterval;
      // Comprobar si ha pasado suficiente tiempo para cambiar de estado
      if (currentTime - lastBlinkToggleTime >= interval) {
        isLedCurrentlyOnForBlink = !isLedCurrentlyOnForBlink; // Invertir el estado de parpadeo
        digitalWrite(LED_PIN, isLedCurrentlyOnForBlink ? HIGH : LOW); // Cambiar el LED físico
        lastBlinkToggleTime = currentTime; // Actualizar el timestamp del último cambio
        notifyLedState(); // Notificar el nuevo estado a la app
        // Serial.print("Parpadeo - LED: "); Serial.println(isLedCurrentlyOnForBlink ? "ON" : "OFF"); // Reducir logs si funciona
      }
    }
    // Modo Auto-Apagado: Si la duración es mayor que 0 Y el temporizador se inició (ledTurnOnTime > 0)
    else if (profileAutoOffDuration > 0 && ledTurnOnTime > 0) {
      // Comprobar si ha pasado el tiempo configurado desde que se encendió
      if (currentTime - ledTurnOnTime >= (unsigned long)profileAutoOffDuration * 1000) { // Multiplicar por 1000 para convertir segundos a ms
        // Solo apagar si actualmente está encendido (evita notificaciones innecesarias)
        if (digitalRead(LED_PIN) == HIGH) {
           Serial.println("[Loop] Auto-Apagado ejecutándose..."); // DEBUG
           digitalWrite(LED_PIN, LOW); // Apagar el LED
           ledTurnOnTime = 0; // Detener/resetear el temporizador poniendo el timestamp a 0
           notifyLedState(); // Notificar que se apagó
           Serial.println("[Loop] Auto-Apagado completado."); // DEBUG
        } else {
            // Si el timer expiró pero el LED ya estaba apagado (quizás manualmente), solo resetear el timer
            ledTurnOnTime = 0;
            // Serial.println("[Loop] Timer Auto-Apagado expiró, pero LED ya estaba apagado."); // DEBUG Opcional
        }
      }
    }
    // Modo Manual o Deshabilitado (Implícito si no es Parpadeo ni Auto-Apagado activo)
    else {
        // En modo manual, no hay lógica de temporización activa.
        // Reseteamos los timers por si acaso venimos de otro modo.
        if (ledTurnOnTime != 0) {
            // Serial.println("[Loop] Reseteando timer Auto-Apagado (ledTurnOnTime = 0)."); // DEBUG Opcional
             ledTurnOnTime = 0;
        }
        if (lastBlinkToggleTime != 0) {
            // Serial.println("[Loop] Reseteando timer Parpadeo (lastBlinkToggleTime = 0)."); // DEBUG Opcional
             lastBlinkToggleTime = 0;
        }
        if (isLedCurrentlyOnForBlink) {
            // Serial.println("[Loop] Reseteando estado Parpadeo (isLedCurrentlyOnForBlink = false)."); // DEBUG Opcional
             isLedCurrentlyOnForBlink = false; // Asegurar estado correcto si salimos de parpadeo
        }
    }
  } else { // Si las luces están deshabilitadas globalmente por el perfil
      // Forzar apagado del LED si estaba encendido
      if (digitalRead(LED_PIN) == HIGH) {
          Serial.println("[Loop] Luces deshabilitadas por perfil, apagando LED..."); // DEBUG
          digitalWrite(LED_PIN, LOW);
          notifyLedState(); // Notificar el cambio forzado
      }
      // Asegurar que todos los timers y estados relacionados con el LED estén reseteados
      ledTurnOnTime = 0;
      lastBlinkToggleTime = 0;
      isLedCurrentlyOnForBlink = false;
  }

  // --- Lógica de Lectura y Envío de Sensores ---
  static unsigned long lastSensorReadTime = 0; // Timestamp de la última lectura
  // Comprobar si los sensores están habilitados Y si ha pasado el intervalo definido
  if (profileSensorsEnabled && (currentTime - lastSensorReadTime >= profileSensorReadInterval)) {
    lastSensorReadTime = currentTime; // Actualizar timestamp de la última lectura

    // Leer valores de los sensores
    float temp = dht.readTemperature(false); // Lee temperatura en Celsius
    float humidity = dht.readHumidity();     // Lee humedad relativa
    int lightValue = analogRead(LDR_PIN);   // Lee valor analógico del LDR (0-4095 en ESP32)

    // Validar lecturas del DHT (pueden fallar y devolver NaN)
    if (isnan(temp) || isnan(humidity)) {
      Serial.println("[Loop] Error al leer del sensor DHT!");
    } else {
      // Formatear los datos en una cadena CSV: "Temp,Hum,Luz"
      char sensorData[30]; // Buffer para la cadena formateada
      snprintf(sensorData, sizeof(sensorData), "%.1f,%.1f,%d", temp, humidity, lightValue);

      // Enviar los datos por BLE Notify solo si hay algún dispositivo conectado
      if (pServer != nullptr && pSensorCharacteristic != nullptr && pServer->getConnectedCount() > 0) {
        pSensorCharacteristic->setValue(sensorData); // Establecer el valor en la característica
        pSensorCharacteristic->notify();             // Enviar notificación
        // Serial.print("[Loop] Enviando datos sensores: "); Serial.println(sensorData); // Reducir logs si funciona
      } else {
        // Si no hay conexión, opcionalmente mostrar los datos en Serial para depuración
        // Serial.print("[Loop] Datos sensores (no enviados - sin conexión): "); Serial.println(sensorData); // Reducir logs si funciona
      }
    }
  }

  // Pequeño delay para dar tiempo a otros procesos (como BLE) y evitar consumo excesivo de CPU
  delay(50); // 50ms de pausa en cada iteración del loop
}