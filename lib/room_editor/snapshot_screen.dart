import 'package:flutter/material.dart';

class SnapshotScreen extends StatelessWidget {
  final String displaySText;
  final VoidCallback onSettingsPressed;
  final Future<void> Function() onCopyPressed;

  const SnapshotScreen({
    super.key,
    required this.displaySText,
    required this.onSettingsPressed,
    required this.onCopyPressed,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth - 16,
          height: 120,
          child: Stack(
            children: [
              SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: SingleChildScrollView(
                  child: SelectableText(
                    displaySText,
                    textAlign: TextAlign.left,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: onSettingsPressed,
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy),
                      tooltip: 'コピー',
                      onPressed: () => onCopyPressed(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
