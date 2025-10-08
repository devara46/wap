import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class CustomCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? backgroundColor;

  const CustomCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16.0),
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration.copyWith(
        color: backgroundColor ?? AppTheme.cardColor,
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class InstructionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? backgroundColor;

  const InstructionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16.0),
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.cardDecoration.copyWith(
        color: backgroundColor ?? AppTheme.primaryColor.shade50,
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}