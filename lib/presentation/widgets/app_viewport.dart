import 'package:flutter/material.dart';

class AppViewport extends StatelessWidget {
  const AppViewport({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
        top: false,
        child: Theme(
          data: Theme.of(context).copyWith(
              appBarTheme: Theme.of(context).appBarTheme.copyWith(
                    toolbarHeight: 56 +
                        (MediaQuery.textScalerOf(context).scale(20) - 20)
                                .clamp(0, 80) *
                            2,
                  )),
          child: child,
        ),
      );
}
