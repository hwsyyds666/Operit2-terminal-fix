import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('Android chat renderer comparison', (tester) async {
    final messages = List.generate(
      1000,
      (i) => 'Message $i: 中文 Markdown and tool history',
    );
    final cells = List.generate(
      40,
      (row) => List.generate(4, (i) => '$row / $i'),
    );
    final output = List.generate(24, (i) => 'Output line $i').join('\n');
    final live = List.generate(49, (i) => ' live' * i);
    final scroll = ScrollController();
    final tokens = ValueNotifier(0);
    final toolOpen = ValueNotifier(false);
    final frames = <FrameTiming>[];
    void record(List<FrameTiming> samples) => frames.addAll(samples);
    addTearDown(scroll.dispose);
    addTearDown(tokens.dispose);
    addTearDown(toolOpen.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: CustomScrollView(
              controller: scroll,
              reverse: true,
              slivers: [
                SliverList.builder(
                  itemCount: messages.length,
                  itemBuilder: (context, i) => Padding(
                    key: ValueKey(i),
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (i == 0)
                          ValueListenableBuilder(
                            valueListenable: tokens,
                            builder: (context, count, _) =>
                                Text(messages[i] + live[count]),
                          )
                        else
                          Text(messages[i]),
                        if (i % 20 == 0)
                          for (final row in cells)
                            Row(
                              children: [
                                for (final cell in row)
                                  Expanded(child: Text(cell)),
                              ],
                            ),
                        if (i % 5 == 0)
                          ValueListenableBuilder(
                            valueListenable: toolOpen,
                            builder: (context, open, _) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Tool result'),
                                if (i == 0 && open) Text(output),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    binding.addTimingsCallback(record);
    try {
      await tester.runAsync(() async {
        for (var i = 0; i < 5; i++) {
          await scroll.animateTo(
            scroll.offset + 1600,
            duration: const Duration(milliseconds: 220),
            curve: Curves.linear,
          );
        }
        scroll.jumpTo(0);
        toolOpen.value = true;
        for (var i = 0; i < 48; i++) {
          tokens.value = i + 1;
          await Future<void>.delayed(const Duration(milliseconds: 32));
        }
        toolOpen.value = false;
        await Future<void>.delayed(const Duration(milliseconds: 650));
      });
    } finally {
      binding.removeTimingsCallback(record);
    }
    expect(frames, isNotEmpty);
    double p95(Iterable<int> micros) {
      final samples = micros.toList()..sort();
      return samples[(samples.length * .95).ceil() - 1] / 1000;
    }

    binding.reportData = {
      'frames': frames.length,
      'buildP95Ms': p95(
        frames.map((frame) => frame.buildDuration.inMicroseconds),
      ),
      'rasterP95Ms': p95(
        frames.map((frame) => frame.rasterDuration.inMicroseconds),
      ),
      'totalP95Ms': p95(frames.map((frame) => frame.totalSpan.inMicroseconds)),
    };
  });
}
