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
    final authProvider = context.read<AuthProvider>();
    String userId = authProvider.userId;
    if (userId.isEmpty) {
      await authProvider.fetchProfile();
      if (!mounted) return;
      userId = authProvider.userId;
    }

    if (userId.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'User ID tidak ditemukan. Silakan login ulang.';
        });
      }
      return;
    }

    if (mounted) {
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

class _SessionCard extends StatefulWidget {
  final Map<String, dynamic> session;

  const _SessionCard({required this.session});

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  bool _isExpanded = false;
  bool _isLoadingDetails = false;
  String? _errorDetails;
  List<Map<String, dynamic>>? _results;

  Color _gradeColor(double accuracy) {
    if (accuracy >= 85) return AppTheme.success;
    if (accuracy >= 65) return AppTheme.warning;
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

  String _getInsight(double accuracy) {
    if (accuracy >= 85) {
      return 'Excellent movement control! Your form is highly consistent and optimized for muscle activation. Keep it up!';
    }
    if (accuracy >= 65) {
      return 'Good execution overall. Focus on achieving a fuller range of motion for even better results.';
    }
    if (accuracy >= 45) {
      return 'Reduce your speed and ensure your elbow stays stable throughout the movement.';
    }
    return 'Focus on your posture and muscle isolation. Start with lighter loads to build correct movement patterns.';
  }

  String _formatRepStatus(String status) {
    switch (status.toLowerCase()) {
      case 'correct':
        return 'Correct Form';
      case 'elbow_drift':
        return 'Elbow Drift';
      case 'body_swing':
        return 'Body Swing';
      case 'incomplete_rom':
        return 'Incomplete ROM';
      case 'invalid':
        return 'Invalid Pose';
      default:
        return status
            .split('_')
            .map((word) => word.isNotEmpty ? '${word[0].toUpperCase()}${word.substring(1)}' : '')
            .join(' ');
    }
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
    });

    if (_isExpanded && _results == null && !_isLoadingDetails) {
      _fetchSessionDetails();
    }
  }

  Future<void> _fetchSessionDetails() async {
    final sessionId = widget.session['id'];
    if (sessionId == null) return;

    setState(() {
      _isLoadingDetails = true;
      _errorDetails = null;
    });

    try {
      final response = await ApiClient().dio.get('/session/$sessionId/results');
      if (response.statusCode == 200 && response.data is List) {
        if (mounted) {
          setState(() {
            _results = (response.data as List).cast<Map<String, dynamic>>();
            _isLoadingDetails = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorDetails = 'Gagal memuat detail repetisi';
            _isLoadingDetails = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorDetails = 'Koneksi gagal saat memuat detail';
          _isLoadingDetails = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double accuracy =
        (widget.session['accuracy'] as num?)?.toDouble() ?? 0.0;
    final int totalReps = (widget.session['total_reps'] as num?)?.toInt() ?? 0;
    final int correctReps = (widget.session['correct_reps'] as num?)?.toInt() ?? 0;
    final String type = widget.session['exercise_type'] ?? '-';
    final color = _gradeColor(accuracy);
    final time = _formatTime(widget.session['created_at'] as String?);

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacing12),
      decoration: AppTheme.cardDecoration(shadowColor: color),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleExpand,
          borderRadius: BorderRadius.circular(AppTheme.radius20),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.spacing16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Header Row ──
                Row(
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
                          color: color,
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

                    // Grade badge + dropdown indicator
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        GradeBadge(accuracy: accuracy),
                        const SizedBox(height: AppTheme.spacing8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _isExpanded ? 'Hide' : 'Details',
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Icon(
                              _isExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              color: color,
                              size: 16,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                // ── Animated Inline Details Section ──
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _isExpanded
                      ? _buildInlineDetails(
                          context,
                          accuracy,
                          totalReps,
                          correctReps,
                          color,
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInlineDetails(
    BuildContext context,
    double accuracy,
    int totalReps,
    int correctReps,
    Color gradeColor,
  ) {
    final int incorrectReps = totalReps - correctReps;
    final insightIcon = accuracy >= 65
        ? Icons.tips_and_updates_rounded
        : Icons.info_outline_rounded;
    final iconColor = accuracy >= 65 ? AppTheme.success : AppTheme.warning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppTheme.spacing12),
        const Divider(color: AppTheme.dividerColor, height: 24),

        // ── Stats Row ──
        Row(
          children: [
            Expanded(
              child: _buildMiniStatItem('Total Reps', '$totalReps', AppTheme.primaryBlue),
            ),
            const SizedBox(width: AppTheme.spacing8),
            Expanded(
              child: _buildMiniStatItem('Correct', '$correctReps', AppTheme.success),
            ),
            const SizedBox(width: AppTheme.spacing8),
            Expanded(
              child: _buildMiniStatItem('Incorrect', '$incorrectReps', AppTheme.error),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing16),

        // ── Performance Insights ──
        Text(
          'Performance Insights',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: AppTheme.spacing8),
        Container(
          padding: const EdgeInsets.all(AppTheme.spacing12),
          decoration: BoxDecoration(
            color: AppTheme.bgSoftBlue,
            borderRadius: BorderRadius.circular(AppTheme.radius12),
            border: Border.all(color: iconColor.withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(insightIcon, color: iconColor, size: 20),
              const SizedBox(width: AppTheme.spacing12),
              Expanded(
                child: Text(
                  _getInsight(accuracy),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textDark,
                        height: 1.45,
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTheme.spacing16),

        // ── Repetition Breakdown Header ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Repetition Breakdown',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (_results != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.bgSoftBlue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_results!.length} Reps Logged',
                  style: const TextStyle(
                    color: AppTheme.primaryBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing8),
        _buildRepDetailsList(context),
      ],
    );
  }

  Widget _buildMiniStatItem(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppTheme.radius8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textGrey,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRepDetailsList(BuildContext context) {
    if (_isLoadingDetails) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.spacing16),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppTheme.primaryBlue,
            ),
          ),
        ),
      );
    }

    if (_errorDetails != null) {
      return Container(
        padding: const EdgeInsets.all(AppTheme.spacing12),
        decoration: BoxDecoration(
          color: AppTheme.errorLight,
          borderRadius: BorderRadius.circular(AppTheme.radius8),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _errorDetails!,
                style: const TextStyle(color: AppTheme.error, fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: _fetchSessionDetails,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: const Text('Retry', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    if (_results == null || _results!.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppTheme.spacing12),
        decoration: BoxDecoration(
          color: AppTheme.bgLightGrey,
          borderRadius: BorderRadius.circular(AppTheme.radius8),
        ),
        child: const Center(
          child: Text(
            'No detailed repetitions recorded for this session.',
            style: TextStyle(color: AppTheme.textGrey, fontSize: 12),
          ),
        ),
      );
    }

    return Column(
      children: _results!.map((item) {
        final int repNumber = (item['rep_number'] as num?)?.toInt() ?? 0;
        final String status = item['prediction']?.toString() ?? 'unknown';
        final bool isCorrect = status.toLowerCase() == 'correct';
        final statusColor = isCorrect
            ? AppTheme.success
            : (status.toLowerCase() == 'invalid'
                ? AppTheme.textGrey
                : AppTheme.error);

        final iconData = isCorrect
            ? Icons.check_circle_rounded
            : (status.toLowerCase() == 'invalid'
                ? Icons.help_outline_rounded
                : Icons.warning_rounded);

        final String feedback =
            (item['feedback_text'] as String?)?.isNotEmpty == true
                ? item['feedback_text'] as String
                : (isCorrect
                    ? 'Optimal movement execution and stable posture throughout.'
                    : 'Form deviation detected during this repetition.');

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.bgWhite,
            borderRadius: BorderRadius.circular(AppTheme.radius12),
            border: Border.all(color: statusColor.withValues(alpha: 0.25)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '#$repNumber',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(iconData, color: statusColor, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _formatRepStatus(status),
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feedback,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textDark,
                            height: 1.35,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
