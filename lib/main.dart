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
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.blueGrey,
        ).copyWith(
          secondary: Colors.white70,
        ),
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
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
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
          Container(color: Theme.of(context).scaffoldBackgroundColor),
          AspectRatio(
            aspectRatio: targetCameraRatio,
            child: CameraPreview(controller),
          ),
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

  Widget _buildStatusIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: _isSleeping ? Colors.red.withOpacity(0.6) : Colors.green.withOpacity(0.6),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
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
            size: 24,
          ),
          const SizedBox(width: 10),
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

  Future<void> _showIpSettingsDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF202020),
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
              child: Text('저장', style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
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