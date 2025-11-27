import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:audioplayers/audioplayers.dart';

class MLService {
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  final StreamController<bool> _sleepStateController = StreamController<bool>.broadcast();
  Stream<bool> get sleepStateStream => _sleepStateController.stream;

  final AudioPlayer _audioPlayer = AudioPlayer();

  Timer? _sleepTimer;
  bool _isSleeping = false;
  Timer? _beepGapTimer;
  StreamSubscription<void>? _beepLoopSubscription;

  static const Duration _sleepThreshold = Duration(seconds: 2);
  static const double _eyeOpenThreshold = 0.4;
  static const Duration _beepGap = Duration(milliseconds: 400);

  Future<void> processCameraImage(CameraImage cameraImage, CameraDescription camera) async {
    final InputImage? inputImage = _createInputImage(cameraImage, camera);
    if (inputImage == null) {
      print("이미지 변환 실패. 포맷을 지원하지 않습니다.");
      return;
    }

    final List<Face> faces = await _faceDetector.processImage(inputImage);

    _detectSleep(faces);
  }

  void _detectSleep(List<Face> faces) {
    if (faces.isEmpty) {
      _resetSleepTimer("No face detected");
      return;
    }

    final Face face = faces.first;
    final double? leftEyeProb = face.leftEyeOpenProbability;
    final double? rightEyeProb = face.rightEyeOpenProbability;

    if (leftEyeProb == null || rightEyeProb == null) {
      _resetSleepTimer("Eye probability not available");
      return;
    }

    if (leftEyeProb < _eyeOpenThreshold && rightEyeProb < _eyeOpenThreshold) {
      if (!_isSleeping) {
        _startSleepTimer();
      }

    } else {
      _resetSleepTimer("Eyes are open");
    }
  }

  void _startSleepTimer() {
    if (_sleepTimer != null && _sleepTimer!.isActive) return;

    _sleepTimer = Timer(_sleepThreshold, () {
      if (!_isSleeping) {
        print("--- SLEEP DETECTED! '수면' 상태로 전환 ---");

        _isSleeping = true;
        _startBeepLoop();
        _sleepStateController.add(true);
      }
    });
  }

  void _resetSleepTimer(String reason) {
    if (_sleepTimer != null && _sleepTimer!.isActive) {
      _sleepTimer!.cancel();
    }

    if (_isSleeping) {
      print("--- EYES OPEN! ($reason) 사운드 정지 및 상태 리셋 ---");
      _stopBeepLoop();
    }

    if (_isSleeping) {
      _sleepStateController.add(false);
    }
    _isSleeping = false;
  }

  void dispose() {
    _faceDetector.close();
    _sleepStateController.close();
    _sleepTimer?.cancel();
    _stopBeepLoop();
    _audioPlayer.dispose();
  }

  InputImage? _createInputImage(CameraImage image, CameraDescription camera) {
    final InputImageRotation rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.rotation0deg;

    if (image.format.group == ImageFormatGroup.yuv420) {
      final format = InputImageFormat.nv21;

      final bytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        bytes.putUint8List(plane.bytes);
      }
      final allBytes = bytes.done().buffer.asUint8List();

      final InputImageMetadata metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: allBytes,
        metadata: metadata,
      );
    } else if (image.format.group == ImageFormatGroup.bgra8888) {
      final format = InputImageFormat.bgra8888;
      final allBytes = image.planes[0].bytes;

      final InputImageMetadata metadata = InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      return InputImage.fromBytes(
        bytes: allBytes,
        metadata: metadata,
      );
    } else {
      print("지원하지 않는 이미지 포맷입니다: ${image.format.group}");
      return null;
    }
  }

  void _startBeepLoop() {
    _beepGapTimer?.cancel();
    _beepLoopSubscription?.cancel();
    _audioPlayer.stop();
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
    _beepLoopSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      _scheduleNextBeep();
    });
    _playBeep();
  }

  void _scheduleNextBeep() {
    _beepGapTimer?.cancel();
    if (!_isSleeping) return;
    _beepGapTimer = Timer(_beepGap, () {
      if (_isSleeping) {
        _playBeep();
      }
    });
  }

  Future<void> _playBeep() async {
    try {
      await _audioPlayer.play(AssetSource('audio/beep_warning.mp3'));
    } catch (e) {
      print("'beep_warning.mp3' 재생 실패: $e");
    }
  }

  void _stopBeepLoop() {
    _beepGapTimer?.cancel();
    _beepLoopSubscription?.cancel();
    _audioPlayer.stop();
  }
}