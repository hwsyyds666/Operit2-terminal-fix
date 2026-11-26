// ignore_for_file: file_names

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../../core/proxy/generated/CoreProxyModels.g.dart';

/// Owns one chat's on-screen history. Core's generation history is separate.
class ChatTranscriptController {
  ChatTranscriptController({
    required this.readPage,
    required this.readMessage,
    this.readBodies,
    this.readToolOutput,
    required this.visibleTimestamp,
    required this.followLatest,
    required this.onChanged,
    required this.onError,
  });

  final Future<ChatTranscriptPage> Function(String, int?) readPage;
  final Future<ChatMessage?> Function(int) readMessage;
  final Future<String?> Function(int, int, String)? readToolOutput;
  final Future<List<ChatMessage>> Function(List<int>)? readBodies;
  final int? Function() visibleTimestamp;
  final bool Function() followLatest;
  final void Function() onChanged;
  final void Function(Object) onError;
  final locatorRevision = ValueNotifier<int>(0);

  final _rows = SplayTreeMap<int, ChatMessage>();
  final _pending = <ChatTranscriptChange>[];
  final _waiting = <int, (ChatMessage, Completer<ChatMessage?>)>{};
  bool _bodyScheduled = false;
  bool _active = true;

  void setActive(bool active) {
    _active = active;
    if (active) _scheduleBodies();
  }

  final _details = <int, (ChatMessage, Future<ChatMessage?>)>{};
  List<ChatMessage> messages = const [];
  bool hasOlder = false;
  bool hasNewer = false;
  bool _disposed = false;
  bool _needsRefresh = false;
  bool _ready = false;
  int? _sequence;
  Future<void>? _page;
  bool get loading => _page != null;

  void dispose() {
    _disposed = true;
    for (final (_, completer) in _waiting.values) {
      completer.complete(null);
    }
    _waiting.clear();
    _details.clear();
    locatorRevision.dispose();
  }

  void accept(List<ChatTranscriptChange> journal) {
    if (_disposed) return;
    final sequence = _sequence;
    if (sequence == null) {
      _sequence = journal.lastOrNull?.sequence ?? 0;
      unawaited(_refresh());
      return;
    }
    final changes = journal.where((change) => change.sequence > sequence);
    if (changes.isEmpty) return;
    final missedChanges = changes.first.sequence > sequence + 1;
    if (missedChanges) _needsRefresh = true;
    _sequence = changes.last.sequence;
    if (missedChanges || changes.any(_changesLocator)) {
      locatorRevision.value++;
    }
    _pending.addAll(changes);
    if (_pending.length > 48) {
      _pending.removeRange(0, _pending.length - 24);
      _needsRefresh = true;
    }
    if (loading) {
      if (_ready && _apply(changes)) {
        _trim(fromNewest: hasNewer);
        _publish();
      }
      return;
    }
    if (_consumeChanges()) {
      _trim(fromNewest: hasNewer);
      _publish();
    }
    if (_needsRefresh) unawaited(_refresh());
  }

  bool _changesLocator(ChatTranscriptChange change) {
    if (change.kind != 'upsert') return true;
    final message = change.message;
    if (message == null) return false;
    final previous = _rows[message.timestamp];
    return previous == null ||
        previous.isFavorite != message.isFavorite ||
        previous.sender != message.sender ||
        previous.displayMode != message.displayMode;
  }

  Future<void> _refresh() async {
    if (_disposed || loading) return;
    final anchor = followLatest() ? null : visibleTimestamp();
    _needsRefresh = false;
    try {
      await load(anchor == null ? 'latest' : 'around', anchor);
    } catch (error) {
      if (!_disposed) onError(error);
    }
  }

  Future<void> load(String direction, [int? target]) async {
    await _load(direction, target, requireTarget: false);
  }

  Future<bool> reveal(int timestamp) async {
    await _load('around', timestamp, requireTarget: true);
    return !_disposed && _rows.containsKey(timestamp);
  }

  Future<void> _load(
    String direction,
    int? target, {
    required bool requireTarget,
  }) async {
    while (_page != null) {
      try {
        await _page!;
      } catch (_) {
        // The requesting action owns presentation of its error.
      }
    }
    if (_disposed) return;
    final cursor = switch (direction) {
      'older' => _rows.firstKey(),
      'newer' => _rows.lastKey(),
      _ => target,
    };
    if (direction == 'older' && (!hasOlder || cursor == null) ||
        direction == 'newer' && (!hasNewer || cursor == null)) {
      return;
    }

    final task = _read(direction, cursor, requireTarget: requireTarget);
    _page = task;
    try {
      await task;
    } finally {
      _page = null;
      if (!_disposed && _needsRefresh) unawaited(_refresh());
    }
  }

  Future<void> _read(
    String direction,
    int? cursor, {
    required bool requireTarget,
  }) async {
    try {
      final page = await readPage(direction, cursor);
      if (_disposed) return;
      if (requireTarget &&
          !page.messages.any((message) => message.timestamp == cursor)) {
        if (_consumeChanges()) _publish();
        return;
      }
      if (direction == 'latest' || direction == 'around') {
        _rows.clear();
        hasOlder = page.hasOlder;
        hasNewer = page.hasNewer;
      } else if (direction == 'older') {
        hasOlder = page.hasOlder;
      } else {
        hasNewer = page.hasNewer;
      }
      for (final row in page.messages) {
        _rows[row.timestamp] = row;
      }
      _consumeChanges();
      _trim(fromNewest: direction == 'older');
      _ready = true;
      _publish();
    } catch (_) {
      if (!_disposed && _consumeChanges()) _publish();
      rethrow;
    }
  }

  bool _consumeChanges() {
    final changed = _apply(_pending);
    _pending.clear();
    return changed;
  }

  bool _apply(Iterable<ChatTranscriptChange> changes) {
    var changed = false;
    for (final change in changes) {
      final timestamp = change.timestamp;
      final message = change.message;
      switch (change.kind) {
        case 'upsert' when message != null:
          final first = _rows.firstKey();
          final last = _rows.lastKey();
          if (_rows.containsKey(message.timestamp) ||
              (first == null || message.timestamp >= first) &&
                  (!hasNewer || last == null || message.timestamp <= last)) {
            _rows[message.timestamp] = message;
            changed = true;
          }
        case 'remove':
          changed = _rows.remove(timestamp) != null || changed;
        case 'removeFrom' when timestamp != null:
          _rows.removeWhere((id, _) => id >= timestamp);
          hasNewer = false;
          changed = true;
        case 'reloadRow' when timestamp != null:
          final old = _rows[timestamp];
          if (old != null) unawaited(_reloadRow(old));
        case 'reset':
          _needsRefresh = true;
      }
    }
    if (_rows.isEmpty && (hasOlder || hasNewer)) _needsRefresh = true;
    return changed;
  }

  Future<void> _reloadRow(ChatMessage old) async {
    try {
      final row = await readMessage(old.timestamp);
      if (_disposed || !identical(_rows[old.timestamp], old)) return;
      _details.remove(old.timestamp);
      if (row == null) {
        _rows.remove(old.timestamp);
      } else {
        _rows[row.timestamp] = row;
      }
      _publish();
    } catch (error) {
      if (!_disposed) onError(error);
    }
  }

  void _trim({required bool fromNewest}) {
    final anchor = visibleTimestamp();
    while (_rows.length > 120) {
      final first = _rows.firstKey()!;
      final last = _rows.lastKey()!;
      final removeNewest = fromNewest ? last != anchor : first == anchor;
      final edge = removeNewest ? last : first;
      _rows.remove(edge);
      if (removeNewest) {
        hasNewer = true;
      } else {
        hasOlder = true;
      }
    }
  }

  void _publish() {
    if (!_ready) return;
    messages = List.unmodifiable(_rows.values);
    _details.removeWhere((id, entry) => !identical(entry.$1, _rows[id]));
    onChanged();
  }

  Future<ChatMessage?> hydrate(ChatMessage row) {
    final cached = _details.remove(row.timestamp);
    if (cached != null && identical(cached.$1, row)) {
      _details[row.timestamp] = cached;
      return cached.$2;
    }
    final previous = _waiting.remove(row.timestamp);
    previous?.$2.complete(null);
    final completer = Completer<ChatMessage?>();
    _waiting[row.timestamp] = (row, completer);
    _details[row.timestamp] = (row, completer.future);
    if (_details.length > 48) _details.remove(_details.keys.first);
    _scheduleBodies();
    return completer.future;
  }

  void _scheduleBodies() {
    if (_disposed || !_active || _bodyScheduled || _waiting.isEmpty) return;
    _bodyScheduled = true;
    scheduleMicrotask(_readBodies);
  }

  Future<void> _readBodies() async {
    try {
      if (!_active || _disposed) return;
      final pending = _waiting.keys.take(8).toList();
      final batch = <int, (ChatMessage, Completer<ChatMessage?>)>{};
      for (final timestamp in pending) {
        final entry = _waiting.remove(timestamp)!;
        if (identical(_rows[timestamp], entry.$1)) {
          batch[timestamp] = entry;
        } else {
          entry.$2.complete(null);
        }
      }
      if (batch.isEmpty) return;
      try {
        final timestamps = batch.keys.toList();
        final load = readBodies;
        final bodies = load != null
            ? await load(timestamps)
            : (await Future.wait(
                timestamps.map(readMessage),
              )).whereType<ChatMessage>();
        final byTimestamp = {for (final body in bodies) body.timestamp: body};
        for (final entry in batch.entries) {
          final (row, completer) = entry.value;
          final body = byTimestamp[entry.key];
          final current =
              !_disposed &&
              identical(_rows[entry.key], row) &&
              body?.selectedVariantIndex == row.selectedVariantIndex;
          // A remounted row can render immediately using its prepared body.
          if (current && identical(_details[entry.key]?.$2, completer.future)) {
            _details[entry.key] = (row, SynchronousFuture(body));
          }
          completer.complete(current ? body : null);
        }
      } catch (error, stackTrace) {
        for (final entry in batch.values) {
          entry.$2.completeError(error, stackTrace);
        }
      }
    } finally {
      _bodyScheduled = false;
      _scheduleBodies();
    }
  }

  /// Drops work for rows that left the viewport before their batch started.
  void releaseBody(ChatMessage row) {
    final waiting = _waiting[row.timestamp];
    if (waiting == null || !identical(waiting.$1, row)) return;
    _waiting.remove(row.timestamp);
    if (identical(_details[row.timestamp]?.$2, waiting.$2.future)) {
      _details.remove(row.timestamp);
    }
    waiting.$2.complete(null);
  }

  Future<ChatMessage?> retryBody(ChatMessage row) {
    _details.remove(row.timestamp);
    return hydrate(row);
  }
}

/// Limits native history preparation without delaying live content streams.
class TranscriptPreparationQueue {
  TranscriptPreparationQueue(this.limit);

  final int limit;
  final _pending = Queue<({void Function() run, void Function() cancel})>();
  int _running = 0;
  bool _disposed = false;

  Future<T?> run<T>(Future<T?> Function() work) {
    if (_disposed) return Future.value(null);
    final result = Completer<T?>();
    _pending.add((
      run: () {
        _running++;
        Future<T?>.sync(
          work,
        ).then(result.complete, onError: result.completeError).whenComplete(() {
          _running--;
          _drain();
        });
      },
      cancel: () => result.complete(null),
    ));
    _drain();
    return result.future;
  }

  void _drain() {
    while (!_disposed && _pending.isNotEmpty && _running < limit) {
      _pending.removeFirst().run();
    }
  }

  void dispose() {
    _disposed = true;
    while (_pending.isNotEmpty) {
      _pending.removeFirst().cancel();
    }
  }
}
