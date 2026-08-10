import 'package:flutter/material.dart';

class TransitionPage extends Page {
  final Widget child;
  final Duration transitionDuration;
  final bool slideUp;

  const TransitionPage({
    required this.child,
    this.transitionDuration = const Duration(milliseconds: 350),
    this.slideUp = true,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  @override
  Route createRoute(BuildContext context) {
    return _TransitionRoute(
      settings: this,
      child: child,
      transitionDuration: transitionDuration,
      slideUp: slideUp,
    );
  }
}

class _TransitionRoute<T> extends PageRoute<T> {
  final Widget child;
  final Duration transitionDuration;
  final bool slideUp;

  _TransitionRoute({
    required super.settings,
    required this.child,
    required this.transitionDuration,
    required this.slideUp,
  });

  @override
  bool get maintainState => true;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    return child;
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (slideUp) {
      final offsetAnimation = Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
      return SlideTransition(position: offsetAnimation, child: child);
    }
    return FadeTransition(opacity: animation, child: child);
  }
}
