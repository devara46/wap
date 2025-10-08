import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTheme.heading2),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: AppTheme.bodySmall),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}