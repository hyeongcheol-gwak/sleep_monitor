#include <WiFi.h>
#include <WebServer.h>
#include <ESP32Servo.h>
#include <WiFiUdp.h>

// 와이파이 네트워크의 SSID를 저장하는 상수입니다. 연결할 핫스팟의 이름을 지정합니다.
const char* ssid = "gwak";
// 와이파이 네트워크의 비밀번호를 저장하는 상수입니다. 연결할 핫스팟의 비밀번호를 지정합니다.
const char* password = "01040880653";

// UDP 통신에 사용할 포트 번호를 정의하는 상수입니다. 앱과 ESP32 간 통신에 사용됩니다.
const int udpPort = 4210;
// 릴레이 모듈이 연결된 핀 번호를 정의하는 상수입니다. 팬이나 펠티어 등의 장치를 제어합니다.
const int relayPin = D2;
// 첫 번째 서보 모터가 연결된 핀 번호를 정의하는 상수입니다.
const int servo1Pin = D3;
// 두 번째 서보 모터가 연결된 핀 번호를 정의하는 상수입니다.
const int servo2Pin = D4;

// HTTP 서버 객체를 생성합니다. 포트 80번에서 웹 서버를 실행합니다.
WebServer server(80);
// UDP 통신을 위한 객체를 생성합니다. 네트워크에서 ESP32 기기를 찾기 위해 사용됩니다.
WiFiUDP udp;
// 첫 번째 서보 모터를 제어하기 위한 객체를 생성합니다.
Servo servo1;
// 두 번째 서보 모터를 제어하기 위한 객체를 생성합니다.
Servo servo2;

// 서보 모터의 위치를 저장하는 변수입니다. 0도에서 90도 사이의 값을 가집니다.
int pos = 0;
// UDP 패킷을 수신할 때 사용하는 버퍼입니다. 최대 255바이트까지 저장할 수 있습니다.
char packetBuffer[255];

// ESP32가 시작될 때 한 번만 실행되는 초기화 함수입니다.
void setup() {
  // 시리얼 통신을 115200 보드레이트로 시작합니다. 디버깅 목적으로 사용됩니다.
  Serial.begin(115200);
  Serial.println("\n[Boot] Sleep monitor starting...");
  
  // 릴레이 핀을 출력 모드로 설정합니다.
  pinMode(relayPin, OUTPUT);
  // 릴레이를 초기 상태인 OFF로 설정합니다. LOW 신호는 릴레이를 끕니다.
  digitalWrite(relayPin, LOW);

  // 첫 번째 서보 모터의 PWM 주파수를 50Hz로 설정합니다. 일반적인 서보 모터의 표준 주파수입니다.
  servo1.setPeriodHertz(50); 
  // 두 번째 서보 모터의 PWM 주파수를 50Hz로 설정합니다.
  servo2.setPeriodHertz(50);
  // 첫 번째 서보 모터를 지정된 핀에 연결하고, 최소 펄스 폭을 500 마이크로초, 최대 펄스 폭을 2400 마이크로초로 설정합니다.
  servo1.attach(servo1Pin, 500, 2400);
  // 두 번째 서보 모터를 지정된 핀에 연결하고, 최소 펄스 폭을 500 마이크로초, 최대 펄스 폭을 2400 마이크로초로 설정합니다.
  servo2.attach(servo2Pin, 500, 2400);
  // 첫 번째 서보 모터를 0도 위치로 초기화합니다.
  servo1.write(0);
  // 두 번째 서보 모터를 0도 위치로 초기화합니다.
  servo2.write(0);

  // 지정된 SSID와 비밀번호로 와이파이에 연결을 시도합니다.
  Serial.print("[WiFi] Connecting to ");
  Serial.println(ssid);
  WiFi.begin(ssid, password);

  // 와이파이 연결이 완료될 때까지 대기합니다. 연결 상태를 확인하며 500ms마다 체크합니다.
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println();
  Serial.print("[WiFi] Connected. IP: ");
  Serial.println(WiFi.localIP());

  // UDP 서버를 시작합니다. 지정된 포트에서 UDP 패킷을 수신할 수 있게 됩니다.
  udp.begin(udpPort);
  Serial.print("[UDP] Listening on port ");
  Serial.println(udpPort);

  // HTTP 요청 경로 /sleep에 대한 핸들러를 등록합니다. 졸음 감지 시 이 경로로 요청이 오면 handleSleep 함수가 호출됩니다.
  server.on("/sleep", handleSleep);
  // 루트 경로 /에 대한 핸들러를 등록합니다. 시스템이 온라인 상태임을 알리는 응답을 반환합니다.
  server.on("/", []() {
    server.send(200, "text/plain", "Sleep Detector System Online");
  });
  // HTTP 서버를 시작합니다. 이제 클라이언트의 요청을 받을 수 있습니다.
  server.begin();
}

// 메인 루프 함수입니다. 이 함수는 계속 반복 실행됩니다.
void loop() {
  // HTTP 클라이언트의 요청을 처리합니다. GET 요청이나 POST 요청이 들어오면 적절한 핸들러를 호출합니다.
  server.handleClient();
  // UDP 패킷을 처리합니다. 앱에서 ESP32 기기를 찾기 위해 보낸 FIND_ESP 메시지를 처리합니다.
  handleUdp();
}

// UDP 패킷을 처리하는 함수입니다. 앱에서 ESP32 기기를 찾기 위해 보낸 메시지를 처리합니다.
void handleUdp() {
  // 수신된 UDP 패킷의 크기를 확인합니다. 패킷이 없으면 0을 반환합니다.
  int packetSize = udp.parsePacket();
  // 패킷이 수신되었는지 확인합니다.
  if (packetSize) {
    Serial.print("[UDP] Packet size ");
    Serial.print(packetSize);
    Serial.print(" from ");
    Serial.print(udp.remoteIP());
    Serial.print(":");
    Serial.println(udp.remotePort());

    // 패킷의 데이터를 버퍼에 읽어옵니다. 최대 255바이트까지 읽을 수 있습니다.
    int len = udp.read(packetBuffer, 255);
    // 문자열 종료 문자를 추가합니다. C 스타일 문자열로 만들기 위해 필요합니다.
    if (len > 0) packetBuffer[len] = 0;

    // 버퍼의 내용을 String 객체로 변환합니다.
    String msg = String(packetBuffer);

    // 수신된 메시지가 FIND_ESP이면 ESP32 기기의 IP 주소를 응답으로 보냅니다.
    if (msg == "FIND_ESP") {
      Serial.println("[UDP] FIND_ESP received, sending IP");
      // 응답 패킷을 생성하기 시작합니다. 송신자의 IP 주소와 포트를 사용합니다.
      udp.beginPacket(udp.remoteIP(), udp.remotePort());
      // ESP32의 로컬 IP 주소를 문자열로 변환하여 패킷에 추가합니다.
      udp.print(WiFi.localIP().toString());
      // 패킷 전송을 완료합니다.
      udp.endPacket();
    } else {
      Serial.print("[UDP] Unknown message: ");
      Serial.println(msg);
    }
  }
}

// 졸음 감지 신호를 처리하는 함수입니다. HTTP 요청으로 호출됩니다.
void handleSleep() {
  // HTTP 200 응답을 보내서 요청이 성공적으로 처리되었음을 알립니다.
  server.send(200, "text/plain", "WAKE UP ACTION STARTED");
  // 졸음 감지 시 수행할 하드웨어 동작을 시작합니다.
  wakeUpRoutine();
}

// 졸음 감지 시 사용자를 깨우기 위한 하드웨어 동작을 수행하는 함수입니다.
void wakeUpRoutine() {
  // 릴레이를 켜서 팬이나 펠티어 등의 장치를 작동시킵니다. HIGH 신호는 릴레이를 켭니다.
  digitalWrite(relayPin, HIGH);

  // 서보 모터를 3번 흔들어서 사용자를 깨웁니다.
  for (int i = 0; i < 3; i++) {
    // 서보 모터를 0도에서 90도로 이동시킵니다. 1도씩 증가하며 이동합니다.
    for (pos = 0; pos <= 90; pos += 1) { 
      // 첫 번째 서보 모터를 현재 위치로 이동시킵니다.
      servo1.write(pos);
      // 두 번째 서보 모터를 반대 방향으로 이동시킵니다. 90도에서 현재 위치를 빼서 반대 방향으로 만듭니다.
      servo2.write(90 - pos);
      // 15ms 동안 대기합니다. 서보 모터가 부드럽게 움직이도록 합니다.
      delay(15);
    }
    // 서보 모터를 90도에서 0도로 이동시킵니다. 1도씩 감소하며 이동합니다.
    for (pos = 90; pos >= 0; pos -= 1) { 
      // 첫 번째 서보 모터를 현재 위치로 이동시킵니다.
      servo1.write(pos);
      // 두 번째 서보 모터를 반대 방향으로 이동시킵니다.
      servo2.write(90 - pos);
      // 15ms 동안 대기합니다.
      delay(15);
    }
  }
  // 7초 동안 대기합니다. 팬이나 펠티어가 작동하여 바람을 쐬는 시간을 제공합니다.
  delay(7000);
  
  // 릴레이를 끕니다. 팬이나 펠티어 등의 장치를 중지합니다.
  digitalWrite(relayPin, LOW);
  // 첫 번째 서보 모터를 0도 위치로 복귀시킵니다.
  servo1.write(0);
  // 두 번째 서보 모터를 0도 위치로 복귀시킵니다.
  servo2.write(0);
}
