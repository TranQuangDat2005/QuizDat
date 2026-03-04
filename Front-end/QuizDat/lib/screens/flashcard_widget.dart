import 'package:flutter/material.dart';
import 'dart:math';

class FlashcardWidget extends StatefulWidget {
  final String frontText;
  final String backText;

  const FlashcardWidget({
    super.key,
    required this.frontText,
    required this.backText,
  });

  @override
  State<FlashcardWidget> createState() => FlashcardWidgetState();
}

class FlashcardWidgetState extends State<FlashcardWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _isFront = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _animation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void flipCard() {
    if (_controller.isAnimating) return;
    if (_isFront) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    _isFront = !_isFront;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: flipCard,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          double angle = _animation.value * pi;
          bool isFrontVisible = angle < (pi / 2);

          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;

          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX(angle),
            alignment: Alignment.center,
            child: isFrontVisible
                ? _buildCardSide(
                    text: widget.frontText,
                    bgColor: theme.cardColor,
                    isFront: true,
                  )
                : Transform(
                    transform: Matrix4.identity()..rotateX(pi),
                    alignment: Alignment.center,
                    child: _buildCardSide(
                      text: widget.backText,
                      bgColor: isDark ? theme.cardColor.withOpacity(0.8) : Colors.grey.shade100,
                      isFront: false,
                    ),
                  ),
          );
        },
      ),
    );
  }

  Widget _buildCardSide({
    required String text,
    required Color bgColor,
    required bool isFront,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      height: 400,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor, width: 2.5),
        boxShadow: [
          BoxShadow(
              color: isDark ? Colors.black54 : Colors.black,
              offset: const Offset(6, 6),
              blurRadius: 0
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: isFront ? 32 : 24,
            fontWeight: isFront ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
