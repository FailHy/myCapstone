import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Service untuk menulis log sesi latihan ke file.
///
/// File disimpan di: <Documents>/reports/log_training_<timestamp>.txt
///
/// Strategi logging:
/// • Event utama (MULAI, CONNECT, EVAL_START, dll) → tulis langsung
/// • Per-frame   → dikumpulkan dalam window 5 detik, lalu tulis ringkasan
class TrainingLogger {
  IOSink?  _sink;
  File?    _logFile;
  bool     _isOpen = false;

  // ── Frame summary buffer ──────────────────────────────────────────
  int      _windowTotal     = 0;
  int      _windowProcessed = 0;
  int      _windowDropped   = 0;
  double   _windowInfMsSum  = 0;
  int      _windowInfCount  = 0;
  Map<String, Map<String, dynamic>>? _lastSampleLandmarks;

  DateTime _windowStart    = DateTime.now();
  static const Duration _windowSize = Duration(seconds: 5);

  Timer? _flushTimer;

  String? get logFilePath => _logFile?.path;

  // ──────────────────────────────────────────────────────────────────
  // OPEN / CLOSE
  // ──────────────────────────────────────────────────────────────────

  /// Buka file log baru. Panggil saat sesi dimulai.
  Future<void> open() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final reportsDir = Directory('${dir.path}/reports');
      if (!reportsDir.existsSync()) reportsDir.createSync(recursive: true);

      final ts = _timestamp().replaceAll(':', '-').replaceAll(' ', '_');
      _logFile = File('${reportsDir.path}/log_training_$ts.txt');
      _sink    = _logFile!.openWrite(mode: FileMode.write);
      _isOpen  = true;

      // Header
      _writeLine('=' * 60);
      _writeLine('BiTri AI — Training Session Log');
      _writeLine('File    : ${_logFile!.path}');
      _writeLine('Dibuat  : ${_timestamp()}');
      _writeLine('=' * 60);

      // Timer flush summary tiap 5 detik
      _windowStart = DateTime.now();
      _flushTimer  = Timer.periodic(_windowSize, (_) => _flushFrameSummary());

      debugPrint('[Logger] 📝 Log dibuka: ${_logFile!.path}');
    } catch (e) {
      debugPrint('[Logger] ❌ Gagal membuka log: $e');
    }
  }

  /// Tutup file log. Panggil saat sesi selesai.
  Future<void> close() async {
    if (!_isOpen) return;
    _flushTimer?.cancel();
    _flushFrameSummary(isFinal: true);
    _writeLine('=' * 60);
    _writeLine('[SESSION END]  ${_timestamp()}');
    _writeLine('=' * 60);
    await _sink?.flush();
    await _sink?.close();
    _isOpen = false;
    debugPrint('[Logger] 📝 Log ditutup: ${_logFile?.path}');
  }

  // ──────────────────────────────────────────────────────────────────
  // EVENT LOGGING  (tulis langsung)
  // ──────────────────────────────────────────────────────────────────

  void logSessionStart({
    required String userId,
    required String exerciseType,
  }) {
    _write('SESSION START');
    _writeLine('  userId       = $userId');
    _writeLine('  exerciseType = $exerciseType');
    _writeLine('  timestamp    = ${_timestamp()}');
    _separator();
  }

  void logCameraInit({
    required int width,
    required int height,
    required int sensorOrientation,
    required String resolution,
    required String formatGroup,
  }) {
    _write('CAMERA INIT');
    _writeLine('  resolusi          = ${width}x$height ($resolution)');
    _writeLine('  sensorOrientation = $sensorOrientation°');
    _writeLine('  imageFormatGroup  = $formatGroup');
    _separator();
  }

  void logWebSocketConnect({required String url, required String sessionId}) {
    _write('WS CONNECT');
    _writeLine('  url       = $url');
    _writeLine('  sessionId = $sessionId');
    _separator();
  }

  void logEvalStart() {
    _write('EVAL START — Image stream dimulai');
    _writeLine('  waktu = ${_timestamp()}');
    _separator();
  }

  void logBackendResponse(Map<String, dynamic> result) {
    _write('BACKEND RESPONSE');
    _writeLine('  feedback = ${result['feedback']}');
    _writeLine('  state    = ${result['state']}');
    _writeLine('  reps     = ${result['reps']}');
  }

  void logWebSocketError(String error) {
    _write('WS ERROR');
    _writeLine('  $error');
  }

  void logWebSocketDisconnect({required int sent, required int dropped}) {
    _write('WS DISCONNECT');
    _writeLine('  frames_sent    = $sent');
    _writeLine('  frames_dropped = $dropped');
    _separator();
  }

  void logEvalStop({
    required Duration duration,
    required int totalFrames,
    required int processedFrames,
    required int reps,
  }) {
    _separator();
    _write('EVAL STOP');
    _writeLine('  durasi          = ${duration.inSeconds}s');
    _writeLine('  total_frames    = $totalFrames');
    _writeLine('  processed       = $processedFrames');
    _writeLine('  reps_akhir      = $reps');
    _writeLine('  waktu           = ${_timestamp()}');
    _separator();
  }

  // ──────────────────────────────────────────────────────────────────
  // FRAME ACCUMULATOR  (tulis ringkasan tiap 5 detik)
  // ──────────────────────────────────────────────────────────────────

  /// Panggil setiap frame kamera masuk.
  void accumulateFrame({
    required bool processed,
    required bool dropped,
    double infMs = 0,
    Map<String, Map<String, dynamic>>? sampleLandmarks,
  }) {
    _windowTotal++;
    if (processed) {
      _windowProcessed++;
      _windowInfMsSum  += infMs;
      _windowInfCount++;
      if (sampleLandmarks != null) _lastSampleLandmarks = sampleLandmarks;
    }
    if (dropped) _windowDropped++;
  }

  void _flushFrameSummary({bool isFinal = false}) {
    if (_windowTotal == 0) return;

    final elapsed = DateTime.now().difference(_windowStart).inSeconds;
    final label   = isFinal ? 'FRAME SUMMARY (final)' : 'FRAME SUMMARY (${elapsed}s window)';
    final avgFps  = _windowTotal     / (elapsed == 0 ? 1 : elapsed);
    final avgInf  = _windowInfCount  > 0
        ? (_windowInfMsSum / _windowInfCount).toStringAsFixed(1)
        : '-';

    _write(label);
    _writeLine('  total     = $_windowTotal frames');
    _writeLine('  processed = $_windowProcessed frames');
    _writeLine('  dropped   = $_windowDropped frames');
    _writeLine('  avg FPS   = ${avgFps.toStringAsFixed(1)}');
    _writeLine('  avg inf   = ${avgInf}ms');

    // Satu contoh frame landmark
    if (_lastSampleLandmarks != null) {
      _writeLine('  [SAMPLE LANDMARK]');
      _lastSampleLandmarks!.forEach((key, val) {
        final x    = (val['x']    as double).toStringAsFixed(3);
        final y    = (val['y']    as double).toStringAsFixed(3);
        final conf = (val['visibility'] as double).toStringAsFixed(2);
        _writeLine('    $key → x=$x y=$y conf=$conf');
      });
    }

    // Reset window
    _windowTotal     = 0;
    _windowProcessed = 0;
    _windowDropped   = 0;
    _windowInfMsSum  = 0;
    _windowInfCount  = 0;
    _lastSampleLandmarks = null;
    _windowStart     = DateTime.now();
  }

  // ──────────────────────────────────────────────────────────────────
  // INTERNAL HELPERS
  // ──────────────────────────────────────────────────────────────────

  void _write(String tag) {
    _writeLine('\n[${_timestamp()}] [$tag]');
  }

  void _writeLine(String line) {
    if (!_isOpen || _sink == null) return;
    try {
      _sink!.writeln(line);
    } catch (e) {
      debugPrint('[Logger] ⚠️ Tulis gagal: $e');
    }
  }

  void _separator() => _writeLine('-' * 40);

  String _timestamp() {
    final now = DateTime.now();
    return '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }
}
