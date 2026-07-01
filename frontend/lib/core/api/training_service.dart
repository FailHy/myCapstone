// frontend/lib/core/api/training_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;

class TrainingService {
  WebSocketChannel? _channel;
  String? _currentSessionId;

  static String get _httpBaseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000';
    // jangan lupa gnti terus selagi belum ke server
    if (Platform.isAndroid) return 'http://10.20.27.224:8000';
    return 'http://127.0.0.1:8000';
  }

  static String get _wsBaseUrl {
    if (kIsWeb) return 'ws://127.0.0.1:8000/ws';
    if (Platform.isAndroid) return 'ws://10.20.27.224:8000/ws';
    return 'ws://127.0.0.1:8000/ws';
  }

  final Function(Map<String, dynamic> result) onEvaluationReceived;
  final Function(String error) onError;

  TrainingService({required this.onEvaluationReceived, required this.onError});

  /// 1. HTTP POST: Meminta Session ID baru
  Future<bool> startSession({
    required String userId,
    required String exerciseType,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_httpBaseUrl/session/start'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': userId, 'exercise_type': exerciseType}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _currentSessionId = data['session_id'];
        _connectWebSocket(_currentSessionId!);
        return true;
      } else {
        onError('Gagal membuat sesi: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      onError('Error network saat start session: $e');
      return false;
    }
  }

  /// 2. Menghubungkan ke WebSocket menggunakan Session ID
  void _connectWebSocket(String sessionId) {
    final wsUri = Uri.parse('$_wsBaseUrl/$sessionId');
    _channel = WebSocketChannel.connect(wsUri);

    _channel!.stream.listen(
      (message) {
        try {
          final decoded = jsonDecode(message as String);
          if (decoded is Map<String, dynamic>) {
            if (decoded.containsKey('error')) {
              onError(decoded['error'].toString());
            } else {
              onEvaluationReceived(decoded);
            }
          }
        } catch (e) {
          debugPrint('[TrainingService] decode error: $e');
        }
      },
      onError: (error) => onError('WebSocket Error: $error'),
      onDone: () => debugPrint('[TrainingService] WebSocket closed.'),
    );
  }

  /// 3. Mengirim data landmark ke backend
  void sendFrameData(Map<String, Map<String, dynamic>> extractedLandmarks) {
    if (_channel != null && _currentSessionId != null) {
      final payload = {
        'session_id': _currentSessionId,
        'timestamp': DateTime.now().millisecondsSinceEpoch / 1000,
        'landmarks': extractedLandmarks,
      };
      _channel!.sink.add(jsonEncode(payload));
    }
  }

  /// 4. Akhiri sesi: kirim POST /session/end dan dapatkan hasil latihan
  Future<Map<String, dynamic>?> endSession() async {
    final sessionId = _currentSessionId;
    if (sessionId == null) {
      _channel?.sink.close();
      return null;
    }

    Map<String, dynamic>? result;
    try {
      final response = await http.post(
        Uri.parse('$_httpBaseUrl/session/end'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'session_id': sessionId}),
      );
      if (response.statusCode == 200) {
        result = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint('[TrainingService] Session ended: $result');
      } else {
        debugPrint(
          '[TrainingService] session/end error: ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('[TrainingService] endSession error: $e');
    }

    _channel?.sink.close();
    _currentSessionId = null;
    return result;
  }

  /// 5. Tutup koneksi tanpa memanggil API (fallback)
  void dispose() {
    _channel?.sink.close();
    _currentSessionId = null;
  }
}
