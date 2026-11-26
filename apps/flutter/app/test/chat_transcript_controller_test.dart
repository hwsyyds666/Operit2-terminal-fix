import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operit2/core/proxy/generated/CoreProxyModels.g.dart';
import 'package:operit2/ui/common/markdown/TranscriptMarkdownViewport.dart';
import 'package:operit2/ui/features/chat/viewmodel/ChatTranscriptController.dart';

void main() {
  test(
    'keeps cursor paging bounded and goes directly to a distant message',
    () async {
      final controller = _controller();
      addTearDown(controller.dispose);
      await controller.load('latest');
      expect(controller.messages.first.timestamp, 981);
      expect(controller.messages.length, 20);
      for (var index = 0; index < 12; index++) {
        await controller.load('older');
        expect(controller.messages.length, lessThanOrEqualTo(120));
      }
      expect(controller.hasNewer, isTrue);
      await controller.load('around', 500);
      expect(controller.messages.first.timestamp, 491);
      expect(controller.messages[9].timestamp, 500);
      await controller.load('newer');
      expect(controller.messages.last.timestamp, 530);
      expect(controller.hasOlder, isTrue);
    },
  );

  test(
    'a committed user row arrives while an older page is outstanding',
    () async {
      final page = Completer<ChatTranscriptPage>();
      final controller = _controller(
        read: (direction, cursor) async {
          if (direction == 'older') return page.future;
          return _page(981, 1000);
        },
      );
      addTearDown(controller.dispose);
      controller.accept([]);
      await Future<void>.delayed(Duration.zero);
      final pending = controller.load('older');
      controller.accept([
        ChatTranscriptChange(
          sequence: 1,
          kind: 'upsert',
          timestamp: 1001,
          message: _message(1001),
        ),
      ]);
      expect(controller.messages.last.timestamp, 1001);
      expect(controller.locatorRevision.value, 1);
      page.complete(_page(961, 980));
      await pending;
      expect(controller.messages.last.timestamp, 1001);
      expect(controller.messages.map((m) => m.timestamp).toSet().length, 41);
      expect(controller.locatorRevision.value, 1);
    },
  );

  test(
    'failed paging keeps the current window and a retry can succeed',
    () async {
      var first = true;
      final controller = _controller(
        read: (direction, cursor) async {
          if (direction == 'latest') return _page(981, 1000);
          if (first) {
            first = false;
            throw StateError('temporary error');
          }
          return _page(961, 980);
        },
      );
      addTearDown(controller.dispose);
      await controller.load('latest');
      final initial = controller.messages;
      await expectLater(controller.load('older'), throwsStateError);
      expect(controller.messages, same(initial));
      await controller.load('older');
      expect(controller.messages.first.timestamp, 961);
    },
  );

  test('hydrates mounted rows in one batch and pauses while hidden', () async {
    final reads = <List<int>>[];
    final controller = ChatTranscriptController(
      readPage: (_, _) async => _page(981, 1000),
      readMessage: (_) async => throw StateError('single read'),
      readBodies: (ids) async {
        reads.add(ids);
        return ids.map(_message).toList();
      },
      visibleTimestamp: () => 1000,
      followLatest: () => true,
      onChanged: () {},
      onError: (error) => throw error,
    );
    addTearDown(controller.dispose);
    await controller.load('latest');
    controller.setActive(false);
    final work = controller.messages.reversed
        .take(6)
        .map(controller.hydrate)
        .toList();
    await Future<void>.delayed(Duration.zero);
    expect(reads, isEmpty);
    controller.setActive(true);
    expect((await Future.wait(work)).whereType<ChatMessage>(), hasLength(6));
    expect(reads.single, [1000, 999, 998, 997, 996, 995]);
  });

  testWidgets('long Markdown mounts blocks near the outer viewport', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final built = <int>{};
    final buildsPerBlock = <int, int>{};
    await tester.pumpWidget(
      MaterialApp(
        home: ListView(
          controller: scroll,
          children: [
            TranscriptMarkdownViewport(
              blockCount: 100,
              builder: (context, index) {
                built.add(index);
                buildsPerBlock.update(
                  index,
                  (count) => count + 1,
                  ifAbsent: () => 1,
                );
                return SizedBox(height: 64, child: Text('Block $index'));
              },
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(built.length, lessThan(25));
    expect(find.text('Block 0'), findsOneWidget);
    expect(find.text('Block 50'), findsNothing);
    for (var offset = 24.0; offset < 600; offset += 24) {
      scroll.jumpTo(offset);
      await tester.pump();
    }
    expect(buildsPerBlock.values, everyElement(1));
    scroll.jumpTo(50 * 64);
    await tester.pumpAndSettle();
    expect(find.text('Block 50'), findsOneWidget);
    expect(find.text('Block 0'), findsNothing);
    expect(built.length, lessThan(50));
    await tester.pumpWidget(const SizedBox());
  });
}

ChatTranscriptController _controller({
  Future<ChatTranscriptPage> Function(String, int?)? read,
}) => ChatTranscriptController(
  readPage:
      read ??
      (direction, cursor) async => switch (direction) {
        'older' => _page(cursor! - 20, cursor - 1),
        'newer' => _page(cursor! + 1, cursor + 20),
        'around' => _page(cursor! - 9, cursor + 10),
        _ => _page(981, 1000),
      },
  readMessage: (timestamp) async => _message(timestamp),
  visibleTimestamp: () => null,
  followLatest: () => true,
  onChanged: () {},
  onError: (error) => fail(error.toString()),
);

ChatTranscriptPage _page(int first, int last) => ChatTranscriptPage(
  messages: [for (var id = first; id <= last; id++) _message(id)],
  hasOlder: first > 1,
  hasNewer: last < 1000,
);

ChatMessage _message(int timestamp) => ChatMessage(
  sender: 'user',
  parts: const [],
  timestamp: timestamp,
  roleName: 'user',
  pluginExtensions: const {},
  selectedVariantIndex: 0,
  variantCount: 1,
  provider: '',
  modelName: '',
  inputTokens: 0,
  outputTokens: 0,
  cachedInputTokens: 0,
  sentAt: 0,
  outputDurationMs: 0,
  waitDurationMs: 0,
  completedAt: 0,
  displayMode: ChatMessageDisplayMode.normal,
  isFavorite: false,
  contentStream: null,
);
