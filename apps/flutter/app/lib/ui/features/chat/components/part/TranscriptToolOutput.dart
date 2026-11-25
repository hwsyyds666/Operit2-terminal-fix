// ignore_for_file: file_names

import 'package:flutter/material.dart';

const deferredToolOutputAttribute = 'operit_deferred_output';

/// Resolves payloads within the exact message revision that owns the tool row.
class TranscriptToolOutputScope extends InheritedWidget {
  const TranscriptToolOutputScope({
    super.key,
    required this.load,
    required super.child,
  });

  final Future<String?> Function(String)? load;

  static Future<String?> Function(String)? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TranscriptToolOutputScope>()
      ?.load;

  @override
  bool updateShouldNotify(TranscriptToolOutputScope oldWidget) =>
      load != oldWidget.load;
}
