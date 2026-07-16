import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';

import '../core/services/pose_detector_service.dart';
import '../core/services/logging_service.dart';
import '../core/api/training_service.dart';
import '../features/auth/providers/auth_provider.dart';
import '../core/models/exercise_type.dart';
import '../theme.dart';
import 'result_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET
// ─────────────────────────────────────────────────────────────────────────────

class TrainingScreen extends StatefulWidget {
  final ExerciseType exerciseType;
  final int targetReps;

  const TrainingScreen({
    super.key,
    required this.exerciseType,
    required this.targetReps,
  });

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  // ── Camera ────────────────────────────────────────────────────────
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isCameraInitialized = false;

  // ── Pose Detection ────────────────────────────────────────────────
  final PoseDetectorService _poseService = PoseDetectorService();

  // SATU flag — tidak ada frame yang diproses bersamaan
  bool _isProcessingFrame = false;

  // ── Backend / WebSocket ───────────────────────────────────────────
  late TrainingService _trainingService;
  bool _isEvaluationStarted = false;

  // ── UI State ──────────────────────────────────────────────────────
  String _currentFeedback = 'Tekan Mulai Evaluasi';
  String _currentState = '-';
  String _connectionStatus = 'Belum terhubung';
  int _reps = 0;
  int _countdown = 3;
  final List<RepetitionDetail> _repHistory = [];

  // ── Audio ─────────────────────────────────────────────────────────
  late AudioPlayer _audioPlayer;

  // ── FPS Monitor ───────────────────────────────────────────────────
  int _totalFrames = 0; // semua frame dari kamera
  int _processedFrames = 0; // frame yang benar-benar diproses ML Kit
  int _droppedFrames = 0; // frame yang di-skip
  DateTime _fpsWindowStart = DateTime.now();
  double _currentFps = 0;
  double _processedFps = 0;

  // ── Throttling adaptif ────────────────────────────────────────────
  DateTime? _lastProcessedTime;
  static const Duration _targetInterval = Duration(milliseconds: 100); // ~10fps

  // ── Logger ────────────────────────────────────────────────────────
  final TrainingLogger _logger = TrainingLogger();
  DateTime? _evalStartTime;

  // ─────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.stop);
    _poseService.initialize();
    _initService();
    _initCamera();
  }

  @override
  void dispose() {
    // Urutan dispose penting — stop stream dulu, lalu resources
    _stopEvaluation();
    _controller?.dispose();
    _poseService.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────
  // INIT SERVICE
  // ─────────────────────────────────────────────────────────────────────

  void _initService() {
    _trainingService = TrainingService(
      onEvaluationReceived: (result) {
        _logger.logBackendResponse(result);
        if (!mounted) return;
        setState(() {
          // [FIX B6-01] Backend kirim 'rep_count', bukan 'reps'
          if (result['status'] == 'rep_completed') {
            final newReps = result['rep_count'] is int
                ? result['rep_count'] as int
                : (result['rep_count'] as num?)?.toInt() ?? _reps;
            
            if (newReps > _reps) {
              _audioPlayer.play(AssetSource('ding.mp3'));
            }
            _reps = newReps;

            _repHistory.add(
              RepetitionDetail(
                repNumber: newReps,
                status: (result['smoothed_prediction'] ?? result['prediction'] ?? 'unknown').toString(),
                confidence: (result['confidence'] as num?)?.toDouble() ?? 1.0,
                feedbackText: (result['feedback'] ?? '').toString(),
              ),
            );
          }

          // Good/Bad Form Indicator sederhana
          final smoothed = result['smoothed_prediction']?.toString();
          if (smoothed != null) {
            _currentFeedback = (smoothed == 'correct') ? '🟢 Good Form' : '🔴 Bad Form';
            _currentState = smoothed.toUpperCase();
          }

          _connectionStatus = 'Terhubung ✓';

          // Auto-stop jika target terpenuhi
          if (_reps >= widget.targetReps && _isEvaluationStarted) {
            _stopEvaluation();
          }
        });
      },
      onError: (error) {
        _logger.logWebSocketError(error); // ← LOG ERROR
        debugPrint('[TrainingScreen] ❌ Service error: $error');
        if (!mounted) return;
        setState(() => _connectionStatus = 'Error: $error');
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // INIT CAMERA
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        debugPrint('[TrainingScreen] ❌ Tidak ada kamera tersedia');
        return;
      }

      // Prioritaskan kamera depan
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      debugPrint(
        '[TrainingScreen] 📷 Kamera: ${camera.name} | '
        'sensorOrientation=${camera.sensorOrientation}',
      );

      _controller = CameraController(
        camera,
        // LOW = mencegah buffer bloat di Infinix/MediaTek
        ResolutionPreset.low,
        enableAudio: false,
        imageFormatGroup:
            defaultTargetPlatform == TargetPlatform.iOS
                ? ImageFormatGroup.bgra8888
                : ImageFormatGroup.yuv420,
      );

      await _controller!.initialize();
      if (!mounted) return;

      setState(() => _isCameraInitialized = true);
      debugPrint('[TrainingScreen] ✅ Kamera siap');

      // ── LOG kamera setelah berhasil init ──────────────────────────
      final previewSize = _controller!.value.previewSize;
      _logger.logCameraInit(
        width: previewSize?.width.toInt() ?? 0,
        height: previewSize?.height.toInt() ?? 0,
        sensorOrientation: camera.sensorOrientation,
        resolution: 'low',
        formatGroup:
            defaultTargetPlatform == TargetPlatform.iOS ? 'bgra8888' : 'yuv420',
      );
    } catch (e) {
      debugPrint('[TrainingScreen] ❌ Error init kamera: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // START / STOP
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _startEvaluation() async {
    if (_isEvaluationStarted) return;

    setState(() {
      _currentFeedback = 'Menghubungkan ke server...';
      _connectionStatus = 'Connecting...';
    });

    // Ambil userId dari AuthProvider
    final userId = context.read<AuthProvider>().userId;
    final effectiveId = userId.isNotEmpty ? userId : 'guest';

    // ── Buka file log ─────────────────────────────────────────────
    await _logger.open();
    _logger.logSessionStart(
      userId: effectiveId,
      exerciseType: widget.exerciseType.backendCode,
    );

    final success = await _trainingService.startSession(
      userId: effectiveId,
      exerciseType: widget.exerciseType.backendCode,
    );

    if (!success) {
      _logger.logWebSocketError(
        'startSession gagal — server tidak dapat dihubungi',
      );
      await _logger.close();
      if (!mounted) return;
      setState(() {
        _currentFeedback = 'Gagal terhubung ke server';
        _connectionStatus = 'Offline';
      });
      return;
    }

    // ── Log WebSocket connect ─────────────────────────────────────
    _logger.logWebSocketConnect(
      url: 'ws://10.93.254.195:8000/ws',
      sessionId: 'connected',
    );

    _evalStartTime = DateTime.now();

    if (!mounted) return;
    setState(() {
      _repHistory.clear();
      _isEvaluationStarted = true;
      _countdown = 3;
      _currentFeedback = 'Bersiap... $_countdown';
      _connectionStatus = 'Terhubung ✓';
      _totalFrames = 0;
      _processedFrames = 0;
      _droppedFrames = 0;
      _fpsWindowStart = DateTime.now();
    });

    // ── Countdown Loop ────────────────────────────────────────────
    while (_countdown > 0) {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted || !_isEvaluationStarted) return;
      setState(() {
        _countdown--;
        if (_countdown > 0) {
          _currentFeedback = 'Bersiap... $_countdown';
        } else {
          _currentFeedback = 'Mulai!';
        }
      });
    }

    try {
      if (_controller != null && _controller!.value.isInitialized && _isEvaluationStarted) {
        await _controller!.startImageStream(_onCameraFrame);
        _logger.logEvalStart();
        debugPrint('[TrainingScreen] 📡 Image stream dimulai');
        debugPrint('[TrainingScreen] 📝 Log: ${_logger.logFilePath}');
      }
    } catch (e) {
      debugPrint('[TrainingScreen] ❌ Gagal start stream: $e');
      setState(() => _currentFeedback = 'Gagal mulai kamera');
    }
  }

  Future<void> _stopEvaluation() async {
    if (!_isEvaluationStarted) return;

    // Stop camera stream terlebih dahulu
    try {
      if (_controller != null && _controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
      }
    } catch (e) {
      debugPrint('[TrainingScreen] ⚠️ Stop stream error: $e');
    }

    // [FIX B2-01] Akhiri sesi ke backend dan ambil hasil
    final sessionResult = await _trainingService.endSession();

    // Log eval stop
    final duration =
        _evalStartTime != null
            ? DateTime.now().difference(_evalStartTime!)
            : Duration.zero;
    _logger.logEvalStop(
      duration: duration,
      totalFrames: _totalFrames + _processedFrames + _droppedFrames,
      processedFrames: _processedFrames,
      reps: _reps,
    );
    await _logger.close();

    if (!mounted) return;
    setState(() {
      _isEvaluationStarted = false;
      _currentFeedback = 'Selesai';
      _connectionStatus = '';
    });

    // [FIX B5-03] Navigasi ke ResultScreen dengan data nyata
    if (sessionResult != null && mounted) {
      final backendErrorDist =
          sessionResult['error_distribution'] as Map<String, dynamic>?;
      final errorDist =
          backendErrorDist?.map((k, v) => MapEntry(k, v as int)) ?? {};

      List<RepetitionDetail> finalRepDetails = [];
      if (sessionResult['rep_results'] is List) {
        for (final item in (sessionResult['rep_results'] as List)) {
          if (item is Map) {
            finalRepDetails.add(
              RepetitionDetail(
                repNumber: (item['rep_number'] as num?)?.toInt() ?? finalRepDetails.length + 1,
                status: (item['smoothed_prediction'] ?? item['prediction'] ?? 'unknown').toString(),
                confidence: (item['confidence'] as num?)?.toDouble() ?? 1.0,
                feedbackText: (item['feedback_text'] ?? item['feedback'] ?? '').toString(),
              ),
            );
          }
        }
      }
      if (finalRepDetails.isEmpty) {
        finalRepDetails = List.from(_repHistory);
      }

      final result = TrainingResult(
        exerciseType: widget.exerciseType,
        totalReps: (sessionResult['total_reps'] as num?)?.toInt() ?? _reps,
        correctReps: (sessionResult['correct_reps'] as num?)?.toInt() ?? 0,
        accuracy: (sessionResult['accuracy'] as num?)?.toDouble() ?? 0.0,
        errorDistribution: errorDist,
        repDetails: finalRepDetails,
      );
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ResultScreen(result: result)),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // CAMERA FRAME CALLBACK
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _onCameraFrame(CameraImage image) async {
    if (!_isEvaluationStarted) return;

    _totalFrames++;
    _updateFpsCounter();

    // ── SATU FRAME PADA SATU WAKTU — drop jika masih processing ─────
    if (_isProcessingFrame) {
      _droppedFrames++;
      return;
    }

    // ── Throttling adaptif: target ~10fps ────────────────────────────
    final now = DateTime.now();
    if (_lastProcessedTime != null &&
        now.difference(_lastProcessedTime!) < _targetInterval) {
      _droppedFrames++;
      return;
    }

    _lastProcessedTime = now;
    _isProcessingFrame = true;

    try {
      // ── Dapatkan sensorOrientation dari kamera aktif ─────────────
      final camera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      // ── Proses via PoseDetectorService ───────────────────────────
      final Map<PoseLandmarkType, PoseLandmark>? landmarks = await _poseService
          .processCameraImage(image, camera.sensorOrientation);

      _processedFrames++;

      // ── Update stats UI ──────────────────────────────────────────
      if (mounted) {
        setState(() {
          if (landmarks != null && landmarks.isNotEmpty) {
            _currentState = 'Pose Terdeteksi! (${landmarks.length} pts)';
          } else {
            _currentState = 'Tubuh tidak terlihat';
          }
        });
      }

      // ── Ekstrak 4 landmark utama dan kirim ke backend ────────────
      Map<String, Map<String, dynamic>>? extracted;
      if (landmarks != null && landmarks.isNotEmpty) {
        extracted = _extractKeyLandmarks(landmarks);
        if (extracted != null) {
          _trainingService.sendFrameData(extracted);
        }
      }

      // ── Akumulasi ke logger (1 sample per window) ─────────────────
      _logger.accumulateFrame(
        processed: true,
        dropped: false,
        infMs: _poseService.lastProcessingMs,
        sampleLandmarks: extracted,
      );
    } catch (e) {
      debugPrint('[TrainingScreen] ❌ Error proses frame: $e');
    } finally {
      _isProcessingFrame = false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // LANDMARK EXTRACTION + VALIDATION
  // ─────────────────────────────────────────────────────────────────────

  /// Ekstrak 4 landmark utama.
  /// Mengembalikan null jika ada landmark yang tidak valid
  /// (semua koordinat nol atau confidence < 50%).
  Map<String, Map<String, dynamic>>? _extractKeyLandmarks(
    Map<PoseLandmarkType, PoseLandmark> landmarks,
  ) {
    final shoulder = landmarks[PoseLandmarkType.rightShoulder];
    final elbow = landmarks[PoseLandmarkType.rightElbow];
    final wrist = landmarks[PoseLandmarkType.rightWrist];
    final hip = landmarks[PoseLandmarkType.rightHip];

    // Semua 4 landmark wajib ada
    if (shoulder == null || elbow == null || wrist == null || hip == null) {
      debugPrint('[TrainingScreen] ⚠️ Landmark utama tidak lengkap');
      return null;
    }

    final extracted = {
      'shoulder': _toMap(shoulder),
      'elbow': _toMap(elbow),
      'wrist': _toMap(wrist),
      'hip': _toMap(hip),
    };

    // Validasi: tidak semua titik boleh nol
    final allZero = extracted.values.every(
      (p) => p['x'] == 0.0 && p['y'] == 0.0 && p['z'] == 0.0,
    );
    if (allZero) return null;

    // Validasi: confidence minimal 50%
    final hasLowConfidence = extracted.values.any(
      (p) => (p['visibility'] as double) < 0.5,
    );
    if (hasLowConfidence) {
      if (mounted) setState(() => _currentState = 'Akurasi pose rendah...');
      return null;
    }

    return extracted;
  }

  Map<String, dynamic> _toMap(PoseLandmark lm) => {
    'x': lm.x,
    'y': lm.y,
    'z': lm.z,
    'visibility': lm.likelihood,
  };

  // ─────────────────────────────────────────────────────────────────────
  // FPS MONITOR
  // ─────────────────────────────────────────────────────────────────────

  void _updateFpsCounter() {
    final elapsed = DateTime.now().difference(_fpsWindowStart);
    if (elapsed.inMilliseconds >= 1000) {
      final double secs = elapsed.inMilliseconds / 1000.0;
      setState(() {
        _currentFps = _totalFrames / secs;
        _processedFps = _processedFrames / secs;
        // Reset window
        _totalFrames = 0;
        _processedFrames = 0;
        _fpsWindowStart = DateTime.now();
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.exerciseType.displayName.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$_reps / ${widget.targetReps} reps',
              style: const TextStyle(
                color: AppTheme.accentLime,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [Expanded(child: _buildCameraView()), _buildControlPanel()],
        ),
      ),
    );
  }

  Widget _buildCameraView() {
    if (!_isCameraInitialized || _controller == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppTheme.primaryBlue),
            SizedBox(height: AppTheme.spacing16),
            Text(
              'Initializing Camera...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_controller!),

        // FPS Monitor overlay (kiri atas)
        Positioned(
          top: 12,
          left: 12,
          child: _FpsOverlay(
            cameraFps: _currentFps,
            processedFps: _processedFps,
            dropped: _droppedFrames,
            poseDropped: _poseService.droppedFrames,
            lastMs: _poseService.lastProcessingMs,
          ),
        ),

        // Status bar (bawah)
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: _StatusBadge(
              feedback: _currentFeedback,
              state: _currentState,
              connection: _connectionStatus,
              reps: _reps,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlPanel() {
    final panelBg = const Color(0xFF0D1117); // Very dark, matches camera feel
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacing24,
        AppTheme.spacing16,
        AppTheme.spacing24,
        AppTheme.spacing20,
      ),
      decoration: BoxDecoration(
        color: panelBg,
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: AppTheme.error,
                elevation: 0,
                side: const BorderSide(color: AppTheme.error, width: 1.5),
                minimumSize: const Size(double.infinity, AppTheme.buttonHeight),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius16),
                ),
              ),
              onPressed: () async {
                await _stopEvaluation();
                if (mounted && Navigator.canPop(context)) Navigator.pop(context);
              },
              icon: const Icon(Icons.stop_circle_outlined, size: AppTheme.iconLg),
              label: const Text(
                'Finish',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacing16),
          Expanded(
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isEvaluationStarted ? const Color(0xFF1E293B) : AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    _isEvaluationStarted
                        ? const Color(0xFF1E293B)
                        : AppTheme.primaryBlue.withValues(alpha: 0.6),
                disabledForegroundColor: Colors.white70,
                elevation: 0,
                minimumSize: const Size(double.infinity, AppTheme.buttonHeight),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radius16),
                ),
              ),
              onPressed:
                  _isCameraInitialized && !_isEvaluationStarted
                      ? _startEvaluation
                      : null,
              icon: const Icon(Icons.play_circle_fill_rounded, size: AppTheme.iconLg),
              label: Text(
                _isEvaluationStarted ? 'In Progress...' : 'Start',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _FpsOverlay extends StatelessWidget {
  final double cameraFps;
  final double processedFps;
  final int dropped;
  final int poseDropped;
  final double lastMs;

  const _FpsOverlay({
    required this.cameraFps,
    required this.processedFps,
    required this.dropped,
    required this.poseDropped,
    required this.lastMs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing12,
        vertical: AppTheme.spacing8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppTheme.radius8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: AppTheme.accentLime,
          fontSize: 10,
          fontFamily: 'monospace',
          letterSpacing: 0.5,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CAM  ${cameraFps.toStringAsFixed(1)} fps'),
            Text('POSE ${processedFps.toStringAsFixed(1)} fps'),
            Text('DROP ${dropped + poseDropped}'),
            Text('INF  ${lastMs.toStringAsFixed(0)} ms'),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String feedback;
  final String state;
  final String connection;
  final int reps;

  const _StatusBadge({
    required this.feedback,
    required this.state,
    required this.connection,
    required this.reps,
  });

  @override
  Widget build(BuildContext context) {
    // Determine form quality from feedback string (without emoji dependency)
    final feedbackLower = feedback.toLowerCase();
    final bool isGoodForm = feedbackLower.contains('good') ||
        feedbackLower.contains('correct') ||
        feedbackLower.contains('🟢');
    final bool isBadForm = feedbackLower.contains('bad') ||
        feedbackLower.contains('incorrect') ||
        feedbackLower.contains('🔴');

    Color badgeColor;
    IconData formIcon;
    if (isGoodForm) {
      badgeColor = AppTheme.success.withValues(alpha: 0.92);
      formIcon = Icons.check_circle_rounded;
    } else if (isBadForm) {
      badgeColor = AppTheme.error.withValues(alpha: 0.92);
      formIcon = Icons.cancel_rounded;
    } else {
      badgeColor = Colors.black.withValues(alpha: 0.75);
      formIcon = Icons.radio_button_unchecked;
    }

    // Clean feedback text — remove emoji for professional display
    final cleanFeedback = feedback
        .replaceAll('🟢', '')
        .replaceAll('🔴', '')
        .trim();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppTheme.spacing16),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacing24,
        vertical: AppTheme.spacing16,
      ),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(AppTheme.radius20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(formIcon, color: Colors.white, size: AppTheme.iconLg),
          const SizedBox(width: AppTheme.spacing12),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cleanFeedback.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
              if (reps > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Reps: $reps',
                  style: const TextStyle(
                    color: AppTheme.accentLime,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              if (connection.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  connection,
                  style: TextStyle(
                    color: connection.contains('✓')
                        ? AppTheme.accentLime
                        : AppTheme.warning,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

