#include <WiFi.h>
#include <WebServer.h>
#include <ESP32Servo.h>
#include <WiFiUdp.h>

const char* ssid = "gwak";
const char* password = "01040880653";

const int udpPort = 4210;
const int relayPin = D2;
const int servo1Pin = D3;
const int servo2Pin = D4;

WebServer server(80);
WiFiUDP udp;
Servo servo1;
Servo servo2;

int pos = 0;
char packetBuffer[255];

void setup() {
  Serial.begin(115200);
  
  pinMode(relayPin, OUTPUT);
  digitalWrite(relayPin, LOW);

  servo1.setPeriodHertz(50); 
  servo2.setPeriodHertz(50);
  servo1.attach(servo1Pin, 500, 2400);
  servo2.attach(servo2Pin, 500, 2400);
  servo1.write(0);
  servo2.write(0);

  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
  }

  udp.begin(udpPort);

  server.on("/sleep", handleSleep);
  server.on("/", []() {
    server.send(200, "text/plain", "Sleep Detector System Online");
  });
  server.begin();
}

void loop() {
  server.handleClient();
  handleUdp();
}

void handleUdp() {
  int packetSize = udp.parsePacket();
  if (packetSize) {
    int len = udp.read(packetBuffer, 255);
    if (len > 0) packetBuffer[len] = 0;

    String msg = String(packetBuffer);

    if (msg == "FIND_ESP") {
      udp.beginPacket(udp.remoteIP(), udp.remotePort());
      udp.print(WiFi.localIP().toString());
      udp.endPacket();
    }
  }
}

void handleSleep() {
  server.send(200, "text/plain", "WAKE UP ACTION STARTED");
  wakeUpRoutine();
}

void wakeUpRoutine() {
  digitalWrite(relayPin, HIGH);

  for (int i = 0; i < 3; i++) {
    for (pos = 0; pos <= 90; pos += 5) { 
      servo1.write(pos);
      servo2.write(90 - pos);
      delay(15);
    }
    for (pos = 90; pos >= 0; pos -= 5) { 
      servo1.write(pos);
      servo2.write(90 - pos);
      delay(15);
    }
  }
  delay(2000);
  
  digitalWrite(relayPin, LOW);
  servo1.write(0);
  servo2.write(0);
}