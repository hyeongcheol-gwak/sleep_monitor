import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// 네트워크 통신을 처리하는 서비스 클래스입니다. ESP32 기기와의 통신을 담당합니다.
class NetworkService {
  // SharedPreferences에 저장할 때 사용하는 IP 주소 키입니다.
  static const String _ipPrefKey = 'esp_ip_address';
  // UDP 통신에 사용할 포트 번호입니다. ESP32와 동일한 포트를 사용해야 합니다.
  static const int _udpPort = 4210;

  // ESP32 기기를 네트워크에서 찾는 함수입니다. UDP 브로드캐스트를 사용하여 기기를 검색합니다.
  static Future<String?> findEspDevice() async {
    RawDatagramSocket? socket;
    try {
      // IPv4 주소를 사용하여 UDP 소켓을 생성합니다. 0번 포트는 시스템이 자동으로 할당합니다.
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      // 브로드캐스트 전송을 활성화합니다. 네트워크의 모든 기기에 메시지를 보낼 수 있습니다.
      socket.broadcastEnabled = true;

      // ESP32 기기를 찾기 위해 보낼 메시지를 바이트 배열로 변환합니다.
      List<int> data = "FIND_ESP".codeUnits;

      // 전체 네트워크에 브로드캐스트 메시지를 전송합니다. 255.255.255.255는 모든 기기에 메시지를 보냅니다.
      try {
        socket.send(data, InternetAddress('255.255.255.255'), _udpPort);
      } catch (e) {}

      // 일반적인 안드로이드 핫스팟 대역에 브로드캐스트 메시지를 전송합니다. 192.168.43.0 네트워크의 모든 기기에 메시지를 보냅니다.
      try {
        socket.send(data, InternetAddress('192.168.43.255'), _udpPort);
      } catch (e) {}

      // 특정 핫스팟 대역에 브로드캐스트 메시지를 전송합니다. 172.29.158.0 네트워크의 모든 기기에 메시지를 보냅니다.
      try {
        socket.send(data, InternetAddress('172.29.158.255'), _udpPort);
      } catch (e) {}

      // 현재 연결된 네트워크 인터페이스의 서브넷 브로드캐스트 주소로도 전송합니다.
      // 이를 통해 10.x.x.x, 192.168.x.x, 172.x.x.x 등 모든 IP 대역을 지원합니다.
      try {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
          includeLoopback: false,
        );
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            // IPv4 주소만 처리합니다.
            if (addr.type != InternetAddressType.IPv4) continue;
            
            // IP 주소의 옥텟을 추출합니다.
            final octets = addr.rawAddress;
            if (octets.length == 4) {
              // 서브넷의 브로드캐스트 주소를 생성합니다 (마지막 옥텟을 255로 설정).
              final broadcastAddr = InternetAddress(
                  "${octets[0]}.${octets[1]}.${octets[2]}.255");
              try {
                socket.send(data, broadcastAddr, _udpPort);
              } catch (e) {
                // 브로드캐스트 전송 실패는 무시합니다.
              }
            }
          }
        }
      } catch (e) {
        // 네트워크 인터페이스 목록 조회 실패는 무시합니다.
      }

      // 비동기 작업의 완료를 알리기 위한 Completer 객체를 생성합니다.
      Completer<String?> completer = Completer();

      // 소켓 이벤트를 수신하기 위한 스트림 구독 객체입니다.
      StreamSubscription? subscription;
      // 소켓에서 발생하는 이벤트를 수신합니다.
      subscription = socket.listen((RawSocketEvent event) {
        // 읽기 이벤트가 발생하면 데이터를 수신합니다.
        if (event == RawSocketEvent.read) {
          // 소켓에서 데이터그램을 수신합니다.
          Datagram? dg = socket!.receive();
          if (dg != null) {
            // 수신된 데이터를 문자열로 변환합니다.
            String message = String.fromCharCodes(dg.data).trim();

            // 메시지가 IP 주소 형식인지 확인합니다. 점이 3개 있으면 IP 주소 형식입니다.
            if (message.split('.').length == 4) {
              // 아직 완료되지 않았으면 IP 주소를 반환합니다.
              if (!completer.isCompleted) {
                completer.complete(message);
              }
            }
          }
        }
      });

      // 3초 동안 응답을 기다립니다. 시간 내에 응답이 없으면 null을 반환합니다.
      return await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          return null;
        },
      ).whenComplete(() {
        // 스트림 구독을 취소합니다.
        subscription?.cancel();
        // 소켓을 닫습니다.
        socket?.close();
      });

    } catch (e) {
      socket?.close();
      return null;
    }
  }

  // 졸음 감지 신호를 ESP32 기기에 전송하는 함수입니다. HTTP GET 요청을 사용합니다.
  static Future<void> sendSleepSignal() async {
    try {
      // SharedPreferences 인스턴스를 가져옵니다. 로컬 저장소에 접근하기 위해 사용합니다.
      final prefs = await SharedPreferences.getInstance();
      // 저장된 ESP32 기기의 IP 주소를 가져옵니다.
      final String? espIp = prefs.getString(_ipPrefKey);

      // IP 주소가 없거나 비어있으면 함수를 종료합니다.
      if (espIp == null || espIp.isEmpty) {
        return;
      }

      // ESP32 기기의 /sleep 엔드포인트로 요청을 보낼 URL을 생성합니다.
      final url = Uri.parse('http://$espIp/sleep');

      // HTTP GET 요청을 보냅니다. 7초 내에 응답이 없으면 타임아웃됩니다.
      await http.get(url).timeout(const Duration(seconds: 7));
    } catch (e) {
    }
  }

  // ESP32 기기의 IP 주소를 로컬 저장소에 저장하는 함수입니다.
  static Future<void> saveIpAddress(String ip) async {
    // SharedPreferences 인스턴스를 가져옵니다.
    final prefs = await SharedPreferences.getInstance();
    // IP 주소를 지정된 키로 저장합니다.
    await prefs.setString(_ipPrefKey, ip);
  }

  // 저장된 ESP32 기기의 IP 주소를 가져오는 함수입니다.
  static Future<String> getIpAddress() async {
    // SharedPreferences 인스턴스를 가져옵니다.
    final prefs = await SharedPreferences.getInstance();
    // 저장된 IP 주소를 가져옵니다. 없으면 빈 문자열을 반환합니다.
    return prefs.getString(_ipPrefKey) ?? "";
  }
}
