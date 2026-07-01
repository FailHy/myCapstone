import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/auth/providers/auth_provider.dart';
import 'history_screen.dart';
import '../core/api/api_client.dart';

class ProfileScreen extends StatefulWidget {
  final bool isActive;
  const ProfileScreen({super.key, this.isActive = true});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    context.read<AuthProvider>().fetchProfile();
    _fetchHistory();
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      context.read<AuthProvider>().fetchProfile();
      _fetchHistory();
    }
  }

  Future<void> _fetchHistory() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'User ID tidak ditemukan.';
      });
      return;
    }
    try {
      final response = await ApiClient().dio.get('/history/$userId');
      if (response.statusCode == 200) {
        final data = response.data as List<dynamic>;
        setState(() {
          _sessions = data.cast<Map<String, dynamic>>();
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Gagal memuat riwayat';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Koneksi gagal';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          return SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                await context.read<AuthProvider>().fetchProfile();
                await _fetchHistory();
              },
              color: Colors.blueAccent,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor: Colors.blueAccent,
                            child: Text(
                              authProvider.userName.isNotEmpty
                                  ? authProvider.userName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 40,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            authProvider.userName.isEmpty
                                ? 'Memuat...'
                                : authProvider.userName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            authProvider.userEmail.isEmpty
                                ? ''
                                : authProvider.userEmail,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (!_isLoading && _sessions.isNotEmpty)
                            Text(
                              '${_sessions.map((s) => s['created_at']?.split('T')[0]).toSet().length} Days',
                              style: const TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 16),
                    const Text(
                      'Training History',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isLoading)
                      const Center(
                        child: CircularProgressIndicator(
                          color: Colors.blueAccent,
                        ),
                      )
                    else if (_error != null)
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      )
                    else if (_sessions.isEmpty)
                      const Text(
                        'Belum ada riwayat.',
                        style: TextStyle(color: Colors.white54),
                      )
                    else
                      Column(
                        children: [
                          ..._sessions
                              .take(3)
                              .map((session) => _buildHistoryItem(session)),
                          if (_sessions.length > 3)
                            TextButton(
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const HistoryScreen(),
                                ),
                              ),
                              child: const Text(
                                'Lihat Semua',
                                style: TextStyle(color: Colors.blueAccent),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 24),
                    const Divider(color: Colors.white24),
                    const SizedBox(height: 12),
                    // Tombol Logout
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.redAccent),
                      title: const Text(
                        'Logout',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: Colors.redAccent,
                      ),
                      onTap: () async {
                        await authProvider.logout();
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> session) {
    final accuracy = (session['accuracy'] as num?)?.toDouble() ?? 0.0;
    final totalReps = (session['total_reps'] as num?)?.toInt() ?? 0;
    final correctReps = (session['correct_reps'] as num?)?.toInt() ?? 0;
    final type = session['exercise_type'] ?? '-';
    final date = session['created_at'] as String?;
    final color =
        accuracy >= 85
            ? Colors.greenAccent
            : accuracy >= 65
            ? Colors.lightBlueAccent
            : Colors.orangeAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '$totalReps reps · $correctReps benar',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                if (date != null)
                  Text(
                    date.split('T')[0],
                    style: const TextStyle(color: Colors.white30, fontSize: 11),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${accuracy.toStringAsFixed(0)}%',
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}