#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <string>
#include "DHT.h"

// --- PINES DE HARDWARE ACTUALIZADOS ---
#define LED_PIN 23
#define DHT_PIN 22
#define LDR_PIN 18 

// --- CONFIGURACIÓN DEL SENSOR DHT ---
#define DHT_TYPE DHT22
DHT dht(DHT_PIN, DHT_TYPE);

// --- UUIDs 
#define SERVICE_UUID                  "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define LED_CHARACTERISTIC_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define SENSOR_CHARACTERISTIC_UUID    "a1b2c3d4-e5f6-4a5b-6c7d-8e9f0a1b2c3d"

BLECharacteristic *pSensorCharacteristic;

class LedCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String value = pCharacteristic->getValue().c_str();
      if (value.length() > 0) {
        if (value.indexOf("1") != -1) {
          digitalWrite(LED_PIN, HIGH);
        } else if (value.indexOf("0") != -1) {
          digitalWrite(LED_PIN, LOW);
        }
      }
    }
};

void setup() {
  Serial.begin(115200);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);
  dht.begin();
  BLEDevice::init("ESP32-LED");
  BLEServer *pServer = BLEDevice::createServer();
  BLEService *pService = pServer->createService(SERVICE_UUID);
  BLECharacteristic *pLedCharacteristic = pService->createCharacteristic(
                                         LED_CHARACTERISTIC_UUID,
                                         BLECharacteristic::PROPERTY_WRITE);
  pLedCharacteristic->setCallbacks(new LedCallbacks());
  pSensorCharacteristic = pService->createCharacteristic(
                                         SENSOR_CHARACTERISTIC_UUID,
                                         BLECharacteristic::PROPERTY_NOTIFY);
  pSensorCharacteristic->addDescriptor(new BLE2902());
  pService->start();
  BLEDevice::getAdvertising()->start();
  Serial.println("Servidor BLE iniciado. Sensores: DHT22 y LDR.");
}

void loop() {
  float temp = dht.readTemperature(false);
  float humidity = dht.readHumidity();
  int lightValue = analogRead(LDR_PIN);

  if (isnan(temp) || isnan(humidity)) {
    Serial.println("Error al leer del sensor DHT!");
  } else {
    // Formateamos los tres valores
    char sensorData[30];
    snprintf(sensorData, sizeof(sensorData), "%.1f,%.1f,%d", temp, humidity, lightValue);
    
    pSensorCharacteristic->setValue(sensorData);
    pSensorCharacteristic->notify();
    Serial.print("Enviando datos: ");
    Serial.println(sensorData);
  }
  delay(2000); // Enviamos datos un poco más rápido
}