# Android chat renderer comparison

The two prototypes use the same prepared workload. Each displays 1,000 messages,
a four-column 40-row table every 20 messages and a collapsible tool result every
five. They scroll five times, return to the latest message, open its tool result
and append 48 increments. Run both on one physical phone with the same refresh
rate and text scaling. Measure the full production app separately with DevTools.

From the Flutter application directory run a profile integration test using
`integration_test/chat_render_benchmark_test.dart` and the existing
`test_driver/compose_performance_driver.dart`. The driver exports build, raster
and total frame percentiles.

Build the Android subproject as a standalone Release APK with Android SDK 36
using the repository Gradle wrapper and the `-p` project directory option.
Install and launch the benchmark activity. Its Window FrameMetrics samples
appear in logcat under the `ChatRenderBenchmark` tag. Use Android Frame Timeline
for a shared end-to-end jank measure across both renderers.
