import 'package:flutter/material.dart';

/// Animated placeholder block for OX loading states.
class OxSkeletonBox extends StatefulWidget {
  final double? width;
  final double? height;
  final BorderRadiusGeometry borderRadius;

  const OxSkeletonBox({
    this.width,
    this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    super.key,
  });

  @override
  State<OxSkeletonBox> createState() => _OxSkeletonBoxState();
}

class _OxSkeletonBoxState extends State<OxSkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight = scheme.surfaceContainerHigh;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1.0 + (t * 2), 0),
              end: Alignment(0.0 + (t * 2), 0),
              colors: [base, highlight, base],
            ),
          ),
          child: SizedBox(
            width: widget.width,
            height: widget.height,
          ),
        );
      },
    );
  }
}
