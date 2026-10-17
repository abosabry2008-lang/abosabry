import 'package:flutter/material.dart';

/// Pushes [screen] as a standalone route wrapped in a [Scaffold] with an
/// [AppBar], so body-only screens also work outside the [AppShell].
Future<T?> pushScreen<T>(
  BuildContext context,
  String title,
  Widget screen, {
  List<Widget>? actions,
}) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      builder: (_) => Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: actions,
        ),
        body: screen,
      ),
    ),
  );
}
