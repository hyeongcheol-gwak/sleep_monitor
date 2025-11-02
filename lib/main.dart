import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:sleep_monitor/services/ml_service.dart';
import 'package:sleep_monitor/services/network_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final cameras = await availableCameras();
  final CameraDescription selectedCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
    orElse: () {
      print("경고: 전면 카메라를 찾을 수 없습니다. 후면 카메라로 대체합니다.");
      return cameras.first;
    },
  );

  runApp(MyApp(camera: selectedCamera));
}

class MyApp extends StatelessWidget {
  final CameraDescription camera;
  const MyApp({super.key, required this.camera});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sleep Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        // 전체 앱의 배경색을 진한 회색으로 변경 (미니멀)
        scaffoldBackgroundColor: const Color(0xFF121212),
        // 앱 바는 아예 없애거나 투명하게 하여 UI를 최소화합니다.
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent, // 투명
          foregroundColor: Colors.white,
          elevation: 0, // 그림자 제거
        ),
        // 전반적인 액센트 색상을 회색 톤으로 통일하거나 최소화
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.blueGrey, // 기본 색상은 크게 중요하지 않음
        ).copyWith(
          secondary: Colors.white70, // 보조 액센트 색상 (버튼, 로딩 등)
        ),
        // 텍스트 필드 테마 (IP 설정 다이얼로그)
        inputDecorationTheme: const InputDecorationTheme(
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white54), // 포커스 시 테두리색
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.grey), // 기본 테두리색
          ),
          labelStyle: TextStyle(color: Colors.white70),
          hintStyle: TextStyle(color: Colors.white54),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white, // 텍스트 버튼 기본 색상
          ),
        ),
      ),
      home: SleepDetectorPage(camera: camera),
    );
  }
}

class SleepDetectorPage extends StatefulWidget {
  final CameraDescription camera;
  const SleepDetectorPage({super.key, required this.camera});

  @override
  State<SleepDetectorPage> createState() => _SleepDetectorPageState();
}

class _SleepDetectorPageState extends State<SleepDetectorPage> with WidgetsBindingObserver {
  CameraController? _cameraController;
  late MLService _mlService;
  bool _isSleeping = false;
  bool _isProcessing = false;
  final TextEditingController _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _mlService = MLService();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedIp();
    _initializeCamera();

    _mlService.sleepStateStream.listen((isSleeping) {
      if (mounted) {
        setState(() {
          _isSleeping = isSleeping;
        });
      }
      if (isSleeping) {
        NetworkService.sendSleepSignal();
      }
    });
  }

  void _loadSavedIp() async {
    _ipController.text = await NetworkService.getIpAddress();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.paused) {
      controller.stopImageStream();
      print("앱이 일시정지되어 카메라 스트림을 멈춥니다.");
    } else if (state == AppLifecycleState.resumed) {
      print("앱이 다시 활성화되어 카메라 스트림을 시작합니다.");
      try {
        controller.startImageStream(_processCameraImage);
      } catch (e) {
        print("!!! 카메라 스트림 재시작 실패: $e");
      }
    }
  }

  void _initializeCamera() async {
    _cameraController = CameraController(
      widget.camera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      await _cameraController!.startImageStream(_processCameraImage);
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print("!!! 카메라 초기화 실패: $e");
    }
  }

  void _processCameraImage(CameraImage image) {
    if (_isProcessing) return;
    _isProcessing = true;
    _mlService.processCameraImage(image, widget.camera).whenComplete(() {
      _isProcessing = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _mlService.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;

    if (controller == null || !controller.value.isInitialized) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: Theme.of(context).colorScheme.secondary),
        ),
      );
    }

    const double targetCameraRatio = 3 / 4;

    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          // 1. 레터박스 배경 (0xFF121212)
          Container(color: Theme.of(context).scaffoldBackgroundColor),

          // 2. 카메라 미리보기
          AspectRatio(
            aspectRatio: targetCameraRatio,
            child: CameraPreview(controller),
          ),

          // 3. 상단 설정 아이콘
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

          // 4. 하단 컨트롤 UI
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
              decoration: BoxDecoration(
                // --- ★★★ 수정된 부분 ★★★ ---
                // Colors.black.withAlpha(102) (순수 검정) 대신,
                // 앱의 배경색(0xFF121212)을 가져와서 투명도를 적용합니다.
                color: Theme.of(context).scaffoldBackgroundColor.withAlpha(102),
                // --- ★★★ 수정 끝 ★★★ ---
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

  // 수면 상태를 표시하는 위젯 (디자인 변경)
  Widget _buildStatusIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10), // 패딩 줄임
      // margin은 제거하여 Container가 하단 바에 더 붙어 보이게
      decoration: BoxDecoration(
        // 색상 채도 낮추고 불투명도 조절
        color: _isSleeping ? Colors.red.withOpacity(0.6) : Colors.green.withOpacity(0.6),
        borderRadius: BorderRadius.circular(25), // 둥글게
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2), // 그림자 연하게
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
          Icon(
            _isSleeping ? Icons.bedtime : Icons.wb_sunny,
            color: Colors.white,
            size: 24, // 아이콘 크기 줄임
          ),
          const SizedBox(width: 10), // 여백 줄임
          Text(
            _isSleeping ? "수면 중입니다" : "깨어있습니다",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18, // 텍스트 크기 줄임
              fontWeight: FontWeight.w600, // 굵기 조절
            ),
          ),
        ],
      ),
    );
  }

  // IP 설정 다이얼로그 (색상 등 테마에 맞게 조정)
  Future<void> _showIpSettingsDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF202020), // 다이얼로그 배경색
          title: const Text('ESP IP 주소 설정', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                const Text('핫스팟 \'연결된 기기\' 목록에서\nESP의 IP 주소를 확인 후 입력하세요.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 16),
                TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: '예: 192.168.43.102',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('취소', style: TextStyle(color: Colors.white70)),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text('저장', style: TextStyle(color: Theme.of(context).colorScheme.secondary)), // 테마색 사용
              onPressed: () {
                NetworkService.saveIpAddress(_ipController.text);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}