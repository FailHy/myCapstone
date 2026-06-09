import 'package:flutter/material.dart';
import '../theme.dart';

// --- REUSABLE BUTTON ---
class PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final bool isFullWidth;

  const PrimaryButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isFullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: isFullWidth ? double.infinity : null,
      height: 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.accentLime,
          foregroundColor: AppTheme.primaryNavy, // High contrast text
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        onPressed: onPressed,
        child: Text(
          text,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// --- REUSABLE TRAINING CARD ---
class TrainingCard extends StatelessWidget {
  final String title;
  final String description;
  final VoidCallback onStart;

  const TrainingCard({
    super.key,
    required this.title,
    required this.description,
    required this.onStart,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Placeholder (In production: CachedNetworkImage)
          Container(
            height: 150,
            decoration: const BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: const Center(
              child: Icon(
                Icons.fitness_center,
                size: 50,
                color: Colors.white24,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                PrimaryButton(text: "Start Routine", onPressed: onStart),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- REUSABLE STATS CARD ---
class StatsCard extends StatelessWidget {
  final String title;
  final String value;

  const StatsCard({super.key, required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.accentLime,
              ),
            ),
            const SizedBox(height: 4),
            Text(title, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
