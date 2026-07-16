import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../features/auth/providers/auth_provider.dart';
import '../core/api/api_client.dart';
import '../theme.dart';
import '../widgets/custom_widgets.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    final userId = context.read<AuthProvider>().userId;
    if (userId.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'User ID tidak ditemukan. Silakan login ulang.';
      });
      return;
    }

    setState(() {
      _error = null;
    });

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
            _error = 'Failed to load history (${response.statusCode})';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Connection failed: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLightGrey,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Training History',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        iconTheme: const IconThemeData(color: AppTheme.textDark),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textDark),
            onPressed: () {
              setState(() {
                _isLoading = true;
                _error = null;
              });
              _fetchHistory();
            },
          ),
          const SizedBox(width: AppTheme.spacing8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.primaryBlue),
      );
    }

    if (_error != null) {
      return EmptyStateWidget(
        icon: Icons.cloud_off_rounded,
        title: 'Unable to Load History',
        subtitle: _error!,
        buttonLabel: 'Try Again',
        onButton: _fetchHistory,
      );
    }

    if (_sessions.isEmpty) {
      return const EmptyStateWidget(
        icon: Icons.fitness_center_outlined,
        title: 'No Training History',
        subtitle: 'Complete your first session to see it here.',
      );
    }

    // Group sessions by date
    final grouped = _groupByDate(_sessions);

    return RefreshIndicator(
      onRefresh: _fetchHistory,
      color: AppTheme.primaryBlue,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppTheme.spacing16),
        itemCount: grouped.length,
        itemBuilder: (context, index) {
          final date = grouped.keys.elementAt(index);
          final items = grouped[date]!;
          return _buildDateGroup(context, date, items);
        },
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupByDate(
    List<Map<String, dynamic>> sessions,
  ) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final s in sessions) {
      final raw = s['created_at'] as String?;
      final key = raw != null ? raw.split('T')[0] : 'Unknown';
      map.putIfAbsent(key, () => []).add(s);
    }
    return map;
  }

  Widget _buildDateGroup(
    BuildContext context,
    String dateKey,
    List<Map<String, dynamic>> items,
  ) {
    String displayDate = dateKey;
    try {
      final dt = DateTime.parse(dateKey);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final d = DateTime(dt.year, dt.month, dt.day);
      if (d == today) {
        displayDate = 'Today';
      } else if (d == yesterday) {
        displayDate = 'Yesterday';
      } else {
        displayDate = '${dt.day} ${_monthName(dt.month)} ${dt.year}';
      }
    } catch (_) {}

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: AppTheme.spacing8,
            bottom: AppTheme.spacing12,
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 16,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: AppTheme.spacing8),
              Text(
                displayDate,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(width: AppTheme.spacing8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacing8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.bgSoftBlue,
                  borderRadius: BorderRadius.circular(AppTheme.radius8),
                ),
                child: Text(
                  '${items.length} session${items.length > 1 ? 's' : ''}',
                  style: const TextStyle(
                    color: AppTheme.primaryBlue,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...items.map((s) => _SessionCard(session: s)),
        const SizedBox(height: AppTheme.spacing12),
      ],
    );
  }

  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return months[month - 1];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SESSION CARD
// ─────────────────────────────────────────────────────────────────────────────

class _SessionCard extends StatelessWidget {
  final Map<String, dynamic> session;

  const _SessionCard({required this.session});

  Color _gradeColor(double accuracy) {
    if (accuracy >= 85) return AppTheme.success;
    if (accuracy >= 65) return AppTheme.primaryBlue;
    if (accuracy >= 45) return AppTheme.warning;
    return AppTheme.error;
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  String _exerciseAsset(String type) {
    return type.toLowerCase().contains('bicep')
        ? 'assets/images/Biceps icon.png'
        : 'assets/images/Triceps icon.png';
  }

  @override
  Widget build(BuildContext context) {
    final double accuracy =
        (session['accuracy'] as num?)?.toDouble() ?? 0.0;
    final int totalReps = (session['total_reps'] as num?)?.toInt() ?? 0;
    final int correctReps = (session['correct_reps'] as num?)?.toInt() ?? 0;
    final String type = session['exercise_type'] ?? '-';
    final color = _gradeColor(accuracy);
    final time = _formatTime(session['created_at'] as String?);

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing12),
      decoration: AppTheme.cardDecoration(shadowColor: color),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacing16),
        child: Row(
          children: [
            // Exercise icon container
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppTheme.radius12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(6.0),
                child: Image.asset(
                  _exerciseAsset(type),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.fitness_center_rounded,
                    color: color,
                    size: 24,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacing16),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          type.toUpperCase(),
                          style: Theme.of(context).textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (time.isNotEmpty)
                        Text(
                          time,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacing4),
                  Text(
                    '$totalReps reps  ·  $correctReps correct  ·  ${totalReps - correctReps} incorrect',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textGrey,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing8),
                  // Mini progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: accuracy / 100,
                      minHeight: 4,
                      backgroundColor: color.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppTheme.spacing12),

            // Grade badge
            GradeBadge(accuracy: accuracy),
          ],
        ),
      ),
    );
  }
}
