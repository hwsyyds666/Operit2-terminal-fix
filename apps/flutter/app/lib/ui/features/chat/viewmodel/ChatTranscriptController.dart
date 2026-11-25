// ignore_for_file: file_names

import 'dart:async';
import 'dart:collection';

import '../../../../core/proxy/generated/CoreProxyModels.g.dart';

/// Owns one chat's on-screen history. Core's generation history is separate.
class ChatTranscriptController {
  ChatTranscriptController({
    required this.readPage,
    required this.readMessage,
    required this.visibleTimestamp,
    required this.followLatest,
    required this.onChanged,
    required this.onError,
  });

  final Future<ChatTranscriptPage> Function(String, int?) readPage;
  final Future<ChatMessage?> Function(int) readMessage;
  final int? Function() visibleTimestamp;
  final bool Function() followLatest;
  final void Function() onChanged;
  final void Function(Object) onError;

  final _rows = SplayTreeMap<int, ChatMessage>();
  final _pending = <ChatTranscriptChange>[];
  late final _preparation = TranscriptPreparationQueue(2);
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
    _preparation.dispose();
    _details.clear();
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
    if (changes.first.sequence > sequence + 1) _needsRefresh = true;
    _sequence = changes.last.sequence;
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
    final result = _preparation.run(() async {
      if (_disposed || !identical(_rows[row.timestamp], row)) return null;
      return readMessage(row.timestamp);
    });
    _details[row.timestamp] = (row, result);
    if (_details.length > 24) _details.remove(_details.keys.first);
    return result;
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
