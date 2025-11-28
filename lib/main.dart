import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sleep_monitor/services/ml_service.dart';
import 'package:sleep_monitor/services/network_service.dart';

// 애플리케이션의 진입점 함수입니다. 비동기로 실행되며 카메라를 초기화하고 앱을 시작합니다.
Future<void> main() async {
  // Flutter 위젯 바인딩을 초기화합니다. 이는 Flutter 프레임워크가 제대로 작동하기 위해 필요합니다.
  WidgetsFlutterBinding.ensureInitialized();

  // 디바이스에서 사용 가능한 모든 카메라 목록을 가져옵니다.
  final cameras = await availableCameras();
  // 전면 카메라를 우선적으로 선택하고, 전면 카메라가 없으면 첫 번째 카메라를 사용합니다.
  final CameraDescription selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
    orElse: () => cameras.first,
  );

  // 선택된 카메라로 앱을 시작합니다.
  runApp(MyApp(camera: selectedCamera));
}

// 메인 애플리케이션 위젯입니다. 앱의 전역 설정과 테마를 정의합니다.
class MyApp extends StatelessWidget {
  // 사용할 카메라 정보를 저장하는 변수입니다.
  final CameraDescription camera;
  const MyApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    // Material Design 스타일의 앱을 생성합니다.
    return MaterialApp(
      // 앱의 제목을 설정합니다.
      title: 'Sleep Detector',
      // 디버그 모드에서 우측 상단의 배너를 숨깁니다.
      debugShowCheckedModeBanner: false,
      // 다크 테마를 기반으로 커스텀 테마를 설정합니다.
      theme: ThemeData.dark().copyWith(
        // 스캐폴드 배경색을 어두운 회색으로 설정합니다.
        scaffoldBackgroundColor: const Color(0xFF121212),
        // 앱바 테마를 설정합니다. 투명 배경과 흰색 텍스트를 사용합니다.
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        // 색상 스키마를 설정합니다. 블루그레이를 기본 색상으로 사용합니다.
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.blueGrey,
        ).copyWith(
          secondary: Colors.white70,
        ),
        // 입력 필드의 장식 테마를 설정합니다. 포커스 시와 일반 상태의 테두리 색상을 정의합니다.
        inputDecorationTheme: const InputDecorationTheme(
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white54),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey),
          ),
          labelStyle: TextStyle(color: Colors.white70),
          hintStyle: TextStyle(color: Colors.white54),
        ),
        // 텍스트 버튼의 테마를 설정합니다. 흰색 텍스트를 사용합니다.
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
          ),
        ),
      ),
      // 앱의 홈 화면으로 졸음 감지 페이지를 설정합니다.
      home: SleepDetectorPage(camera: camera),
    );
  }
}

// 졸음 감지 기능을 제공하는 메인 페이지 위젯입니다. StatefulWidget으로 상태 관리를 합니다.
class SleepDetectorPage extends StatefulWidget {
  // 사용할 카메라 정보를 저장하는 변수입니다.
  final CameraDescription camera;
  const SleepDetectorPage({super.key, required this.camera});

  @override
  State<SleepDetectorPage> createState() => _SleepDetectorPageState();
}

// 졸음 감지 페이지의 상태를 관리하는 클래스입니다. 앱 생명주기 관찰 기능을 포함합니다.
class _SleepDetectorPageState extends State<SleepDetectorPage> with WidgetsBindingObserver {
  // 카메라 제어를 위한 컨트롤러입니다. 카메라 스트림을 관리합니다.
  CameraController? _cameraController;
  // 머신러닝 서비스를 저장하는 변수입니다. 얼굴 감지와 졸음 감지 기능을 제공합니다.
  late MLService _mlService;
  // 현재 졸음 상태를 나타내는 플래그입니다. true이면 졸음 상태입니다.
  bool _isSleeping = false;
  // 이미지 처리 중인지 여부를 나타내는 플래그입니다. 중복 처리를 방지합니다.
  bool _isProcessing = false;
  // ESP32 기기의 IP 주소를 입력받기 위한 텍스트 컨트롤러입니다.
  final TextEditingController _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 머신러닝 서비스 인스턴스를 생성합니다.
    _mlService = MLService();
    // 앱 생명주기 관찰자를 등록합니다. 앱이 백그라운드로 가거나 포그라운드로 올 때를 감지합니다.
    WidgetsBinding.instance.addObserver(this);
    // 저장된 IP 주소를 불러옵니다.
    _loadSavedIp();
    // 카메라를 초기화합니다.
    _initializeCamera();

    // 졸음 상태 스트림을 구독하여 상태 변화를 감지합니다.
    _mlService.sleepStateStream.listen((isSleeping) {
      // 위젯이 마운트되어 있는지 확인한 후 상태를 업데이트합니다.
      if (mounted) {
        setState(() {
          _isSleeping = isSleeping;
        });
      }
      // 졸음 상태가 감지되면 ESP32 기기에 신호를 보냅니다.
      if (isSleeping) {
        NetworkService.sendSleepSignal();
      }
    });
  }

  // 저장된 IP 주소를 불러와서 텍스트 필드에 표시합니다.
  void _loadSavedIp() async {
    _ipController.text = await NetworkService.getIpAddress();
  }

  @override
  // 앱의 생명주기 상태가 변경될 때 호출되는 콜백 함수입니다.
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final controller = _cameraController;
    // 카메라 컨트롤러가 없거나 초기화되지 않았으면 함수를 종료합니다.
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    // 앱이 일시정지 상태가 되면 카메라 이미지 스트림을 중지합니다.
    if (state == AppLifecycleState.paused) {
      controller.stopImageStream();
    // 앱이 다시 활성화되면 카메라 이미지 스트림을 재시작합니다.
    } else if (state == AppLifecycleState.resumed) {
      try {
        controller.startImageStream(_processCameraImage);
      } catch (e) {}
    }
  }

  // 카메라를 초기화하고 이미지 스트림을 시작하는 함수입니다.
  void _initializeCamera() async {
    // 카메라 컨트롤러를 생성합니다. 고해상도 프리셋을 사용하고 오디오는 비활성화합니다.
    _cameraController = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      // 카메라를 초기화합니다.
      await _cameraController!.initialize();
      // 이미지 스트림을 시작하고 각 프레임마다 처리 함수를 호출합니다.
      await _cameraController!.startImageStream(_processCameraImage);
      // 위젯이 마운트되어 있으면 상태를 업데이트합니다.
      if (mounted) {
        setState(() {});
      }
    } catch (e) {}
  }

  // 카메라에서 받은 이미지를 처리하는 함수입니다. 머신러닝 서비스에 전달하여 졸음을 감지합니다.
  void _processCameraImage(CameraImage image) {
    // 이미 처리 중이면 함수를 종료합니다. 중복 처리를 방지합니다.
    if (_isProcessing) return;
    // 처리 중 플래그를 true로 설정합니다.
    _isProcessing = true;
    // 머신러닝 서비스에 이미지를 전달하여 처리합니다. 처리가 완료되면 플래그를 false로 설정합니다.
    _mlService.processCameraImage(image, widget.camera).whenComplete(() {
      _isProcessing = false;
    });
  }

  @override
  // 위젯이 제거될 때 호출되는 함수입니다. 리소스를 정리합니다.
  void dispose() {
    // 앱 생명주기 관찰자를 제거합니다.
    WidgetsBinding.instance.removeObserver(this);
    // 카메라 이미지 스트림을 중지합니다.
    _cameraController?.stopImageStream();
    // 카메라 컨트롤러를 해제합니다.
    _cameraController?.dispose();
    // 머신러닝 서비스를 해제합니다.
    _mlService.dispose();
    // 텍스트 컨트롤러를 해제합니다.
    _ipController.dispose();
    super.dispose();
  }

  @override
  // UI를 구성하는 빌드 함수입니다.
  Widget build(BuildContext context) {
    final controller = _cameraController;

    // 카메라 컨트롤러가 없거나 초기화되지 않았으면 로딩 인디케이터를 표시합니다.
    if (controller == null || !controller.value.isInitialized) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Theme.of(context).colorScheme.secondary),
        ),
      );
    }

    // 카메라 프리뷰의 가로세로 비율을 설정합니다. 3:4 비율을 사용합니다.
    const double targetCameraRatio = 3 / 4;

    // 스캐폴드를 반환합니다. 스택 레이아웃을 사용하여 여러 위젯을 겹쳐서 배치합니다.
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          // 배경 컨테이너입니다. 스캐폴드 배경색으로 채웁니다.
          Container(color: Theme.of(context).scaffoldBackgroundColor),
          // 카메라 프리뷰를 표시합니다. 설정된 비율에 맞춰 표시됩니다.
          AspectRatio(
            aspectRatio: targetCameraRatio,
            child: CameraPreview(controller),
          ),
          // 우측 상단에 설정 버튼을 배치합니다.
          Positioned(
            top: 40,
            right: 20,
            child: IconButton(
              icon: const Icon(Icons.settings, color: Colors.white, size: 28),
              onPressed: () {
                _showIpSettingsDialog(context);
              },
            ),
          ),
          // 하단에 상태 표시기를 배치합니다.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor.withAlpha(102),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatusIndicator(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 졸음 상태를 표시하는 인디케이터 위젯을 생성하는 함수입니다.
  Widget _buildStatusIndicator() {
    return Container(
      // 컨테이너의 내부 여백을 설정합니다.
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        // 졸음 상태에 따라 빨간색 또는 초록색 배경을 사용합니다.
        color: _isSleeping ? Colors.red.withValues(alpha: 0.6) : Colors.green.withValues(alpha: 0.6),
        // 둥근 모서리를 설정합니다.
        borderRadius: BorderRadius.circular(25),
        // 그림자 효과를 추가합니다.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 졸음 상태에 따라 다른 아이콘을 표시합니다. 졸음이면 침대 아이콘, 깨어있으면 태양 아이콘입니다.
          Icon(
            _isSleeping ? Icons.bedtime : Icons.wb_sunny,
            color: Colors.white,
            size: 24,
          ),
          const SizedBox(width: 10),
          // 졸음 상태에 따라 다른 텍스트를 표시합니다.
          Text(
            _isSleeping ? "수면 중입니다" : "깨어있습니다",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ESP32 기기의 IP 주소를 설정하는 다이얼로그를 표시하는 함수입니다.
  Future<void> _showIpSettingsDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      // 다이얼로그 외부를 탭하여 닫을 수 있도록 설정합니다.
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        // 기기 검색 중인지 여부를 나타내는 로컬 상태 변수입니다.
        bool isScanning = false;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              // 다이얼로그 배경색을 어두운 회색으로 설정합니다.
              backgroundColor: const Color(0xFF202020),
              title: const Text('ESP 연결 설정', style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    // 사용자에게 안내 메시지를 표시합니다.
                    const Text(
                      'ESP32와 같은 Wi-Fi나 핫스팟에 연결되어 있어야 합니다.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        // IP 주소를 입력받는 텍스트 필드입니다.
                        Expanded(
                          child: TextField(
                            controller: _ipController,
                            decoration: const InputDecoration(
                              labelText: 'IP 주소',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 검색 중이면 로딩 인디케이터를 표시하고, 그렇지 않으면 검색 버튼을 표시합니다.
                        isScanning
                            ? const Padding(
                          padding: EdgeInsets.all(12.0),
                          child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2)
                          ),
                        )
                            : IconButton(
                          icon: const Icon(Icons.search, color: Colors.blueAccent),
                          tooltip: "자동으로 기기 찾기",
                          onPressed: () async {
                            // 검색 시작 상태로 변경합니다.
                            setState(() { isScanning = true; });

                            // 네트워크 서비스를 통해 ESP32 기기를 찾습니다.
                            String? foundIp = await NetworkService.findEspDevice();

                            // 위젯이 마운트되어 있지 않으면 함수를 종료합니다.
                            if (!context.mounted) return;

                            // 기기를 찾았으면 IP 주소를 텍스트 필드에 설정하고 성공 메시지를 표시합니다.
                            if (foundIp != null) {
                              _ipController.text = foundIp;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("기기를 찾았습니다: $foundIp")),
                              );
                            // 기기를 찾지 못했으면 실패 메시지를 표시합니다.
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("기기를 찾을 수 없습니다. 핫스팟 연결을 확인하세요.")),
                              );
                            }

                            // 검색 완료 상태로 변경합니다.
                            setState(() { isScanning = false; });
                          },
                        ),
                      ],
                    ),
                    // 검색 중일 때 안내 메시지를 표시합니다.
                    if (isScanning)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text("기기를 검색 중입니다...", style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
                      ),
                  ],
                ),
              ),
              // 다이얼로그 하단에 취소와 저장 버튼을 배치합니다.
              actions: <Widget>[
                TextButton(
                  child: const Text('취소', style: TextStyle(color: Colors.white70)),
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
                TextButton(
                  child: Text('저장', style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
                  onPressed: () {
                    // 입력된 IP 주소를 저장합니다.
                    NetworkService.saveIpAddress(_ipController.text);
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}
