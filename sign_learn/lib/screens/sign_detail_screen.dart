import 'package:flutter/material.dart';

import '../models/sign.dart';
import '../widgets/sign_widgets.dart';

class SignDetailScreen extends StatelessWidget {
  final Sign sign;

  const SignDetailScreen({super.key, required this.sign});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text('Sign ${sign.name}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: HandPoseView(pose: sign.robotPose)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                sign.name,
                style: text.displayMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              DifficultyDots(level: sign.difficulty),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How to sign', style: text.titleMedium),
                  const SizedBox(height: 8),
                  Text(sign.description, style: text.bodyLarge),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Practice mode is coming soon')),
            ),
            icon: const Icon(Icons.camera_alt),
            label: const Text('Practice this sign'),
          ),
        ],
      ),
    );
  }
}
