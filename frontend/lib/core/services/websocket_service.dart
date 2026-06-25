import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// WebSocket client dengan:
/// • Exponential backoff reconnect (1→2→4→8s, max 8s)
/// • Heartbeat ping setiap 30 detik
/// • Validasi payload sebelum kirim
/// • Null-safe disconnect
class WebSocketService {
  WebSocketChannel?    _channel;
  StreamSubscription?  _subscription;
  Timer?               _heartbeatTimer;
  Timer?               _reconnectTimer;

  String?  _url;
  bool     _isConnected        = false;
  bool     _intentionalClose   = false; // true = user sengaja disconnect
  int      _reconnectAttempts  = 0;
  int      _sentFrames         = 0;
  int      _droppedFrames      = 0;

  static const int    _maxReconnectDelay = 8;  // detik
  static const int    _heartbeatInterval = 30; // detik

  bool get isConnected => _isConnected;
  int  get sentFrames  => _sentFrames;
  int  get droppedFrames => _droppedFrames;

  // Callback eksternal
  void Function(Map<String, dynamic>)? onMessageReceived;
  void Function(String)?               onError;
  void Function()?                     onConnected;
  void Function()?                     onDisconnected;

  // ------------------------------------------------------------------
  // CONNECT
  // ------------------------------------------------------------------

  /// Hubungkan ke [url].  Jika koneksi putus, akan auto-reconnect.
  void connect(String url) {
    _url                = url;
    _intentionalClose   = false;
    _reconnectAttempts  = 0;
    _doConnect();
  }

  void _doConnect() {
    if (_url == null) return;

    try {
      debugPrint('[WebSocket] 🔌 Menghubungkan ke $_url');
      _channel = WebSocketChannel.connect(Uri.parse(_url!));

      // Tunggu koneksi benar-benar terbuka via ready future
      _channel!.ready.then((_) {
        _isConnected       = true;
        _reconnectAttempts = 0;
        debugPrint('[WebSocket] ✅ Terhubung ke $_url');
        onConnected?.call();
        _startHeartbeat();
        _listenStream();
      }).catchError((e) {
        debugPrint('[WebSocket] ❌ Gagal handshake: $e');
        _isConnected = false;
        onError?.call('Gagal handshake: $e');
        _scheduleReconnect();
      });
    } catch (e) {
      debugPrint('[WebSocket] ❌ Exception saat connect: $e');
      _isConnected = false;
      onError?.call('Exception connect: $e');
      _scheduleReconnect();
    }
  }

  // ------------------------------------------------------------------
  // LISTEN
  // ------------------------------------------------------------------

  void _listenStream() {
    _subscription?.cancel();
    _subscription = _channel?.stream.listen(
      (message) {
        try {
          final decoded = jsonDecode(message as String);
          if (decoded is Map<String, dynamic>) {
            onMessageReceived?.call(decoded);
          }
        } catch (e) {
          debugPrint('[WebSocket] ⚠️ Gagal decode message: $e');
        }
      },
      onError: (error) {
        debugPrint('[WebSocket] ❌ Stream error: $error');
        _isConnected = false;
        onError?.call('Stream error: $error');
        _scheduleReconnect();
      },
      onDone: () {
        debugPrint('[WebSocket] 🔌 Koneksi ditutup');
        _isConnected = false;
        onDisconnected?.call();
        if (!_intentionalClose) _scheduleReconnect();
      },
      cancelOnError: false,
    );
  }

  // ------------------------------------------------------------------
  // SEND
  // ------------------------------------------------------------------

  /// Kirim data landmark yang sudah divalidasi.
  ///
  /// [landmarks] format: { "shoulder": {x,y,z,visibility}, "elbow": {...}, ... }
  /// [sessionId] ID sesi aktif.
  ///
  /// Drop frame jika:
  /// • Belum terhubung
  /// • landmarks kosong
  /// • Semua titik memiliki visibility = 0 (confidence terlalu rendah)
  void sendLandmarks({
    required Map<String, Map<String, dynamic>> landmarks,
    required String sessionId,
  }) {
    // ── Guard: koneksi ───────────────────────────────────────────────
    if (!_isConnected || _channel == null) {
      _droppedFrames++;
      debugPrint('[WebSocket] ⚠️ Drop frame — belum terhubung');
      return;
    }

    // ── Guard: landmarks tidak boleh kosong ──────────────────────────
    if (landmarks.isEmpty) {
      _droppedFrames++;
      debugPrint('[WebSocket] ⚠️ Drop frame — landmarks kosong');
      return;
    }

    // ── Guard: confidence minimum 50% untuk semua titik ─────────────
    final bool lowConfidence = landmarks.values.any(
      (p) => (p['visibility'] as double? ?? 0.0) < 0.5,
    );
    if (lowConfidence) {
      _droppedFrames++;
      debugPrint('[WebSocket] ⚠️ Drop frame — confidence rendah');
      return;
    }

    // ── Kirim payload ────────────────────────────────────────────────
    final payload = {
      'session_id': sessionId,
      'timestamp' : DateTime.now().millisecondsSinceEpoch / 1000,
      'landmarks' : landmarks,
    };

    try {
      _channel!.sink.add(jsonEncode(payload));
      _sentFrames++;
      debugPrint('[WebSocket] 📤 Frame #$_sentFrames dikirim (dropped=$_droppedFrames)');
    } catch (e) {
      debugPrint('[WebSocket] ❌ Gagal kirim: $e');
      _droppedFrames++;
    }
  }

  // ------------------------------------------------------------------
  // HEARTBEAT
  // ------------------------------------------------------------------

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: _heartbeatInterval),
      (_) {
        if (_isConnected && _channel != null) {
          try {
            _channel!.sink.add(jsonEncode({'type': 'ping'}));
            debugPrint('[WebSocket] 💓 Ping dikirim');
          } catch (e) {
            debugPrint('[WebSocket] ❌ Heartbeat gagal: $e');
          }
        }
      },
    );
  }

  // ------------------------------------------------------------------
  // RECONNECT
  // ------------------------------------------------------------------

  void _scheduleReconnect() {
    if (_intentionalClose || _url == null) return;

    final int delaySeconds =
        (1 << _reconnectAttempts).clamp(1, _maxReconnectDelay);
    _reconnectAttempts++;

    debugPrint(
      '[WebSocket] 🔄 Reconnect ke-$_reconnectAttempts dalam ${delaySeconds}s',
    );

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), _doConnect);
  }

  // ------------------------------------------------------------------
  // DISCONNECT
  // ------------------------------------------------------------------

  /// Tutup koneksi WebSocket secara bersih.
  void disconnect() {
    _intentionalClose = true;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _isConnected  = false;
    _channel      = null;
    _subscription = null;
    debugPrint(
      '[WebSocket] 🔒 Disconnected — sent=$_sentFrames dropped=$_droppedFrames',
    );
  }
}