// ignore_for_file: file_names

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Enables body virtualization only inside a completed chat transcript row.
class TranscriptMarkdownScope extends InheritedWidget {
  const TranscriptMarkdownScope({
    super.key,
    required this.enabled,
    required super.child,
  });

  final bool enabled;

  static bool enabledOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TranscriptMarkdownScope>()
          ?.enabled ??
      false;

  @override
  bool updateShouldNotify(TranscriptMarkdownScope oldWidget) =>
      enabled != oldWidget.enabled;
}

/// Displays only the semantic blocks near the parent transcript viewport.
/// The outer scrollable keeps ownership of gestures, focus, and selection.
class TranscriptMarkdownViewport extends StatefulWidget {
  const TranscriptMarkdownViewport({
    super.key,
    required this.blockCount,
    required this.builder,
  });

  final int blockCount;
  final IndexedWidgetBuilder builder;

  @override
  State<TranscriptMarkdownViewport> createState() =>
      _TranscriptMarkdownViewportState();
}

class _TranscriptMarkdownViewportState
    extends State<TranscriptMarkdownViewport> {
  final _measuredHeights = <int, double>{};
  late List<double> _offsets = _measureOffsets();
  ScrollPosition? _position;
  bool _scheduled = false;
  bool _measurementsChanged = false;
  int _first = 0;
  int _end = 6;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_schedule);
      _position = position;
      _position?.addListener(_schedule);
    }
    _schedule();
  }

  @override
  void didUpdateWidget(covariant TranscriptMarkdownViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blockCount != widget.blockCount) {
      _measuredHeights.removeWhere((index, _) => index >= widget.blockCount);
      _offsets = _measureOffsets();
    }
    _schedule();
  }

  @override
  void dispose() {
    _position?.removeListener(_schedule);
    super.dispose();
  }

  List<double> _measureOffsets() {
    final offsets = <double>[0];
    for (var index = 0; index < widget.blockCount; index++) {
      offsets.add(offsets.last + (_measuredHeights[index] ?? 64));
    }
    return offsets;
  }

  /// Finds the first block whose lower edge lies below the requested position.
  int _blockAt(double offset) {
    var first = 0;
    var end = widget.blockCount;
    while (first < end) {
      final middle = (first + end) ~/ 2;
      if (_offsets[middle + 1] <= offset) {
        first = middle + 1;
      } else {
        end = middle;
      }
    }
    return first;
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) return;
      final viewport = RenderAbstractViewport.maybeOf(box) as RenderBox?;
      if (viewport == null || !viewport.hasSize) return;
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (!top.isFinite) return;
      final changed = _measurementsChanged;
      _measurementsChanged = false;
      if (changed) _offsets = _measureOffsets();
      const prefetch = 240.0;
      final first = _blockAt(-top - prefetch);
      final end = math.min(
        widget.blockCount,
        _blockAt(viewport.size.height - top + prefetch) + 1,
      );
      if (changed || first != _first || end != _end) {
        setState(() {
          _first = first;
          _end = end;
        });
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) {
    if (_position == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < widget.blockCount; index++)
            widget.builder(context, index),
        ],
      );
    }
    final first = math.min(_first, widget.blockCount);
    final end = math.min(_end, widget.blockCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (first > 0) SizedBox(height: _offsets[first]),
        for (var index = first; index < end; index++)
          _BlockMeasurement(
            key: ValueKey(index),
            onMeasured: (height) {
              if (_measuredHeights[index] == height) return;
              _measuredHeights[index] = height;
              _measurementsChanged = true;
              _schedule();
            },
            child: widget.builder(context, index),
          ),
        if (end < widget.blockCount)
          SizedBox(height: _offsets.last - _offsets[end]),
      ],
    );
  }
}

class _BlockMeasurement extends SingleChildRenderObjectWidget {
  const _BlockMeasurement({
    super.key,
    required this.onMeasured,
    required super.child,
  });

  final ValueChanged<double> onMeasured;

  @override
  RenderProxyBox createRenderObject(BuildContext context) =>
      _MeasuredBlock(onMeasured);

  @override
  void updateRenderObject(BuildContext context, _MeasuredBlock renderObject) =>
      renderObject.onMeasured = onMeasured;
}

class _MeasuredBlock extends RenderProxyBox {
  _MeasuredBlock(this.onMeasured);

  ValueChanged<double> onMeasured;

  @override
  void performLayout() {
    super.performLayout();
    onMeasured(size.height);
  }
}
