import 'package:flutter/material.dart';
import 'package:frontend/screens/training_setup_screen.dart';
import '../core/models/exercise_type.dart';
import '../theme.dart';
class RepetitionDetail {
  final int repNumber;
  final String status;
  final double confidence;
  final String feedbackText;

  const RepetitionDetail({
    required this.repNumber,
    required this.status,
    required this.confidence,
    required this.feedbackText,
  });

  bool get isCorrect => status.toLowerCase() == 'correct';

  String get formattedStatus {
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

  Color get statusColor {
    if (isCorrect) return AppTheme.success;
    if (status.toLowerCase() == 'invalid') return AppTheme.textGrey;
    return AppTheme.error;
  }
}

class TrainingResult {
  final ExerciseType exerciseType;
  final int totalReps;
  final int correctReps;
  final double accuracy;
  final Map<String, int> errorDistribution;
  final List<RepetitionDetail> repDetails;

  const TrainingResult({
    required this.exerciseType,
    required this.totalReps,
    required this.correctReps,
    required this.accuracy,
    required this.errorDistribution,
    this.repDetails = const [],
  });

  int get incorrectReps => totalReps - correctReps;

  String get grade {
    if (accuracy >= 85) return 'Excellent';
    if (accuracy >= 65) return 'Good';
    if (accuracy >= 45) return 'Fair';
    return 'Needs Practice';
  }

  Color get gradeColor {
    if (accuracy >= 85) return AppTheme.success;
    if (accuracy >= 65) return AppTheme.primaryBlue;
    if (accuracy >= 45) return AppTheme.warning;
    return AppTheme.error;
  }

  Color get gradeLightColor {
    if (accuracy >= 85) return AppTheme.successLight;
    if (accuracy >= 65) return AppTheme.bgSoftBlue;
    if (accuracy >= 45) return AppTheme.warningLight;
    return AppTheme.errorLight;
  }

  IconData get gradeIcon {
    if (accuracy >= 85) return Icons.emoji_events_rounded;
    if (accuracy >= 65) return Icons.thumb_up_rounded;
    if (accuracy >= 45) return Icons.trending_up_rounded;
    return Icons.fitness_center_rounded;
  }

  String get insight {
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
}

class ResultScreen extends StatelessWidget {
  final TrainingResult result;
  const ResultScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgLightGrey,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Training Result',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        iconTheme: const IconThemeData(color: AppTheme.textDark),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppTheme.spacing24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Exercise & Grade Header ─────────────────────────────
              _buildGradeHeader(context),
              const SizedBox(height: AppTheme.spacing24),

              // ── Stats Row ───────────────────────────────────────────
              _buildStatsRow(context),
              const SizedBox(height: AppTheme.spacing24),

              // ── Performance Insights ────────────────────────────────
              Text(
                'Performance Insights',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppTheme.spacing12),
              _buildInsightCard(context),

              // ── Repetition Breakdown ────────────────────────────────
              if (result.repDetails.isNotEmpty) ...[
                const SizedBox(height: AppTheme.spacing24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Repetition Breakdown',
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacing8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacing12,
                        vertical: AppTheme.spacing4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSoftBlue,
                        borderRadius: BorderRadius.circular(AppTheme.radius12),
                      ),
                      child: Text(
                        '${result.repDetails.length} Reps Logged',
                        style: const TextStyle(
                          color: AppTheme.primaryBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing12),
                _buildRepetitionCard(context),
              ],
              const SizedBox(height: AppTheme.spacing32),

              // ── Action Buttons ──────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => TrainingSetupScreen(
                            exerciseType: result.exerciseType,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.replay_rounded, size: AppTheme.iconMd),
                      label: const Text('Try Again'),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacing12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).popUntil((r) => r.isFirst),
                      icon: const Icon(Icons.home_outlined, size: AppTheme.iconMd),
                      label: const Text('Home'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacing16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGradeHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing24),
      decoration: BoxDecoration(
        color: result.gradeLightColor,
        borderRadius: BorderRadius.circular(AppTheme.radius20),
        border: Border.all(
          color: result.gradeColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing16),
            decoration: BoxDecoration(
              color: result.gradeColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              result.gradeIcon,
              color: result.gradeColor,
              size: 36,
            ),
          ),
          const SizedBox(width: AppTheme.spacing16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image.asset(
                      result.exerciseType.assetIcon,
                      width: 22,
                      height: 22,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.fitness_center_rounded,
                        size: 18,
                        color: AppTheme.textGrey,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      result.exerciseType.displayName,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textGrey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing4),
                Text(
                  result.grade,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: result.gradeColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Accuracy circle
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: result.accuracy / 100,
                  strokeWidth: 6,
                  backgroundColor:
                      result.gradeColor.withValues(alpha: 0.15),
                  valueColor:
                      AlwaysStoppedAnimation<Color>(result.gradeColor),
                ),
                Text(
                  '${result.accuracy.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: result.gradeColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatMiniCard(
            label: 'Total Reps',
            value: '${result.totalReps}',
            icon: Icons.repeat_rounded,
            color: AppTheme.primaryBlue,
          ),
        ),
        const SizedBox(width: AppTheme.spacing12),
        Expanded(
          child: _StatMiniCard(
            label: 'Correct',
            value: '${result.correctReps}',
            icon: Icons.check_circle_outline_rounded,
            color: AppTheme.success,
          ),
        ),
        const SizedBox(width: AppTheme.spacing12),
        Expanded(
          child: _StatMiniCard(
            label: 'Incorrect',
            value: '${result.incorrectReps}',
            icon: Icons.cancel_outlined,
            color: AppTheme.error,
          ),
        ),
      ],
    );
  }

  Widget _buildInsightCard(BuildContext context) {
    final iconColor = result.accuracy >= 65 ? AppTheme.success : AppTheme.warning;
    final insightIcon =
        result.accuracy >= 65 ? Icons.tips_and_updates_rounded : Icons.info_outline_rounded;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing20),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radius8),
            ),
            child: Icon(insightIcon, color: iconColor, size: AppTheme.iconMd),
          ),
          const SizedBox(width: AppTheme.spacing16),
          Expanded(
            child: Text(
              result.insight,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textDark,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRepetitionCard(BuildContext context) {
    return Column(
      children: result.repDetails.map((detail) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppTheme.spacing12),
          child: _RepetitionTile(detail: detail),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _StatMiniCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatMiniCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppTheme.spacing16,
        horizontal: AppTheme.spacing12,
      ),
      decoration: BoxDecoration(
        color: AppTheme.bgWhite,
        borderRadius: BorderRadius.circular(AppTheme.radius16),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: AppTheme.iconMd),
          const SizedBox(height: AppTheme.spacing8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: AppTheme.spacing4),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _RepetitionTile extends StatelessWidget {
  final RepetitionDetail detail;

  const _RepetitionTile({required this.detail});

  @override
  Widget build(BuildContext context) {
    final statusColor = detail.statusColor;
    final iconData = detail.isCorrect
        ? Icons.check_circle_rounded
        : (detail.status.toLowerCase() == 'invalid'
            ? Icons.help_outline_rounded
            : Icons.warning_rounded);

    final String feedback = detail.feedbackText.isNotEmpty
        ? detail.feedbackText
        : (detail.isCorrect
            ? 'Optimal movement execution and stable posture throughout.'
            : 'Form deviation detected during this repetition.');

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacing16),
      decoration: BoxDecoration(
        color: AppTheme.bgWhite,
        borderRadius: BorderRadius.circular(AppTheme.radius16),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.25),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 8.0,
            ),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppTheme.radius12),
            ),
            child: Text(
              '#${detail.repNumber}',
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacing16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(iconData, color: statusColor, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        detail.formattedStatus,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacing8),
                Text(
                  feedback,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textDark,
                        height: 1.45,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

