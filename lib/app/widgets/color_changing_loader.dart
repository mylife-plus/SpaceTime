import 'package:flutter/material.dart';

class ColorChangingLoader extends StatefulWidget {
  const ColorChangingLoader({super.key});

  @override
  State<ColorChangingLoader> createState() => _ColorChangingLoaderState();
}

class _ColorChangingLoaderState extends State<ColorChangingLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _colorAnimation = _controller.drive(
      TweenSequence<Color?>([
        TweenSequenceItem(
          tween: ColorTween(begin: Colors.blue, end: Colors.green),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: ColorTween(begin: Colors.green, end: Colors.purple),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: ColorTween(begin: Colors.purple, end: Colors.orange),
          weight: 1,
        ),
        TweenSequenceItem(
          tween: ColorTween(begin: Colors.orange, end: Colors.blue),
          weight: 1,
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedBuilder(
        animation: _colorAnimation,
        builder: (context, child) {
          return CircularProgressIndicator(
            color: _colorAnimation.value,
            strokeWidth: 4,
          );
        },
      ),
    );
  }
}
