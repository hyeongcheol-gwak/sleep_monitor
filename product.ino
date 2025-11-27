#include <WiFi.h>
#include <WebServer.h>
#include <ESP32Servo.h>
#include <WiFiUdp.h> // UDP 통신을 위한 라이브러리

// ==========================================
// 1. 와이파이 설정 (핫스팟 정보 입력 필수)
// ==========================================
const char* ssid = "YOUR_HOTSPOT_SSID";      // 핫스팟 이름
const char* password = "YOUR_HOTSPOT_PASSWORD"; // 핫스팟 비밀번호

// ==========================================
// 2. 포트 및 핀 설정
// ==========================================
const int udpPort = 4210; // UDP 통신 포트 (앱과 맞춰야 함)
const int relayPin = 4;   // 릴레이
const int servo1Pin = 18; // 서보 1
const int servo2Pin = 19; // 서보 2

// ==========================================
// 객체 생성
// ==========================================
WebServer server(80);
WiFiUDP udp;
Servo servo1;
Servo servo2;

// 서보모터 동작 변수
int pos = 0;
// 응답용 버퍼
char packetBuffer[255];

void setup() {
  Serial.begin(115200);
  
  // 핀 초기화
  pinMode(relayPin, OUTPUT);
  digitalWrite(relayPin, LOW); // 초기값 OFF

  servo1.setPeriodHertz(50); 
  servo2.setPeriodHertz(50);
  servo1.attach(servo1Pin, 500, 2400);
  servo2.attach(servo2Pin, 500, 2400);
  servo1.write(0);
  servo2.write(0);

  // WiFi 연결
  Serial.println();
  Serial.print("Connecting to ");
  Serial.println(ssid);
  WiFi.begin(ssid, password);

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  Serial.println("\nWiFi connected.");
  Serial.print("IP address: ");
  Serial.println(WiFi.localIP());

  // UDP 서버 시작
  udp.begin(udpPort);
  Serial.printf("UDP Server started on port %d\n", udpPort);

  // 웹 서버 경로 설정
  server.on("/sleep", handleSleep);
  server.on("/", []() {
    server.send(200, "text/plain", "Sleep Detector System Online");
  });
  server.begin();
  Serial.println("HTTP server started");
}

void loop() {
  server.handleClient(); // 1. HTTP 요청 처리 (/sleep)
  handleUdp();           // 2. UDP 요청 처리 (자동 연결)
}

// UDP 패킷 처리 함수
void handleUdp() {
  int packetSize = udp.parsePacket();
  if (packetSize) {
    int len = udp.read(packetBuffer, 255);
    if (len > 0) packetBuffer[len] = 0; // 문자열 종료 처리

    String msg = String(packetBuffer);
    Serial.print("UDP Received: ");
    Serial.println(msg);

    // 앱에서 "FIND_ESP"라고 외치면 응답함
    if (msg == "FIND_ESP") {
      udp.beginPacket(udp.remoteIP(), udp.remotePort());
      // 내 IP주소를 문자열로 보냄
      udp.print(WiFi.localIP().toString());
      udp.endPacket();
      Serial.println("Sent IP Address to App");
    }
  }
}

// 졸음 감지 시 하드웨어 동작
void handleSleep() {
  Serial.println("!!! SLEEP DETECTED !!!");
  server.send(200, "text/plain", "WAKE UP ACTION STARTED");
  wakeUpRoutine();
}

void wakeUpRoutine() {
  Serial.println("--- Activating Hardware ---");
  digitalWrite(relayPin, HIGH); // 릴레이 ON (팬/펠티어)

  // 서보 흔들기 (3회)
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
  delay(2000); // 바람 쐬기 지속
  
  digitalWrite(relayPin, LOW); // 릴레이 OFF
  servo1.write(0);
  servo2.write(0);
  Serial.println("--- Hardware Stopped ---");
}