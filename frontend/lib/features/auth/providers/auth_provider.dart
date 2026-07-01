import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

class AuthProvider extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();

  bool _isLoading = false;
  bool _isAuthenticated = false;
  String _errorMessage = '';

  // Variabel untuk menyimpan profil dinamis
  String _userName = '';
  String _userEmail = '';
  String _userId = ''; // Ditambahkan: ID user dari database

  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String get errorMessage => _errorMessage;

  // Getter untuk UI & service lain
  String get userName => _userName;
  String get userEmail => _userEmail;
  String get userId => _userId; // Getter baru

  // Mengecek sesi login yang tersimpan
  Future<void> checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    final savedId = prefs.getString('user_id') ?? '';

    if (token != null && token.isNotEmpty) {
      _isAuthenticated = true;
      _userId = savedId; // Pulihkan userId dari penyimpanan lokal
    } else {
      _isAuthenticated = false;
    }
    notifyListeners();
  }

  // --- LOGIKA MENGAMBIL PROFIL PENGGUNA (BARU) ---
  Future<void> fetchProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      if (token == null || token.isEmpty) return;

      // Memanggil endpoint /auth/me dengan menyisipkan Token di Header
      final response = await _apiClient.dio.get(
        '/auth/me',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        // Simpan profil + userId ke state
        _userName = response.data['name'] ?? 'Pengguna';
        _userEmail = response.data['email'] ?? '';
        // Backend mengembalikan 'id' atau 'user_id' — sesuaikan jika berbeda
        _userId =
            response.data['id']?.toString() ??
            response.data['user_id']?.toString() ??
            '';

        // Simpan userId ke SharedPreferences agar tersedia setelah restart
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_id', _userId);

        notifyListeners();
      }
    } catch (e) {
      print('Gagal mengambil data profil: $e');
      // Opsional: Jika backend merespons 401 (Token Kadaluarsa), Anda bisa panggil logout()
    }
  }

  // Logika eksekusi Login
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final response = await _apiClient.dio.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );

      if (response.statusCode == 200) {
        final token = response.data['access_token'];

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', token);

        _isAuthenticated = true;
        _isLoading = false;
        notifyListeners();

        // Fetch profil segera agar userId tersedia sebelum training
        await fetchProfile();
        return true;
      }
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null) {
        final detail = e.response!.data['detail'];
        if (detail is List && detail.isNotEmpty) {
          _errorMessage = detail[0]['msg'] ?? 'Input tidak valid.';
        } else if (detail is String) {
          _errorMessage = detail;
        } else {
          _errorMessage = 'Terjadi kesalahan server.';
        }
      } else {
        _errorMessage = 'Ganti IP di Fluter';
      }
    } catch (e) {
      _errorMessage = 'Terjadi kesalahan internal.';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Logika eksekusi Registrasi
  Future<bool> register(String name, String email, String password) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      final response = await _apiClient.dio.post(
        '/auth/register',
        data: {'name': name, 'email': email, 'password': password},
      );

      if (response.statusCode == 201) {
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null) {
        final detail = e.response!.data['detail'];
        if (detail is List && detail.isNotEmpty) {
          _errorMessage = detail[0]['msg'] ?? 'Input tidak valid.';
        } else if (detail is String) {
          _errorMessage = detail;
        } else {
          _errorMessage = 'Terjadi kesalahan pada server.';
        }
      } else {
        _errorMessage = 'Ganti IP di Flutter';
      }
    } catch (e) {
      _errorMessage = 'Terjadi kesalahan internal.';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Logika eksekusi Logout
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('user_id'); // Bersihkan userId juga
    _isAuthenticated = false;

    // Bersihkan semua data profil
    _userName = '';
    _userEmail = '';
    _userId = '';

    notifyListeners();
  }
}
