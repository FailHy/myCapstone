import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:frontend/features/auth/providers/auth_provider.dart';
import 'history_screen.dart';
import '../core/api/api_client.dart';
import '../theme.dart';
import '../widgets/custom_widgets.dart';

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
    _initData();
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _initData();
    }
  }

  Future<void> _initData() async {
    final authProvider = context.read<AuthProvider>();
    // Pastikan data profil dan userId sudah terambil terlebih dahulu dari server
    await authProvider.fetchProfile();
    if (!mounted) return;
    await _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    final authProvider = context.read<AuthProvider>();
    String userId = authProvider.userId;

    // Jika userId masih kosong, tunggu proses fetchProfile() selesai terlebih dahulu
    if (userId.isEmpty) {
      await authProvider.fetchProfile();
      if (!mounted) return;
      userId = authProvider.userId;
    }

    if (userId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'User ID tidak ditemukan.';
        });
      }
      return;
    }

    if (mounted && (_error != null || _isLoading)) {
      setState(() {
        _error = null;
      });
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final response = await ApiClient().dio.get('/history/$userId?t=$timestamp');
      if (response.statusCode == 200) {
        final data = response.data as List<dynamic>;
        if (mounted) {
          setState(() {
            _sessions = data.cast<Map<String, dynamic>>();
            _isLoading = false;
            _error = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = 'Gagal memuat riwayat';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Koneksi gagal';
          _isLoading = false;
        });
      }
    }
  }

  // ── Computed Stats ─────────────────────────────────────────────────────────

  int get _totalSessions => _sessions.length;

  double get _avgAccuracy {
    if (_sessions.isEmpty) return 0;
    final total = _sessions.fold<double>(
      0,
      (sum, s) => sum + ((s['accuracy'] as num?)?.toDouble() ?? 0.0),
    );
    return total / _sessions.length;
  }

  int get _totalReps {
    return _sessions.fold<int>(
      0,
      (sum, s) => sum + ((s['total_reps'] as num?)?.toInt() ?? 0),
    );
  }

  int get _activeDays =>
      _sessions.map((s) => s['created_at']?.split('T')[0]).toSet().length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLightGrey,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Profile',
          style: Theme.of(context).textTheme.titleLarge,
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
              color: AppTheme.primaryBlue,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppTheme.spacing24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Avatar & Name Section ─────────────────────────
                    _buildProfileHeader(context, authProvider),
                    const SizedBox(height: AppTheme.spacing24),

                    // ── Stats Cards ───────────────────────────────────
                    if (!_isLoading && _sessions.isNotEmpty) ...[
                      Text(
                        'Training Stats',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppTheme.spacing12),
                      _buildStatsGrid(context),
                      const SizedBox(height: AppTheme.spacing24),
                    ],

                    // ── Recent Activities ─────────────────────────────
                    const SectionHeader(
                      title: 'Recent Activities',
                    ),
                    const SizedBox(height: AppTheme.spacing12),
                    _buildActivitySection(context),
                    const SizedBox(height: AppTheme.spacing24),

                    // ── Divider ───────────────────────────────────────
                    const Divider(color: AppTheme.dividerColor),
                    const SizedBox(height: AppTheme.spacing12),

                    // ── Logout ────────────────────────────────────────
                    _buildLogoutTile(authProvider),
                    const SizedBox(height: AppTheme.spacing16),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(
    BuildContext context,
    AuthProvider authProvider,
  ) {
    final name = authProvider.userName.isNotEmpty
        ? authProvider.userName
        : 'Loading...';
    final email = authProvider.userEmail;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacing24),
      decoration: AppTheme.cardDecoration(),
      child: Column(
        children: [
          // Avatar with gradient background
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryBlue, AppTheme.secondaryBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  fontSize: 32,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacing16),
          Text(
            name,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing4),
            Text(
              email,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (!_isLoading && _sessions.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacing12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacing16,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: AppTheme.successLight,
                borderRadius: BorderRadius.circular(AppTheme.radius12),
              ),
              child: Text(
                '$_activeDays Days Active',
                style: const TextStyle(
                  color: AppTheme.success,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsGrid(BuildContext context) {
    // Menggunakan Column + Row agar tidak bergantung pada childAspectRatio
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Total Sessions',
                value: '$_totalSessions',
                icon: Icons.calendar_today_outlined,
                color: AppTheme.primaryBlue,
              ),
            ),
            const SizedBox(width: AppTheme.spacing12),
            Expanded(
              child: StatCard(
                label: 'Avg. Accuracy',
                value: '${_avgAccuracy.toStringAsFixed(0)}%',
                icon: Icons.analytics_outlined,
                color: _avgAccuracy >= 65 ? AppTheme.success : AppTheme.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing12),
        Row(
          children: [
            Expanded(
              child: StatCard(
                label: 'Total Reps',
                value: '$_totalReps',
                icon: Icons.repeat_rounded,
                color: AppTheme.secondaryBlue,
              ),
            ),
            const SizedBox(width: AppTheme.spacing12),
            Expanded(
              child: StatCard(
                label: 'Active Days',
                value: '$_activeDays',
                icon: Icons.local_fire_department_outlined,
                color: AppTheme.warning,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActivitySection(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppTheme.spacing24),
          child: CircularProgressIndicator(color: AppTheme.primaryBlue),
        ),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(AppTheme.spacing16),
        decoration: BoxDecoration(
          color: AppTheme.errorLight,
          borderRadius: BorderRadius.circular(AppTheme.radius12),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 20),
            const SizedBox(width: AppTheme.spacing8),
            Expanded(
              child: Text(
                _error!,
                style: const TextStyle(color: AppTheme.error, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (_sessions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppTheme.spacing24),
        decoration: AppTheme.cardDecoration(),
        child: const Row(
          children: [
            Icon(Icons.fitness_center_outlined,
                color: AppTheme.textMuted, size: 20),
            SizedBox(width: AppTheme.spacing12),
            Expanded(
              child: Text(
                'No sessions yet. Start your first training!',
                style: TextStyle(color: AppTheme.textGrey),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        ..._sessions.take(5).map((s) => _buildHistoryItem(context, s)),
        if (_sessions.length > 5) ...[
          const SizedBox(height: AppTheme.spacing8),
          _buildViewMoreButton(context),
        ],
      ],
    );
  }

  Widget _buildViewMoreButton(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HistoryScreen()),
        ),
        borderRadius: BorderRadius.circular(AppTheme.radius16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: AppTheme.spacing16,
            horizontal: AppTheme.spacing20,
          ),
          decoration: BoxDecoration(
            color: AppTheme.bgSoftBlue,
            borderRadius: BorderRadius.circular(AppTheme.radius16),
            border: Border.all(
              color: AppTheme.primaryBlue.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.history_rounded,
                color: AppTheme.primaryBlue,
                size: AppTheme.iconMd,
              ),
              const SizedBox(width: AppTheme.spacing8),
              Flexible(
                child: Text(
                  'View More History (${_sessions.length - 5} more)',
                  style: const TextStyle(
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppTheme.spacing8),
              const Icon(
                Icons.arrow_forward_rounded,
                color: AppTheme.primaryBlue,
                size: AppTheme.iconMd,
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildHistoryItem(
    BuildContext context,
    Map<String, dynamic> session,
  ) {
    final accuracy = (session['accuracy'] as num?)?.toDouble() ?? 0.0;
    final totalReps = (session['total_reps'] as num?)?.toInt() ?? 0;
    final correctReps = (session['correct_reps'] as num?)?.toInt() ?? 0;
    final type = session['exercise_type'] ?? '-';
    final date = session['created_at'] as String?;
    final color = accuracy >= 85
        ? AppTheme.success
        : accuracy >= 65
            ? AppTheme.warning
            : AppTheme.error;

    final exerciseAsset = type.toLowerCase().contains('bicep')
        ? 'assets/images/Biceps icon.png'
        : 'assets/images/Triceps icon.png';

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing8),
      padding: const EdgeInsets.all(AppTheme.spacing16),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radius12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: Image.asset(
                exerciseAsset,
                fit: BoxFit.contain,
                color: color,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.fitness_center_rounded,
                  color: color,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacing12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.toUpperCase(),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppTheme.spacing4),
                Text(
                  '$totalReps reps  ·  $correctReps correct',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (date != null) ...[
                  const SizedBox(height: AppTheme.spacing4),
                  Text(
                    date.split('T')[0],
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.textMuted),
                  ),
                ],
              ],
            ),
          ),
          GradeBadge(accuracy: accuracy),
        ],
      ),
    );
  }

  Widget _buildLogoutTile(AuthProvider authProvider) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          await authProvider.logout();
        },
        borderRadius: BorderRadius.circular(AppTheme.radius16),
        child: Container(
          padding: const EdgeInsets.all(AppTheme.spacing16),
          decoration: BoxDecoration(
            color: AppTheme.errorLight,
            borderRadius: BorderRadius.circular(AppTheme.radius16),
            border: Border.all(
              color: AppTheme.error.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppTheme.spacing8),
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppTheme.radius8),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: AppTheme.error,
                  size: AppTheme.iconMd,
                ),
              ),
              const SizedBox(width: AppTheme.spacing16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Logout',
                      style: TextStyle(
                        color: AppTheme.error,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      'Sign out of your account',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.error.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppTheme.error,
                size: AppTheme.iconLg,
              ),
            ],
          ),
        ),
      ),
    );
  }
}