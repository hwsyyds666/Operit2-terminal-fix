// ignore_for_file: file_names

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/OperitTheme.dart';
import 'MarkdownInlineSpannable.dart';
import 'MarkdownNodeGrouper.dart';
import 'MarkdownSelectionArea.dart';
import 'StreamMarkdownRenderer.dart';
import 'StreamMarkdownRendererState.dart';
import 'TranscriptMarkdownViewport.dart';

const double tableMinColumnWidth = 80;
const double tableMaxColumnWidth = 320;
const double tableCellHorizontalPadding = 8;
const double tableCellVerticalPadding = 8;
const double tableOuterVerticalPadding = 8;
const double tableCornerRadius = 4;
const double tableBorderWidth = 1;
const double tableGridWidth = 0.5;
const double tableLineHeight = markdownLineHeight;

class EnhancedTableBlock extends StatefulWidget {
  const EnhancedTableBlock({
    super.key,
    required this.tableText,
    required this.textColor,
    required this.splitMarkdownContent,
  });

  final String tableText;
  final Color textColor;
  final MarkdownContentSplitter splitMarkdownContent;

  @override
  State<EnhancedTableBlock> createState() => _EnhancedTableBlockState();
}

class _EnhancedTableBlockState extends State<EnhancedTableBlock> {
  late var _parsed = _parseTable(widget.tableText);
  final _plans = <String, Future<List<MarkdownNodeStable>>>{};
  (TextStyle?, TextStyle?, TextScaler, TextDirection)? _widthContext;
  Map<int, TableColumnWidth>? _widths;

  @override
  void didUpdateWidget(EnhancedTableBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableText != widget.tableText) {
      _parsed = _parseTable(widget.tableText);
      _widths = null;
    }
    if (oldWidget.splitMarkdownContent != widget.splitMarkdownContent) {
      _plans.clear();
    }
  }

  Future<List<MarkdownNodeStable>> _cellPlan(String text) {
    final cached = _plans.remove(text);
    final plan =
        cached ??
        widget.splitMarkdownContent(text).then(markdownNodesFromEvents);
    _plans[text] = plan;
    if (_plans.length > 256) _plans.remove(_plans.keys.first);
    return plan;
  }

  Map<int, TableColumnWidth> _measureColumns(
    BuildContext context,
    int count,
    TextStyle? body,
    TextStyle? header,
  ) {
    final settings = (
      body,
      header,
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
    );
    if (_widths != null && _widthContext == settings) return _widths!;
    final widths = List<double>.filled(count, tableMinColumnWidth);
    final candidates = List<(String, bool)>.filled(count, ('', false));
    for (final entry in _parsed.rows.indexed) {
      for (final cell in entry.$2.indexed) {
        final text = cell.$2;
        if (text.length > candidates[cell.$1].$1.length) {
          candidates[cell.$1] = (text, entry.$1 == 0);
        }
      }
    }
    final painter = TextPainter(
      textScaler: settings.$3,
      textDirection: settings.$4,
    );
    for (final entry in candidates.indexed) {
      final (text, isHeader) = entry.$2;
      painter.text = TextSpan(text: text, style: isHeader ? header : body);
      painter.layout();
      final width = math.max(
        painter.minIntrinsicWidth + tableCellHorizontalPadding * 2,
        math.min(
          tableMaxColumnWidth,
          painter.maxIntrinsicWidth + tableCellHorizontalPadding * 2,
        ),
      );
      widths[entry.$1] = width.clamp(tableMinColumnWidth, 2400).ceilToDouble();
    }
    painter.dispose();
    _widthContext = settings;
    return _widths = {
      for (final entry in widths.indexed) entry.$1: FixedColumnWidth(entry.$2),
    };
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    final rows = parsed.rows;
    final alignments = parsed.alignments;
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final transparentSurface = OperitTheme.of(
      context,
    ).themePreferenceSnapshot.transparentSurfaceEnabled;
    final outline = theme.colorScheme.outline.withValues(
      alpha: transparentSurface ? 0.32 : 0.5,
    );
    final grid = theme.colorScheme.outline.withValues(
      alpha: transparentSurface ? 0.22 : 0.35,
    );
    final headerColor = isDark
        ? theme.colorScheme.onSurface.withValues(
            alpha: transparentSurface ? 0.06 : 0.08,
          )
        : theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: transparentSurface ? 0.12 : 0.3,
          );
    final bodyColor = transparentSurface || isDark
        ? Colors.transparent
        : theme.colorScheme.surface;
    final bodyTextStyle = theme.textTheme.bodySmall?.copyWith(
      color: widget.textColor,
      height: tableLineHeight,
    );
    final headerTextStyle = bodyTextStyle?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final maxColumns = rows.fold<int>(
      0,
      (value, row) => row.length > value ? row.length : value,
    );
    final virtual =
        rows.length >= 24 && TranscriptMarkdownScope.enabledOf(context);
    final widths = virtual
        ? _measureColumns(context, maxColumns, bodyTextStyle, headerTextStyle)
        : null;
    TableRow tableRow(int rowIndex) => TableRow(
      decoration: BoxDecoration(
        color: rowIndex == 0 ? headerColor : bodyColor,
        border: virtual && rowIndex != rows.length - 1
            ? Border(
                bottom: BorderSide(color: grid, width: tableGridWidth),
              )
            : null,
      ),
      children: [
        for (var column = 0; column < maxColumns; column++)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: tableMinColumnWidth),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: tableCellHorizontalPadding,
                vertical: tableCellVerticalPadding,
              ),
              child: _MarkdownTableCellText(
                text: column < rows[rowIndex].length
                    ? rows[rowIndex][column]
                    : '',
                textColor: widget.textColor,
                style: rowIndex == 0 ? headerTextStyle : bodyTextStyle,
                textAlign: column < alignments.length
                    ? alignments[column]
                    : TextAlign.left,
                load: _cellPlan,
              ),
            ),
          ),
      ],
    );
    Widget table(List<TableRow> tableRows) => Table(
      defaultColumnWidth: const _MarkdownTableColumnWidth(),
      columnWidths: widths,
      border: TableBorder(
        horizontalInside: BorderSide(color: grid, width: tableGridWidth),
        verticalInside: BorderSide(color: grid, width: tableGridWidth),
      ),
      children: tableRows,
    );
    final tableContent = virtual
        ? TranscriptMarkdownViewport(
            blockCount: rows.length,
            builder: (context, index) => table([tableRow(index)]),
          )
        : table([for (var i = 0; i < rows.length; i++) tableRow(i)]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: tableOuterVerticalPadding),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tableCornerRadius),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: outline, width: tableBorderWidth),
            borderRadius: BorderRadius.circular(tableCornerRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.all(tableBorderWidth),
            child: MarkdownSelectionArea(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: tableContent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps prose compact while allowing indivisible formulas to fit their column.
class _MarkdownTableColumnWidth extends IntrinsicColumnWidth {
  const _MarkdownTableColumnWidth();

  /// Reserves the minimum content width even beyond the preferred text width.
  @override
  double maxIntrinsicWidth(Iterable<RenderBox> cells, double containerWidth) {
    return math
        .max(
          super.minIntrinsicWidth(cells, containerWidth),
          math.min(
            tableMaxColumnWidth,
            super.maxIntrinsicWidth(cells, containerWidth),
          ),
        )
        .ceilToDouble();
  }
}

({List<List<String>> rows, List<TextAlign> alignments}) _parseTable(
  String tableText,
) {
  final rows = <List<String>>[];
  var alignments = const <TextAlign>[];
  for (final line in tableText.split('\n')) {
    final trimmed = line.trim();
    if (!trimmed.contains('|')) {
      continue;
    }
    final start = trimmed.startsWith('|') ? 1 : 0;
    final end = trimmed.endsWith('|') ? trimmed.length - 1 : trimmed.length;
    final withoutEdges = trimmed.substring(start, end < start ? start : end);
    final cells = withoutEdges.split('|').map((cell) => cell.trim()).toList();
    if (_isSeparatorRow(cells)) {
      if (alignments.isEmpty) {
        alignments = cells.map(_parseCellAlignment).toList(growable: false);
      }
      continue;
    }
    rows.add(cells);
  }
  return (rows: rows, alignments: alignments);
}

bool _isSeparatorRow(List<String> cells) {
  return cells.isNotEmpty &&
      cells.every((cell) {
        var start = cell.startsWith(':') ? 1 : 0;
        final end = cell.endsWith(':') ? cell.length - 1 : cell.length;
        if (start >= end) return false;
        for (; start < end; start++) {
          if (cell.codeUnitAt(start) != 45) return false;
        }
        return true;
      });
}

class _MarkdownTableCellText extends StatefulWidget {
  const _MarkdownTableCellText({
    required this.text,
    required this.textColor,
    required this.style,
    required this.textAlign,
    required this.load,
  });

  final String text;
  final Color textColor;
  final TextStyle? style;
  final TextAlign textAlign;
  final Future<List<MarkdownNodeStable>> Function(String) load;

  @override
  State<_MarkdownTableCellText> createState() => _MarkdownTableCellTextState();
}

class _MarkdownTableCellTextState extends State<_MarkdownTableCellText> {
  final MarkdownLinkGestureOwner _gestures = MarkdownLinkGestureOwner();
  late Future<List<MarkdownNodeStable>> _nodes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _MarkdownTableCellText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _load();
  }

  void _load() {
    _nodes = widget.text.isEmpty
        ? Future.value(const [])
        : widget.load(widget.text);
  }

  @override
  void dispose() {
    _gestures.dispose();
    super.dispose();
  }

  /// Keeps asynchronous snapshots scoped to the cell source they describe.
  @override
  Widget build(BuildContext context) => FutureBuilder<List<MarkdownNodeStable>>(
    key: ValueKey(widget.text),
    future: _nodes,
    builder: (context, snapshot) {
      _gestures.beginFrame();
      try {
        final nodes = snapshot.data;
        return Text.rich(
          nodes == null
              ? TextSpan(text: widget.text)
              : buildMarkdownInlineSpannableFromMarkdownNodes(
                  context: context,
                  children: nodes,
                  textColor: widget.textColor,
                  baseStyle: widget.style,
                  gestures: _gestures,
                  // Table formulas align to the line center and need no dry
                  // alphabetic baseline during intrinsic column measurement.
                  inlineMathAlignment: PlaceholderAlignment.middle,
                ),
          textAlign: widget.textAlign,
          style: widget.style,
          strutStyle: StrutStyle.fromTextStyle(
            widget.style ?? const TextStyle(),
          ),
        );
      } finally {
        _gestures.endFrame();
      }
    },
  );
}

TextAlign _parseCellAlignment(String separatorCell) {
  final startsWithColon = separatorCell.startsWith(':');
  final endsWithColon = separatorCell.endsWith(':');
  if (startsWithColon && endsWithColon) {
    return TextAlign.center;
  }
  if (endsWithColon) {
    return TextAlign.right;
  }
  return TextAlign.left;
}
