import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operit2/data/preferences/UserPreferencesManager.dart';
import 'package:operit2/ui/common/components/AdaptiveSidePanel.dart';
import 'package:operit2/ui/main/MainLayoutController.dart';
import 'package:operit2/ui/main/TopBarController.dart';
import 'package:operit2/ui/main/components/AppContent.dart';
import 'package:operit2/ui/main/navigation/AppNavigationModels.dart';
import 'package:operit2/ui/main/screens/OperitScreens.dart';
import 'package:operit2/ui/theme/OperitTheme.dart';

/// Checks workspace attachment above the toolbar without recreating the chat.
void main() {
  testWidgets(
    'returning from settings retains the chat draft and scroll position',
    (tester) async {
      final chat = RouteEntry(instanceId: 'chat', routeId: 'ai_chat');
      final settings = RouteEntry(instanceId: 'settings', routeId: 'settings');
      final router = AppRouterState(chat);
      final layout = MainLayoutController();
      final topBar = TopBarController();
      final scroll = ScrollController();
      addTearDown(router.dispose);
      addTearDown(layout.dispose);
      addTearDown(topBar.dispose);
      addTearDown(scroll.dispose);

      Future<void> show(RouteEntry entry, OperitScreen screen) async {
        router.resetTo(entry);
        await tester.pumpWidget(
          OperitTheme(
            initialThemePreferenceSnapshot:
                UserPreferencesManager.defaultThemePreferenceSnapshot,
            initialThemeIsReady: false,
            unconfiguredChildEnabled: true,
            hostInteractionHostsEnabled: false,
            child: MainLayoutScope(
              controller: layout,
              child: AppContent(
                routerState: router,
                currentScreen: screen,
                currentRouteEntry: entry,
                currentRouteTitle: entry.routeId,
                useTabletLayout: false,
                isTabletSidebarExpanded: false,
                canGoBack: false,
                enableNavigationAnimation: true,
                isNavigatingBack: false,
                topBarController: topBar,
                appBarEntries: const [],
                onGoBack: () {},
                onNavigationButtonPressed: () {},
                onAppBarEntrySelected: (_) {},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
      }

      final chatScreen = _RetainedChatRoute(scroll);
      await show(chat, chatScreen);
      final composer = find.byType(TextField);
      final state = tester.state(composer);
      await tester.enterText(composer, 'Draft in progress');
      scroll.jumpTo(400);
      await tester.pump();

      await show(settings, const _SettingsRoute());
      expect(composer.hitTestable(), findsNothing);
      await show(chat, chatScreen);
      expect(tester.state(composer), same(state));
      expect(find.text('Draft in progress'), findsOneWidget);
      expect(scroll.offset, 400);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final width in [402.0, 900.0]) {
    testWidgets('workspace covers the toolbar and retains chat at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 820);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      final layout = MainLayoutController();
      final topBar = TopBarController();
      final entry = RouteEntry(instanceId: 'chat', routeId: 'ai_chat');
      final router = AppRouterState(entry);
      final open = ValueNotifier<bool>(false);
      addTearDown(layout.dispose);
      addTearDown(topBar.dispose);
      addTearDown(router.dispose);
      addTearDown(open.dispose);
      await tester.pumpWidget(
        OperitTheme(
          initialThemePreferenceSnapshot:
              UserPreferencesManager.defaultThemePreferenceSnapshot,
          initialThemeIsReady: false,
          unconfiguredChildEnabled: true,
          hostInteractionHostsEnabled: false,
          child: MainLayoutScope(
            controller: layout,
            child: Scaffold(
              body: AppContent(
                routerState: router,
                currentScreen: const _ChatRoute(),
                currentRouteEntry: entry,
                currentRouteTitle: 'Chat title',
                useTabletLayout: width >= 600,
                isTabletSidebarExpanded: false,
                canGoBack: false,
                enableNavigationAnimation: false,
                isNavigatingBack: false,
                topBarController: topBar,
                appBarEntries: const [],
                onGoBack: () {},
                onNavigationButtonPressed: () {},
                onAppBarEntrySelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chat = tester.state(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      final owner = Object();
      layout.setAttachment(
        (_, child) => ValueListenableBuilder<bool>(
          valueListenable: open,
          builder: (context, value, _) => AdaptiveSidePanel(
            open: value,
            onOpenChanged: (value) => open.value = value,
            layout: SidePanelLayout.overlay,
            animate: false,
            panel: ColoredBox(
              key: const ValueKey('workspace-surface'),
              color: Theme.of(context).colorScheme.surface,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    tooltip: 'Close workspace',
                    onPressed: () => open.value = false,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ),
            ),
            child: child,
          ),
        ),
        owner: owner,
      );
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TextField)), same(chat));
      for (var cycle = 0; cycle < 2; cycle++) {
        open.value = true;
        await tester.pumpAndSettle();
        final surface = tester.getRect(
          find.byKey(const ValueKey('workspace-surface')),
        );
        expect(surface.top, 0);
        expect(surface.height, 820);
        expect(find.text('Chat title').hitTestable(), findsNothing);
        expect(
          tester.getRect(find.byTooltip('Close workspace')).top,
          greaterThanOrEqualTo(24),
        );
        await tester.tap(find.byTooltip('Close workspace'));
        await tester.pumpAndSettle();
        expect(open.value, isFalse);
        expect(find.text('Chat title').hitTestable(), findsOneWidget);
        expect(find.text('Keep this draft'), findsOneWidget);
        expect(tester.state(find.byType(TextField)), same(chat));
      }
      layout.clearAttachment(owner: owner);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(TextField)), same(chat));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

class _RetainedChatRoute extends AiChatScreenRoute {
  const _RetainedChatRoute(this.scroll);

  final ScrollController scroll;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: ListView(
          controller: scroll,
          children: const [SizedBox(height: 2000)],
        ),
      ),
      const TextField(),
    ],
  );
}

class _SettingsRoute extends OperitScreen {
  const _SettingsRoute() : super(routeTypeName: 'Settings');

  @override
  Widget build(BuildContext context) => const Center(child: Text('Settings'));
}

class _ChatRoute extends OperitScreen {
  /// Creates a chat fixture that owns its bottom system inset.
  const _ChatRoute()
    : super(routeTypeName: 'Chat', handlesBottomSafeArea: true);

  /// Builds retained editable content under the real main toolbar.
  @override
  Widget build(BuildContext context) => const TextField();
}
