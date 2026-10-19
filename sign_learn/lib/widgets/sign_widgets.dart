import 'package:flutter/material.dart';

/// Draws a simple hand: each finger is tall (1) or short (0), from robot_pose.
class HandPoseView extends StatelessWidget {
  final Map<String, int> pose;
  final double height;

  const HandPoseView({super.key, required this.pose, this.height = 220});

  static const _order = ['thumb', 'index', 'middle', 'ring', 'pinky'];
  static const _lengths = {
    'thumb': 0.6,
    'index': 0.85,
    'middle': 1.0,
    'ring': 0.85,
    'pinky': 0.65,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fingerAreaH = height * 0.7;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: fingerAreaH,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final finger in _order)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutBack,
                    width: 30,
                    height: (pose[finger] ?? 0) == 1
                        ? fingerAreaH * _lengths[finger]!
                        : fingerAreaH * 0.14,
                    decoration: BoxDecoration(
                      color: (pose[finger] ?? 0) == 1
                          ? cs.primary
                          : cs.primary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(
          width: 200,
          height: height * 0.3,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(10),
              topRight: Radius.circular(10),
              bottomLeft: Radius.circular(60),
              bottomRight: Radius.circular(60),
            ),
          ),
        ),
      ],
    );
  }
}

/// Three dots, filled according to the difficulty (1 to 3).
class DifficultyDots extends StatelessWidget {
  final int level;

  const DifficultyDots({super.key, required this.level});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 3; i++)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= level
                  ? cs.primary
                  : cs.primary.withValues(alpha: 0.25),
            ),
          ),
      ],
    );
  }
}
