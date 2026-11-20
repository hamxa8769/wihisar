/// Small cyberpunk widgets shared by the tabs: neon cards, section
/// headings and status chips. Pure Flutter, no assets.
library;

import 'package:flutter/material.dart';

import '../theme/cyberpunk_theme.dart';

/// A panel with a neon accent border and a soft glow.
class CyberCard extends StatelessWidget {
  const CyberCard({
    super.key,
    required this.child,
    this.accent = CyberpunkTheme.neonCyan,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final Color accent;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: CyberpunkTheme.panelDecoration(accent: accent),
      padding: padding,
      child: child,
    );
  }
}

/// Section heading in monospace with a neon underline bar.
class CyberHeading extends StatelessWidget {
  const CyberHeading(this.text, {super.key, this.accent});

  final String text;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? CyberpunkTheme.neonCyan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.toUpperCase(),
          style: CyberpunkTheme.display.copyWith(fontSize: 18, color: color),
        ),
        const SizedBox(height: 6),
        Container(height: 2, width: 48, color: color),
      ],
    );
  }
}

/// Small pill label, e.g. `COMING SOON • v0.3.0` or `LIVE`.
class CyberChip extends StatelessWidget {
  const CyberChip(this.label, {super.key, this.accent});

  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? CyberpunkTheme.neonMagenta;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
          letterSpacing: 1,
        ),
      ),
    );
  }
}
