import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

class AuthProvider extends ChangeNotifier {
  final ApiClient _apiClient = ApiClient();
  
  bool _isLoading = false;
  bool _isAuthenticated = false;
  String _errorMessage = '';

  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;
  String get errorMessage => _errorMessage;

  // Mengecek sesi login yang tersimpan saat aplikasi pertama kali dibuka
  Future<void> checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');
    
    if (token != null && token.isNotEmpty) {
      _isAuthenticated = true;
    } else {
      _isAuthenticated = false;
    }
    notifyListeners();
  }

  // Logika eksekusi Login
  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    try {
      // Sesuaikan URL ini dengan endpoint auth di FastAPI Anda
      final response = await _apiClient.dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      if (response.statusCode == 200) {
        // Asumsi respons dari backend: {"access_token": "eyJhb..."}
        final token = response.data['access_token'];
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', token);

        _isAuthenticated = true;
        _isLoading = false;
        notifyListeners();
        return true;
      }
    } on DioException catch (e) {
      _errorMessage = e.response?.data['detail'] ?? 'Koneksi ke server gagal.';
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
    _isAuthenticated = false;
    notifyListeners();
  }
}