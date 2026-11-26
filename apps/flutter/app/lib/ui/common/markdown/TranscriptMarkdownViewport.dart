// ignore_for_file: file_names

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Enables block virtualization inside a chat transcript row.
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
  final _mountedBlocks = <int, Widget>{};
  late _BlockExtents _extents = _BlockExtents(
    widget.blockCount,
    _measuredHeights,
  );
  ScrollPosition? _position;
  bool _scheduled = false;
  bool _measurementsChanged = false;
  int _first = 0;
  int _end = 6;
  double? _layoutWidth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context, axis: Axis.vertical)?.position;
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
      _extents = _BlockExtents(widget.blockCount, _measuredHeights);
    }
    if (oldWidget.builder != widget.builder) _mountedBlocks.clear();
    _schedule();
  }

  @override
  void dispose() {
    _position?.removeListener(_schedule);
    super.dispose();
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) return;
      RenderObject? viewport = RenderAbstractViewport.maybeOf(box);
      // A table's horizontal scroll view is nested in the transcript viewport.
      while (viewport != null && viewport is! RenderViewportBase) {
        viewport = RenderAbstractViewport.maybeOf(viewport.parent);
      }
      if (viewport is! RenderBox || !viewport.hasSize) return;
      final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
      if (!top.isFinite) return;
      final changed = _measurementsChanged;
      _measurementsChanged = false;
      final visibleStart = -top;
      final visibleEnd = viewport.size.height - top;
      var first = _first;
      var end = _end;
      // Move the window in batches. Keep nearby blocks mounted through small
      // movements and keep a buffer in both directions for fast flings.
      if (end > widget.blockCount ||
          (first > 0 && _extents.before(first) > visibleStart - 120) ||
          (end < widget.blockCount &&
              _extents.before(end) < visibleEnd + 120) ||
          visibleStart - _extents.before(first) > 720 ||
          _extents.before(end) - visibleEnd > 720) {
        first = _extents.blockAt(visibleStart - 360);
        end = math.min(
          widget.blockCount,
          _extents.blockAt(visibleEnd + 360) + 1,
        );
      }
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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      if (_layoutWidth != width) {
        _layoutWidth = width;
        _measuredHeights.clear();
        _extents = _BlockExtents(widget.blockCount, _measuredHeights);
        _schedule();
      }
      return _buildBlocks(context);
    },
  );

  Widget _buildBlocks(BuildContext context) {
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
    _mountedBlocks.removeWhere((index, _) => index < first || index >= end);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (first > 0) SizedBox(height: _extents.before(first)),
        for (var index = first; index < end; index++)
          _BlockMeasurement(
            key: ValueKey(index),
            onMeasured: (height) {
              if (_measuredHeights[index] == height) return;
              _extents.resize(
                index,
                height - (_measuredHeights[index] ?? _BlockExtents.estimate),
              );
              _measuredHeights[index] = height;
              _measurementsChanged = true;
              _schedule();
            },
            child: _mountedBlocks.putIfAbsent(
              index,
              () => widget.builder(context, index),
            ),
          ),
        if (end < widget.blockCount)
          SizedBox(
            height: _extents.before(widget.blockCount) - _extents.before(end),
          ),
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

/// A prefix sum index. Layout updates a measured block without walking the reply.
class _BlockExtents {
  _BlockExtents(this.length, Map<int, double> heights)
    : _changes = Float64List(length + 1) {
    for (final entry in heights.entries) {
      resize(entry.key, entry.value - estimate);
    }
  }

  static const estimate = 64.0;
  final int length;
  final Float64List _changes;

  void resize(int index, double delta) {
    for (var i = index + 1; i <= length; i += i & -i) {
      _changes[i] += delta;
    }
  }

  double before(int index) {
    var offset = index * estimate;
    for (var i = index; i > 0; i -= i & -i) {
      offset += _changes[i];
    }
    return offset;
  }

  int blockAt(double offset) {
    var first = 0;
    var end = length;
    while (first < end) {
      final middle = (first + end) >> 1;
      if (before(middle + 1) <= offset) {
        first = middle + 1;
      } else {
        end = middle;
      }
    }
    return first;
  }
}
