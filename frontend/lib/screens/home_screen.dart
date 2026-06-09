import 'package:flutter/material.dart';
import '../widgets/custom_widgets.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 24),
            Text(
              'Your Training',
              style: Theme.of(context).textTheme.displayLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Select your focus area',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),

            Expanded(
              child: ListView(
                children: [
                  TrainingCard(
                    title: 'Biceps Training',
                    description: 'Focus on perfect form with AI tracking.',
                    // CHANGED: onPressed to onStart
                    onStart: () => Navigator.pushNamed(context, '/training'),
                  ),
                  TrainingCard(
                    title: 'Squat Evaluation',
                    description: 'Prevent injury by checking your depth.',
                    // CHANGED: onPressed to onStart
                    onStart: () => Navigator.pushNamed(context, '/training'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
