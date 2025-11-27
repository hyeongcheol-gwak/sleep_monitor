import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class NetworkService {
  static const String _ipPrefKey = 'esp_ip_address';
  static const int _udpPort = 4210; // ESP32와 동일한 포트

  // [기능 추가] 자동으로 ESP32를 찾아 IP를 반환하는 함수
  static Future<String?> findEspDevice() async {
    RawDatagramSocket? socket;
    try {
      // 1. UDP 소켓 열기
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true; // 방송 모드 켜기

      print("UDP Scanning started...");

      // 2. "FIND_ESP" 메시지 방송 (255.255.255.255로 전송)
      // utf8 인코딩이 필요할 수 있으나 간단한 아스키 코드로 전송
      List<int> data = "FIND_ESP".codeUnits;
      socket.send(data, InternetAddress('255.255.255.255'), _udpPort);

      // 3. 응답 기다리기 (Completer를 사용하여 첫 번째 응답만 취함)
      Completer<String?> completer = Completer();

      // 소켓 데이터 리스너
      StreamSubscription? subscription;
      subscription = socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? dg = socket!.receive();
          if (dg != null) {
            String message = String.fromCharCodes(dg.data).trim();
            print("Received response from ESP: $message");

            // 응답이 IP 형식인지 확인 (간단한 체크)
            if (message.split('.').length == 4) {
              if (!completer.isCompleted) {
                completer.complete(message); // IP 찾음!
              }
            }
          }
        }
      });

      // 4. 3초간 기다려보고 응답 없으면 null 반환
      return await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          print("UDP Scan timeout.");
          return null;
        },
      ).whenComplete(() {
        subscription?.cancel();
        socket?.close();
      });

    } catch (e) {
      print("UDP Error: $e");
      socket?.close();
      return null;
    }
  }

  static Future<void> sendSleepSignal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? espIp = prefs.getString(_ipPrefKey);

      if (espIp == null || espIp.isEmpty) {
        print("네트워크 오류: ESP IP 주소가 설정되지 않았습니다.");
        return;
      }

      final url = Uri.parse('http://$espIp/sleep');

      print("Sending signal to $url");
      // 타임아웃을 짧게 주어 앱 멈춤 방지
      await http.get(url).timeout(const Duration(seconds: 2));
      print("Signal sent successfully.");

    } catch (e) {
      print("네트워크 오류 (sendSleepSignal): $e");
    }
  }

  static Future<void> saveIpAddress(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ipPrefKey, ip);
    print("IP 주소 저장 완료: $ip");
  }

  static Future<String> getIpAddress() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_ipPrefKey) ?? "";
  }
}