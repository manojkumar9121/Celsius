import 'package:flutter/material.dart';

class ShimmerEffect extends StatefulWidget {
  final Widget child;
  final Duration period;
  final double radius;
  final Color? baseColor;
  final Color? highlightColor;

  const ShimmerEffect({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 1500),
    this.radius = 8.0,
    this.baseColor,
    this.highlightColor,
  });

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.period,
      vsync: this,
    );
    _animation = Tween<double>(begin: -2.0, end: 2.0).animate(_controller)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _controller.forward(from: 0.0);
        }
      });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = widget.baseColor ?? theme.colorScheme.surfaceContainerHighest;
    final highlightColor = widget.highlightColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.08);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                baseColor,
                highlightColor,
                baseColor,
                baseColor,
              ],
              stops: [
                (_animation.value - 0.5).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.3).clamp(0.0, 1.0),
                (_animation.value + 0.5).clamp(0.0, 1.0),
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class ShimmerLine extends StatelessWidget {
  final double height;
  final double width;
  final double radius;

  const ShimmerLine({
    super.key,
    this.height = 16.0,
    this.width = double.infinity,
    this.radius = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class ShimmerSongTile extends StatelessWidget {
  const ShimmerSongTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerLine(height: 14, radius: 4),
                const SizedBox(height: 6),
                ShimmerLine(height: 10, width: 120, radius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ShimmerCard extends StatelessWidget {
  final double height;
  final double width;

  const ShimmerCard({super.key, this.height = 140, this.width = 140});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
