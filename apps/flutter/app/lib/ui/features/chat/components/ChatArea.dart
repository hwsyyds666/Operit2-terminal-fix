// ignore_for_file: file_names

import 'package:operit2/l10n/generated/app_localizations.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../../common/ApiErrorText.dart';
import '../../../common/markdown/StreamMarkdownRenderer.dart';
import '../../../common/markdown/TranscriptMarkdownViewport.dart';
import '../../../common/markdown/MarkdownFileScope.dart';
import '../../../common/interactions/ChainedScrollController.dart';
import '../../../../core/host/AppToastController.dart';
import '../../../../core/proxy/generated/CoreProxyClients.g.dart';
import '../../../../data/preferences/UserPreferencesManager.dart';
import '../../../theme/OperitTheme.dart';
import '../viewmodel/ChatViewModel.dart';
import '../viewmodel/ChatTranscriptController.dart';
import 'ChatLayoutMetrics.dart';
import 'ChatMessageExtent.dart';
import 'MessageContextMenu.dart';
import 'MessageCopyPreview.dart';
import 'ChatScrollNavigator.dart';
import 'NewChatIntro.dart';
import 'style/ThemedChatMessage.dart';
import '../../../common/contributions/EmbeddedPluginSurfaceCatalog.dart';
import 'ChatMessageSlotHost.dart';
import 'TransformedChatMessage.dart';

const Duration _navigatorHideDelay = Duration(milliseconds: 1200);
const Duration _viewportResizeSettleDelay = Duration(milliseconds: 120);
const Duration _bottomFollowDuration = Duration(milliseconds: 240);
const double _bottomFollowPositionTolerance = 1;

class ChatArea extends StatefulWidget {
  const ChatArea({
    super.key,
    required this.messages,
    this.transcript,
    required this.isLoading,
    required this.errorMessage,
    required this.scrollController,
    required this.currentChatId,
    this.fileDirectory,
    required this.identityAvatarUri,
    this.onIdentityTap,
    required this.clients,
    required this.packageManager,
    required this.autoScrollToBottomListenable,
    required this.hasOlderDisplayHistory,
    required this.hasNewerDisplayHistory,
    required this.isLoadingDisplayWindow,
    this.messageNavigation,
    required this.loadLocatorEntries,
    required this.onRevealMessageForLocator,
    required this.onAutoScrollToBottomChanged,
    required this.onLoadOlderDisplayWindow,
    required this.onLoadNewerDisplayWindow,
    required this.onShowLatestDisplayWindow,
    required this.onToggleFavoriteMessage,
    required this.onDeleteMessage,
    required this.onDeleteMessagesFrom,
    required this.onDeleteMessageVariant,
    required this.onSelectMessageVariant,
    required this.onRollbackToMessage,
    required this.onSelectMessageToEdit,
    required this.onRegenerateMessage,
    required this.onInsertSummary,
    required this.onCreateBranch,
    required this.onReplyToMessage,
    required this.onPlayVoice,
    required this.onToggleMultiSelectMode,
    required this.onToggleMessageSelection,
    required this.onRefreshRequested,
    required this.bottomContentInset,
    this.splitMarkdownContent,
    this.isMultiSelectMode = false,
    this.selectedMessageTimestamps = const <int>{},
  });

  final List<ChatUiMessage> messages;
  final ChatTranscriptController? transcript;
  final bool isLoading;
  final String? errorMessage;
  final ScrollController scrollController;
  final String? currentChatId;
  final String? fileDirectory;
  final String? identityAvatarUri;
  final VoidCallback? onIdentityTap;
  final GeneratedCoreProxyClients clients;
  final GeneratedApplicationPackageManagerCoreProxy packageManager;
  final ValueListenable<bool> autoScrollToBottomListenable;
  final bool hasOlderDisplayHistory;
  final bool hasNewerDisplayHistory;
  final bool isLoadingDisplayWindow;
  final ChatMessageNavigationController? messageNavigation;
  final LoadMessageLocatorEntries loadLocatorEntries;
  final RevealMessageForLocator onRevealMessageForLocator;
  final ValueChanged<bool> onAutoScrollToBottomChanged;
  final Future<void> Function() onLoadOlderDisplayWindow;
  final Future<void> Function() onLoadNewerDisplayWindow;
  final Future<void> Function() onShowLatestDisplayWindow;
  final ToggleFavoriteMessage onToggleFavoriteMessage;
  final MessageTimestampAction onDeleteMessage;
  final MessageTimestampBoolAction onDeleteMessagesFrom;
  final MessageVariantAction onDeleteMessageVariant;
  final MessageVariantAction onSelectMessageVariant;
  final MessageTimestampSelectionAction onRollbackToMessage;
  final MessageSelectionAction onSelectMessageToEdit;
  final MessageTimestampAction onRegenerateMessage;
  final ValueChanged<ChatUiMessage> onInsertSummary;
  final MessageTimestampAction onCreateBranch;
  final ValueChanged<ChatUiMessage> onReplyToMessage;
  final MessageVoiceAction onPlayVoice;
  final MessageTimestampSelectionAction onToggleMultiSelectMode;
  final MessageTimestampSelectionAction onToggleMessageSelection;
  final Future<void> Function() onRefreshRequested;
  final double bottomContentInset;
  final MarkdownCopySplitter? splitMarkdownContent;
  final bool isMultiSelectMode;
  final Set<int> selectedMessageTimestamps;

  @override
  State<ChatArea> createState() => _ChatAreaState();
}

class _ChatAreaState extends State<ChatArea>
    with SingleTickerProviderStateMixin {
  final GlobalKey _viewportKey = GlobalKey();
  final Map<int, GlobalKey> _messageKeys = <int, GlobalKey>{};
  final Map<int, Object> _mountedRows = <int, Object>{};
  final Map<Key, ChatMessageExtent> _rowExtents = <Key, ChatMessageExtent>{};
  final ValueNotifier<Map<int, ChatScrollMessageAnchor>>
  _messageAnchorsNotifier = ValueNotifier<Map<int, ChatScrollMessageAnchor>>(
    const <int, ChatScrollMessageAnchor>{},
  );
  final ValueNotifier<bool> _showNavigatorChipNotifier = ValueNotifier<bool>(
    false,
  );
  final Map<int, _CachedMessageRow> _messageRowCache =
      <int, _CachedMessageRow>{};
  late final ValueNotifier<bool> _chatBusyNotifier;
  late EmbeddedPluginSurfaceCatalog _messageContributions;
  late MessageTransformCache _messageTransforms;
  TranscriptPreparationQueue _markdownPreparation = TranscriptPreparationQueue(
    2,
  );
  Timer? _navigatorHideTimer;
  Timer? _viewportResizeTimer;
  bool _userScrollSessionActive = false;
  ScrollDirection _userScrollDirection = ScrollDirection.idle;
  final Set<int> _activeUserScrollPointers = <int>{};
  bool _messageAnchorCollectionScheduled = false;
  double _viewportHeight = 0;
  final ValueNotifier<double> _viewportHeightNotifier = ValueNotifier<double>(
    0,
  );
  double _scrollViewportDimension = 0;

  /// Uses the scheduler timeline shared by layout, animation and test frames.
  int get _bottomFollowNowMicroseconds =>
      SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds;
  int? _bottomFollowDeadlineMicroseconds;
  late final Ticker _bottomFollowTicker;
  int? _bottomFollowLastFrameMicroseconds;
  bool _bottomFollowCompleting = false;
  double? _lastScrollMaxExtent;
  int? _pendingJumpToMessageTimestamp;
  bool _pendingScrollToBottom = false;
  int _messageNavigationGeneration = 0;
  int? _layoutAnchorTimestamp;
  bool _layoutAnchorAtBottom = false;
  final GlobalKey _leadingKey = GlobalKey();
  final Map<int, int> _messageIndices = {};
  List<({double height, int count})>? _measuredPrefix;
  ChatScrollMessageAnchor? _visibleAnchor;
  double? _rebaseOffset;
  double get _leadingScrollExtent =>
      (_leadingKey.currentContext?.findRenderObject() as RenderSliver?)
          ?.geometry
          ?.scrollExtent ??
      0;
  double _layoutOriginTopPadding = 16;
  bool _initialLayoutOriginChosen = false;
  ScrollDirection _historyLoadDirection = ScrollDirection.idle;
  bool _historyLoadScheduled = false;
  Object? _historyLoadRequest;
  int? _requestedOlderBoundary;
  int? _requestedNewerBoundary;
  Key _scrollLayoutKey = UniqueKey();
  static const _centerSliverKey = ValueKey<String>('chat-message-center');
  late final _ChatLayoutScrollController _layoutScrollController;

  /// Initializes the frame-driven live-output follower.
  @override
  void initState() {
    super.initState();
    _messageTransforms = MessageTransformCache(widget.clients);
    _messageTransforms.bindChat(widget.currentChatId);
    _messageContributions = EmbeddedPluginSurfaceCatalog(
      clients: widget.clients,
      surfaces: const {'chat_message_after'},
    );
    _chatBusyNotifier = ValueNotifier<bool>(widget.isLoading);
    _layoutScrollController = _ChatLayoutScrollController(
      delegate: widget.scrollController,
      shouldAlignBottom: _shouldAlignBottomDuringLayout,
      shouldInitiallyAlignBottom: _ownsBottomScroll,
      hasBottomLayoutOrigin: () => _layoutAnchorAtBottom,
      leadingScrollExtent: () => _leadingScrollExtent,
      layoutOriginTopPadding: () => _layoutOriginTopPadding,
      viewportCorrection: _measureAnchorShift,
      initialOffset: () {
        final offset = _rebaseOffset;
        _rebaseOffset = null;
        return offset;
      },
    );
    _bottomFollowTicker = createTicker(_tickBottomFollow);
    _indexMessages();
  }

  /// Updates localized declarations without opening a catalog per transcript row.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messageContributions.setLanguage(
      Localizations.localeOf(context).languageCode,
    );
  }

  /// Binds message actions to the mounted chat and exact answer revision, not plugin-supplied ids.
  Future<void> _handleMessageContribution(
    String chatId,
    ChatUiMessage message,
    EmbeddedPluginSurfaceEntry entry,
    Object? value,
  ) async {
    if (!mounted || widget.currentChatId != chatId) return;
    final current = widget.messages.firstWhereOrNull(
      (item) => item.timestamp == message.timestamp,
    );
    if (current == null ||
        current.selectedVariantIndex != message.selectedVariantIndex) {
      return;
    }
    if (!_messageContributions.entries.any(
      (item) => item.mountIdentity == entry.mountIdentity,
    )) {
      return;
    }
    if (value is Map && value['type'] == 'toolpkg.message.rollback') {
      widget.onRollbackToMessage(message.timestamp);
    }
  }

  /// Builds the scrollable message area and its navigation overlay.
  @override
  Widget build(BuildContext context) {
    return _buildTranscript(context);
  }

  /// Prepares nearby rows while keeping distant history unmounted.
  Widget _buildTranscript(BuildContext context) {
    final horizontalInset = OperitTheme.of(context)
        .themePreferenceSnapshot.chatContentHorizontalPadding;
    final showLoadingIndicator = _shouldShowLoadingIndicator();
    final itemCount =
        widget.messages.length +
        (showLoadingIndicator || widget.errorMessage != null ? 1 : 0);

    if (itemCount == 0) {
      _disposeRowExtents();
      return ValueListenableBuilder<bool>(
        valueListenable: newChatIntroActive,
        builder: (context, introActive, _) =>
            _EmptyChatArea(showMark: !introActive),
      );
    }

    // Start at the tail instead of laying out from the oldest row and then
    // chasing an estimated maxScrollExtent. Those intermediate layouts mount
    // offscreen rows and start their Markdown requests before discarding them.
    // Initial origin also applies to live conversations: the follower owns
    // subsequent growth, but opening a stream must not walk older rows first.
    // Keep this origin stable as messages arrive or older history is loaded.
    if (!_initialLayoutOriginChosen && widget.messages.isNotEmpty) {
      _initialLayoutOriginChosen = true;
      if (_layoutAnchorTimestamp == null &&
          _ownsBottomScroll() &&
          widget.messages.length > 1) {
        _layoutAnchorTimestamp = widget.messages.last.timestamp;
        _layoutAnchorAtBottom = true;
      }
      _layoutAnchorTimestamp ??= widget.messages.first.timestamp;
    }
    final centerIndex = _messageIndices[_layoutAnchorTimestamp] ?? 0;
    _layoutOriginTopPadding = centerIndex == 0 ? 16 : 0;
    // A sidebar width animation changes constraints, not message data. Reuse
    // this viewport so LayoutBuilder does not recreate the scroll view's delegate and
    // rebuild all visible rows on every animation frame.
    final viewport = Stack(
      key: _viewportKey,
      children: <Widget>[
        NotificationListener<SizeChangedLayoutNotification>(
          onNotification: _handleSizeChangedLayoutNotification,
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: _handleScrollMetricsNotification,
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: Listener(
                onPointerDown: _handleUserPointerStart,
                onPointerUp: _handleUserPointerEnd,
                onPointerCancel: _handleUserPointerEnd,
                onPointerSignal: _handleHistoryPointerSignal,
                onPointerPanZoomStart: _handleUserPointerStart,
                onPointerPanZoomEnd: _handleUserPointerEnd,
                child: CustomScrollView(
                  key: _scrollLayoutKey,
                  controller: _layoutScrollController,
                  // Projection and Markdown parsing both cross the async bridge.
                  // Prepare one screen on either side before bubbles become visible,
                  // with a cap so tall desktop windows do not mount whole histories.
                  cacheExtent: math.min(
                    MediaQuery.sizeOf(context).height,
                    1200,
                  ),
                  // Chat history should stop hard at its boundaries. The
                  // platform default can use bouncing physics, which lets the
                  // transcript move past the bottom and snap back on release.
                  physics: const ClampingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  center: _centerSliverKey,
                  // A tail origin must allow the preceding history to fill the
                  // viewport even when the final message is shorter than it.
                  anchor: _layoutAnchorAtBottom ? 1 : 0,
                  slivers: [
                    if (centerIndex > 0)
                      SliverPadding(
                        key: _leadingKey,
                        padding: EdgeInsets.fromLTRB(horizontalInset, 16, horizontalInset, 0),
                        sliver: SliverList(
                          delegate: _TranscriptSliverDelegate(
                            (context, index) => _buildListRow(
                              centerIndex - index - 1,
                              itemCount,
                            ),
                            childCount: centerIndex,
                            estimateTail: (last, mean) => _estimateRange(
                              0,
                              centerIndex - last - 1,
                              mean,
                              itemCount,
                            ),
                            findChildIndexCallback: (key) {
                              final index = _findRowIndex(key, itemCount);
                              return index != null && index < centerIndex
                                  ? centerIndex - index - 1
                                  : null;
                            },
                          ),
                        ),
                      ),
                    SliverPadding(
                      key: _centerSliverKey,
                      padding: EdgeInsets.fromLTRB(
                        horizontalInset,
                        _layoutOriginTopPadding,
                        horizontalInset,
                        16 + widget.bottomContentInset,
                      ),
                      sliver: SliverList(
                        delegate: _TranscriptSliverDelegate(
                          (context, index) =>
                              _buildListRow(centerIndex + index, itemCount),
                          childCount: itemCount - centerIndex,
                          estimateTail: (last, mean) => _estimateRange(
                            centerIndex + last + 1,
                            itemCount,
                            mean,
                            itemCount,
                          ),
                          findChildIndexCallback: (key) {
                            final index = _findRowIndex(key, itemCount);
                            return index != null && index >= centerIndex
                                ? index - centerIndex
                                : null;
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            _messageAnchorsNotifier,
            _viewportHeightNotifier,
            widget.scrollController,
          ]),
          builder: (context, _) {
            final messageAnchors = _messageAnchorsNotifier.value;
            return ValueListenableBuilder<bool>(
              valueListenable: widget.autoScrollToBottomListenable,
              builder: (context, autoScrollToBottom, _) {
                return ValueListenableBuilder<bool>(
                  valueListenable: _showNavigatorChipNotifier,
                  builder: (context, showNavigatorChip, _) {
                    return ValueListenableBuilder<bool>(
                      valueListenable:
                          UserPreferencesManager.chatScrollNavigatorOnLeft,
                      builder: (context, onLeft, _) => ChatScrollNavigator(
                        onLeft: onLeft,
                        messages: widget.messages,
                        currentChatId: widget.currentChatId,
                        scrollController: widget.scrollController,
                        messageAnchors: messageAnchors,
                        viewportHeight: _viewportHeight,
                        autoScrollToBottom: autoScrollToBottom,
                        hasNewerDisplayHistory: widget.hasNewerDisplayHistory,
                        messageNavigation: widget.messageNavigation,
                        loadLocatorEntries: widget.loadLocatorEntries,
                        onRequestLatestMessages:
                            widget.onShowLatestDisplayWindow,
                        onAutoScrollToBottomChanged:
                            widget.onAutoScrollToBottomChanged,
                        onJumpToMessageTimestamp: _jumpToMessageTimestamp,
                        onJumpToMessage: _jumpToMessageIndex,
                        onToggleFavoriteMessage: widget.onToggleFavoriteMessage,
                        onRequestScrollToBottom: _scrollToBottomFromNavigator,
                        showNavigatorChip: showNavigatorChip,
                        onNavigatorChipHidden: () {
                          _showNavigatorChipNotifier.value = false;
                          _userScrollSessionActive = false;
                        },
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );

    return ChainedScrollScope(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportHeight = constraints.maxHeight;
          if (_viewportHeight != viewportHeight) {
            _viewportHeight = viewportHeight;
            _scheduleViewportResizeUpdate();
          }
          return viewport;
        },
      ),
    );
  }

  /// Builds one chronological row shared by both growth directions.
  Widget _buildListRow(int index, int itemCount) {
    late final Widget child;
    var observesLiveBottomGrowth = false;
    int? timestamp;
    if (index < widget.messages.length) {
      final message = widget.messages[index];
      timestamp = message.timestamp;
      final transcript = widget.transcript;
      child = transcript == null
          ? _messageRowFor(index, message)
          : _TranscriptMessageBody(
              message: message,
              transcript: transcript,
              builder: (body) => _messageRowFor(index, body),
            );
      if (index == widget.messages.length - 1 && _isStreamingMessage(index)) {
        observesLiveBottomGrowth = true;
      }
    } else if (widget.errorMessage != null) {
      child = _StatusMessage(text: widget.errorMessage!, isError: true);
    } else {
      child = const Padding(
        padding: EdgeInsets.only(left: 16, top: 2, bottom: 2),
        child: StreamingCursor(),
      );
    }
    final rowKey = _rowKeyForIndex(index);
    final extentKey = _extentKeyForIndex(index);
    final extent = _rowExtents.putIfAbsent(
      extentKey,
      () => ChatMessageExtent(
        onLayoutHeightChanged: () => _measuredPrefix = null,
      ),
    );
    extent.updateTrailingSpacing(index == itemCount - 1 ? 0 : 8);
    final content = Padding(
      padding: EdgeInsets.only(bottom: index == itemCount - 1 ? 0 : 8),
      child: SizeChangedLayoutNotifier(
        key: rowKey,
        child: _LiveBottomStreamSizeObserver(
          observesGrowth: observesLiveBottomGrowth,
          onSizeGrown: _scheduleBottomFollow,
          child: _ChatAreaContentColumn(child: child),
        ),
      ),
    );
    return observeChatMessageExtent(
      key: extentKey,
      extent: extent,
      child: timestamp == null
          ? content
          : _TranscriptRowRegistration(
              timestamp: timestamp,
              rows: _mountedRows,
              child: content,
            ),
    );
  }

  /// Keeps the chat bottom aligned while the viewport changes size.
  bool _handleScrollMetricsNotification(
    ScrollMetricsNotification notification,
  ) {
    if (notification.depth != 0) {
      return false;
    }
    final maxScrollExtentDelta = _updateLastScrollMaxExtent(
      notification.metrics.maxScrollExtent,
    );
    final viewportDimension = notification.metrics.viewportDimension;
    _handleBottomStreamExtentChange(maxScrollExtentDelta);
    _scheduleHistoryLoad(_historyLoadDirection);
    if (_scrollViewportDimension != viewportDimension) {
      _scrollViewportDimension = viewportDimension;
      _scheduleViewportResizeUpdate();
      return false;
    }
    _scheduleMessageAnchorCollection();
    return false;
  }

  /// Updates the remembered bottom extent and returns the measured delta.
  double _updateLastScrollMaxExtent(double maxScrollExtent) {
    final previousMaxScrollExtent = _lastScrollMaxExtent;
    _lastScrollMaxExtent = maxScrollExtent;
    return previousMaxScrollExtent == null
        ? 0
        : maxScrollExtent - previousMaxScrollExtent;
  }

  /// Follows async transcript growth even before the live tail emits any text.
  void _handleBottomStreamExtentChange(double maxScrollExtentDelta) {
    if (_isCompletingBottomFollow() ||
        (_hasLiveBottomStream() &&
            maxScrollExtentDelta > _bottomFollowPositionTolerance)) {
      _scheduleBottomFollow(maxScrollExtentDelta);
    }
  }

  /// Refreshes navigation geometry after asynchronously rendered content changes.
  bool _handleSizeChangedLayoutNotification(
    SizeChangedLayoutNotification notification,
  ) {
    _scheduleMessageAnchorCollection();
    return false;
  }

  /// Updates navigator anchors for active user scroll sessions only.
  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) {
      return false;
    }
    if (notification is UserScrollNotification) {
      if (notification.direction != ScrollDirection.idle) {
        _scheduleHistoryLoad(notification.direction);
        _clearPendingMessageJump();
        _userScrollSessionActive = true;
        _userScrollDirection = notification.direction;
        if (!_showNavigatorChipNotifier.value) {
          _showNavigatorChipNotifier.value = true;
        }
        if (widget.autoScrollToBottomListenable.value) {
          _stopBottomFollow();
          widget.onAutoScrollToBottomChanged(false);
        }
      } else {
        if (_userScrollSessionActive &&
            _userScrollDirection == ScrollDirection.reverse &&
            _isAtBottom(notification.metrics) &&
            !widget.autoScrollToBottomListenable.value) {
          widget.onAutoScrollToBottomChanged(true);
        }
        _userScrollDirection = ScrollDirection.idle;
        if (_userScrollSessionActive) {
          _scheduleNavigatorHide();
        }
      }
    }

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta;
      if (_userScrollSessionActive && delta != null && delta != 0) {
        _scheduleHistoryLoad(
          delta < 0 ? ScrollDirection.forward : ScrollDirection.reverse,
        );
      }
      if (notification.dragDetails != null) {
        if (!_showNavigatorChipNotifier.value) {
          _userScrollSessionActive = true;
          _showNavigatorChipNotifier.value = true;
        }
        _scheduleNavigatorHide();
      }
      if (_userScrollSessionActive) {
        _scheduleMessageAnchorCollection();
      }
      if (_userScrollDirection == ScrollDirection.reverse &&
          _isAtBottom(notification.metrics) &&
          !widget.autoScrollToBottomListenable.value) {
        widget.onAutoScrollToBottomChanged(true);
      }
    }
    if (notification is OverscrollNotification &&
        _userScrollSessionActive &&
        notification.overscroll != 0) {
      _scheduleHistoryLoad(
        notification.overscroll < 0
            ? ScrollDirection.forward
            : ScrollDirection.reverse,
      );
    }
    return false;
  }

  /// Lets mouse-wheel input request history even when the current window fits the viewport.
  void _handleHistoryPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
      _scheduleHistoryLoad(
        event.scrollDelta.dy < 0
            ? ScrollDirection.forward
            : ScrollDirection.reverse,
      );
    }
  }

  /// Coalesces user-directed boundary checks after the current layout finishes.
  void _scheduleHistoryLoad(ScrollDirection direction) {
    _historyLoadDirection = direction;
    if (direction == ScrollDirection.idle || _historyLoadScheduled) return;
    _historyLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _historyLoadScheduled = false;
      if (mounted) unawaited(_loadHistoryNearEdge());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Prefetches one small body batch in the user's scroll direction without adding transcript UI.
  Future<void> _loadHistoryNearEdge() async {
    final scroll = widget.scrollController;
    if (_historyLoadDirection == ScrollDirection.idle ||
        _historyLoadRequest != null ||
        widget.isLoadingDisplayWindow ||
        _pendingJumpToMessageTimestamp != null ||
        _pendingScrollToBottom ||
        widget.messages.isEmpty ||
        !scroll.hasClients ||
        scroll.positions.length != 1) {
      return;
    }
    final older = _historyLoadDirection == ScrollDirection.forward;
    if (older
        ? !widget.hasOlderDisplayHistory
        : !widget.hasNewerDisplayHistory) {
      return;
    }
    final position = scroll.position;
    final distance = older ? position.extentBefore : position.extentAfter;
    final prefetchDistance = math.min(position.viewportDimension * 0.75, 400.0);
    if (distance > prefetchDistance) return;
    final boundary = older
        ? widget.messages.first.timestamp
        : widget.messages.last.timestamp;
    if (boundary ==
        (older ? _requestedOlderBoundary : _requestedNewerBoundary)) {
      return;
    }
    if (older) {
      _requestedOlderBoundary = boundary;
    } else {
      _requestedNewerBoundary = boundary;
    }
    final request = Object();
    _historyLoadRequest = request;
    _stopBottomFollow();
    widget.onAutoScrollToBottomChanged(false);
    try {
      await (older
          ? widget.onLoadOlderDisplayWindow()
          : widget.onLoadNewerDisplayWindow());
    } catch (error, stack) {
      if (mounted && identical(_historyLoadRequest, request)) {
        _historyLoadDirection = ScrollDirection.idle;
        if (older) {
          _requestedOlderBoundary = null;
        } else {
          _requestedNewerBoundary = null;
        }
        if (widget.transcript != null) {
          final chatId = widget.currentChatId;
          AppToastController.instance.show(
            error.toString(),
            actionLabel: AppLocalizations.of(context)!.retry,
            onAction: () {
              if (mounted && widget.currentChatId == chatId) {
                _scheduleHistoryLoad(
                  older ? ScrollDirection.forward : ScrollDirection.reverse,
                );
              }
            },
          );
          return;
        }
      }
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'chat history',
          context: ErrorDescription('while loading history during scrolling'),
        ),
      );
    } finally {
      if (mounted && identical(_historyLoadRequest, request)) {
        _historyLoadRequest = null;
        _scheduleHistoryLoad(_historyLoadDirection);
      }
    }
  }

  /// Coalesces a burst of viewport-size changes into one anchor refresh.
  void _scheduleViewportResizeUpdate() {
    _viewportResizeTimer?.cancel();
    _viewportResizeTimer = Timer(_viewportResizeSettleDelay, () {
      _viewportResizeTimer = null;
      if (!mounted) {
        return;
      }
      _viewportHeightNotifier.value = _viewportHeight;
      _scheduleMessageAnchorCollection();
    });
  }

  /// Pauses automatic jumps before a touch or trackpad drag takes ownership.
  /// Trackpads send pan/zoom events rather than pointer-down/up events; a
  /// follower jumpTo between pan start and drag acceptance cancels their hold.
  void _handleUserPointerStart(PointerEvent event) {
    _clearPendingMessageJump();
    _activeUserScrollPointers.add(event.pointer);
    if (_bottomFollowTicker.isActive) {
      _bottomFollowLastFrameMicroseconds = _bottomFollowNowMicroseconds;
    }
  }

  /// Resumes follow scheduling only after all touch/trackpad gestures end.
  void _handleUserPointerEnd(PointerEvent event) {
    _activeUserScrollPointers.remove(event.pointer);
    if (_activeUserScrollPointers.isNotEmpty) {
      if (_bottomFollowTicker.isActive) {
        _bottomFollowLastFrameMicroseconds = _bottomFollowNowMicroseconds;
      }
      return;
    }
    if (_bottomFollowTicker.isActive) {
      _bottomFollowLastFrameMicroseconds = _bottomFollowNowMicroseconds;
      return;
    }
    if (!widget.autoScrollToBottomListenable.value) {
      return;
    }
    _scheduleBottomFollow(0);
  }

  /// Schedules one post-layout collection of message navigation anchors.
  void _scheduleMessageAnchorCollection() {
    if (_messageAnchorCollectionScheduled) {
      return;
    }
    _messageAnchorCollectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _messageAnchorCollectionScheduled = false;
      if (mounted) {
        _collectMessageAnchors();
      }
    });
  }

  /// Hides the scroll navigator after the active user scroll session settles.
  void _scheduleNavigatorHide() {
    _navigatorHideTimer?.cancel();
    _navigatorHideTimer = Timer(_navigatorHideDelay, () {
      _navigatorHideTimer = null;
      if (!mounted) {
        return;
      }
      final scrollController = widget.scrollController;
      if (scrollController.hasClients &&
          scrollController.positions.length == 1 &&
          scrollController.position.isScrollingNotifier.value) {
        _scheduleNavigatorHide();
        return;
      }
      _showNavigatorChipNotifier.value = false;
      _userScrollSessionActive = false;
    });
  }

  /// Reports whether the settled display window has reached the latest bottom.
  bool _isAtBottom(ScrollMetrics metrics) {
    return !widget.hasNewerDisplayHistory &&
        !widget.isLoadingDisplayWindow &&
        metrics.pixels >= metrics.maxScrollExtent - 2;
  }

  /// Reports whether the viewport currently belongs to automatic bottom following.
  bool _ownsBottomScroll() {
    return mounted &&
        _activeUserScrollPointers.isEmpty &&
        widget.autoScrollToBottomListenable.value &&
        !widget.hasNewerDisplayHistory &&
        !widget.isLoadingDisplayWindow;
  }

  /// Preserves visible message geometry while the user owns transcript scrolling.
  bool _shouldPreserveManualViewport() {
    return !widget.autoScrollToBottomListenable.value ||
        _activeUserScrollPointers.isNotEmpty;
  }

  /// Aligns static history before paint without taking over live output following.
  bool _shouldAlignBottomDuringLayout() {
    return _ownsBottomScroll() &&
        !_hasLiveBottomStream() &&
        !_isCompletingBottomFollow();
  }

  /// Records measured live growth and starts the frame-driven bottom follower.
  void _scheduleBottomFollow(double heightDelta) {
    final nowMicroseconds = _bottomFollowNowMicroseconds;
    if (!mounted ||
        !_shouldRunBottomFollow() ||
        !widget.autoScrollToBottomListenable.value ||
        widget.hasNewerDisplayHistory ||
        widget.isLoadingDisplayWindow ||
        !widget.scrollController.hasClients) {
      return;
    }
    if (heightDelta > _bottomFollowPositionTolerance ||
        !_bottomFollowTicker.isActive) {
      _bottomFollowDeadlineMicroseconds =
          nowMicroseconds + _bottomFollowDuration.inMicroseconds;
    }
    if (!_bottomFollowTicker.isActive) {
      _bottomFollowLastFrameMicroseconds = nowMicroseconds;
      _bottomFollowTicker.start();
    }
  }

  /// Follows measured growth and settles within a bounded animation window.
  void _tickBottomFollow(Duration elapsed) {
    final nowMicroseconds = _bottomFollowNowMicroseconds;
    if (!mounted ||
        !_shouldRunBottomFollow() ||
        !widget.autoScrollToBottomListenable.value ||
        widget.hasNewerDisplayHistory ||
        widget.isLoadingDisplayWindow ||
        !widget.scrollController.hasClients ||
        widget.scrollController.positions.length != 1 ||
        !widget.scrollController.position.hasPixels) {
      _stopBottomFollow();
      return;
    }
    if (_activeUserScrollPointers.isNotEmpty) {
      _stopBottomFollow();
      return;
    }
    final previousMicroseconds = _bottomFollowLastFrameMicroseconds!;
    _bottomFollowLastFrameMicroseconds = nowMicroseconds;

    final position = widget.scrollController.position;
    final gap = position.maxScrollExtent - position.pixels;
    if (gap <= _bottomFollowPositionTolerance) {
      _stopBottomFollow();
      return;
    }
    final deadline = _bottomFollowDeadlineMicroseconds ?? nowMicroseconds;
    final remaining = deadline - previousMicroseconds;
    final elapsed = nowMicroseconds - previousMicroseconds;
    final fraction = remaining <= 0
        ? 1.0
        : (elapsed / remaining).clamp(0.0, 1.0);
    final target = (position.pixels + gap * fraction).clamp(
      position.pixels,
      position.maxScrollExtent,
    );
    if (target != position.pixels) widget.scrollController.jumpTo(target);
    if (nowMicroseconds >= deadline) _stopBottomFollow();
  }

  /// Stops live following and releases its frame callback.
  void _stopBottomFollow() {
    _bottomFollowTicker.stop();
    _bottomFollowLastFrameMicroseconds = null;
    _bottomFollowCompleting = false;
    _bottomFollowDeadlineMicroseconds = null;
  }

  /// Reports whether bottom following should continue for live or completing rows.
  bool _shouldRunBottomFollow() {
    return _hasLiveBottomStream() || _isCompletingBottomFollow();
  }

  /// Reports whether a finished bottom stream is still settling its final layout.
  bool _isCompletingBottomFollow() {
    return _bottomFollowCompleting;
  }

  /// Starts the final smooth-follow window for a completed bottom stream.
  void _beginBottomFollowCompletion() {
    if (!mounted ||
        !widget.autoScrollToBottomListenable.value ||
        widget.hasNewerDisplayHistory ||
        widget.isLoadingDisplayWindow ||
        !widget.scrollController.hasClients) {
      return;
    }
    final nowMicroseconds = _bottomFollowNowMicroseconds;
    _bottomFollowCompleting = true;
    _bottomFollowDeadlineMicroseconds =
        nowMicroseconds + _bottomFollowDuration.inMicroseconds;
    if (!_bottomFollowTicker.isActive) {
      _bottomFollowLastFrameMicroseconds = nowMicroseconds;
      _bottomFollowTicker.start();
    }
  }

  /// Reports whether the visible bottom message is receiving live AI output.
  bool _hasLiveBottomStream() {
    final message = widget.messages.lastOrNull;
    return message != null &&
        message.sender == 'ai' &&
        message.contentStream != null;
  }

  /// Returns to the latest bottom without replacing the transcript's layout origin.
  Future<void> _scrollToBottomFromNavigator() async {
    _historyLoadDirection = ScrollDirection.idle;
    _clearPendingMessageJump();
    _stopBottomFollow();
    final generation = _messageNavigationGeneration;
    _pendingScrollToBottom = true;
    widget.onAutoScrollToBottomChanged(true);
    if (widget.hasNewerDisplayHistory) {
      await widget.onShowLatestDisplayWindow();
    }
    if (!mounted || generation != _messageNavigationGeneration) return;
    if (_pendingScrollToBottom) _applyPendingNavigation();
  }

  /// Reveals a timestamp and ignores completions superseded by user navigation.
  Future<void> _jumpToMessageTimestamp(int timestamp) async {
    if (!widget.hasNewerDisplayHistory &&
        widget.messages.lastOrNull?.timestamp == timestamp) {
      await _scrollToBottomFromNavigator();
      return;
    }
    _historyLoadDirection = ScrollDirection.idle;
    _clearPendingMessageJump();
    final generation = _messageNavigationGeneration;
    _pendingJumpToMessageTimestamp = timestamp;
    _stopBottomFollow();
    widget.onAutoScrollToBottomChanged(false);
    if (widget.messages.any((message) => message.timestamp == timestamp)) {
      setState(_applyPendingNavigation);
      return;
    }

    final didReveal = await widget.onRevealMessageForLocator(timestamp);
    if (!mounted || generation != _messageNavigationGeneration) {
      return;
    }
    if (!didReveal) {
      _clearPendingMessageJump();
      return;
    }
    setState(_applyPendingNavigation);
  }

  /// Resolves navigator indices to stable message identities.
  void _jumpToMessageIndex(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= widget.messages.length) {
      return;
    }
    unawaited(_jumpToMessageTimestamp(widget.messages[targetIndex].timestamp));
  }

  /// Aligns the current bottom or establishes an origin for a history target.
  void _applyPendingNavigation() {
    final timestamp = _pendingJumpToMessageTimestamp;
    final targetsLatest =
        timestamp != null &&
        timestamp == widget.messages.lastOrNull?.timestamp &&
        !widget.hasNewerDisplayHistory;
    if (_pendingScrollToBottom || targetsLatest) {
      if (widget.hasNewerDisplayHistory ||
          widget.isLoadingDisplayWindow ||
          widget.messages.isEmpty) {
        return;
      }
      _pendingScrollToBottom = false;
      _pendingJumpToMessageTimestamp = null;
      widget.onAutoScrollToBottomChanged(true);
      _layoutScrollController.alignBottom();
      _scheduleMessageAnchorCollection();
      return;
    }
    if (timestamp == null) {
      return;
    }
    if (!widget.messages.any((message) => message.timestamp == timestamp)) {
      return;
    }
    _pendingJumpToMessageTimestamp = null;
    _layoutAnchorTimestamp = timestamp;
    _requestedOlderBoundary = null;
    _requestedNewerBoundary = null;
    _scrollLayoutKey = UniqueKey();
    _visibleAnchor = null;
    _rebaseOffset = null;
    _lastScrollMaxExtent = null;
    _messageAnchorsNotifier.value = const <int, ChatScrollMessageAnchor>{};
    _layoutAnchorAtBottom = false;
    widget.onAutoScrollToBottomChanged(false);
    _scheduleMessageAnchorCollection();
  }

  /// Cancels pending reveals without changing the established layout origin.
  void _clearPendingMessageJump() {
    _messageNavigationGeneration++;
    _pendingJumpToMessageTimestamp = null;
    _pendingScrollToBottom = false;
  }

  /// Collects render anchors for currently visible chat message rows.
  void _collectMessageAnchors() {
    final scroll = widget.scrollController;
    if (!scroll.hasClients ||
        scroll.positions.length != 1 ||
        !scroll.position.hasPixels) {
      return;
    }
    final anchors = <int, ChatScrollMessageAnchor>{};
    ChatScrollMessageAnchor? firstVisible;
    ChatScrollMessageAnchor? partiallyVisible;
    for (final timestamp in _mountedRows.keys) {
      final key = _messageKeys[timestamp];
      final index = _messageIndices[timestamp];
      if (index == null || key == null) continue;
      final measured = _measureRow(timestamp);
      if (measured == null ||
          measured.top >= scroll.position.viewportDimension ||
          measured.top + measured.height <= 0)
        continue;
      final anchor = ChatScrollMessageAnchor(
        timestamp: timestamp,
        index: index,
        key: key,
        absoluteTopPx: scroll.offset + measured.top,
        heightPx: measured.height,
      );
      anchors[timestamp] = anchor;
      if (measured.top < -0.5) {
        partiallyVisible ??= anchor;
      } else if (firstVisible == null ||
          anchor.absoluteTopPx < firstVisible.absoluteTopPx) {
        firstVisible = anchor;
      }
    }
    _visibleAnchor = firstVisible ?? partiallyVisible;
    widget.messageNavigation?.visibleTimestamp = _visibleAnchor?.timestamp;
    if (_showNavigatorChipNotifier.value) {
      _messageAnchorsNotifier.value = anchors;
    }
  }

  void _indexMessages() {
    _measuredPrefix = null;
    _messageIndices.clear();
    for (var index = 0; index < widget.messages.length; index++) {
      _messageIndices[widget.messages[index].timestamp] = index;
    }
  }

  /// Keeps exact measured extents when a different set of rows enters the viewport.
  double _estimateRange(int start, int end, double mean, int itemCount) {
    if (start >= end) return 0;
    var prefix = _measuredPrefix;
    if (prefix == null || prefix.length != itemCount + 1) {
      prefix = [(height: 0.0, count: 0)];
      for (var index = 0; index < itemCount; index++) {
        final height = _rowExtents[_extentKeyForIndex(index)]?.lastLayoutHeight;
        final previous = prefix.last;
        prefix.add((
          height: previous.height + (height ?? 0),
          count: previous.count + (height == null ? 0 : 1),
        ));
      }
      _measuredPrefix = prefix;
    }
    final before = prefix[start];
    final after = prefix[end];
    return after.height -
        before.height +
        (end - start - after.count + before.count) * mean;
  }

  int? _findRowIndex(Key key, int itemCount) {
    if (key is ValueKey<int>) return _messageIndices[key.value];
    return key == const ValueKey<String>('row-status') &&
            itemCount > widget.messages.length
        ? widget.messages.length
        : null;
  }

  /// Reads only sliver geometry while the viewport is in its layout phase.
  ({double top, double height})? _measureRow(int timestamp) {
    final extent = _rowExtents[ValueKey<int>(timestamp)];
    RenderObject? child = extent?.mountedBox;
    while (child != null && child.parent is! RenderSliverMultiBoxAdaptor) {
      child = child.parent;
    }
    if (child == null || !child.attached) return null;
    final sliver = child.parent! as RenderSliverMultiBoxAdaptor;
    final data = child.parentData as SliverMultiBoxAdaptorParentData;
    final offset = data.layoutOffset;
    final geometry = sliver.geometry;
    final height = extent?.lastLayoutHeight;
    if (offset == null ||
        geometry == null ||
        data.keptAlive ||
        height == null) {
      return null;
    }
    final viewport = RenderAbstractViewport.maybeOf(sliver);
    if (viewport == null) return null;
    final constraints = sliver.constraints;
    final local = offset - constraints.scrollOffset;
    final reversed =
        applyGrowthDirectionToAxisDirection(
          constraints.axisDirection,
          constraints.growthDirection,
        ) ==
        AxisDirection.up;
    final sliverTop = MatrixUtils.transformPoint(
      sliver.getTransformTo(viewport),
      Offset.zero,
    ).dy;
    final top =
        sliverTop + (reversed ? geometry.paintExtent - height - local : local);
    return top.isFinite ? (top: top, height: height) : null;
  }

  /// Adding pixels back cancels gesture motion and isolates changes in layout.
  double _measureAnchorShift(double pixels) {
    final anchor = _visibleAnchor;
    if (anchor == null || !_shouldPreserveManualViewport()) return 0;
    final measured = _measureRow(anchor.timestamp);
    return measured == null ? 0 : measured.top + pixels - anchor.absoluteTopPx;
  }

  /// Returns the persistent render key for one message identity.
  GlobalKey _keyForMessage(int timestamp) {
    return _messageKeys.putIfAbsent(timestamp, GlobalKey.new);
  }

  /// Keeps measurements keyed by timestamps across display-window changes.
  Key _extentKeyForIndex(int index) {
    if (index < widget.messages.length) {
      return ValueKey<int>(widget.messages[index].timestamp);
    }
    return _rowKeyForIndex(index);
  }

  /// Identifies message and status rows independently of their list index.
  Key _rowKeyForIndex(int index) {
    if (index < widget.messages.length) {
      return _keyForMessage(widget.messages[index].timestamp);
    }
    return const ValueKey<String>('row-status');
  }

  /// Refreshes cached rows and anchors after the message window changes.
  @override
  void didUpdateWidget(ChatArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clients.bridge != widget.clients.bridge) {
      _messageTransforms.dispose();
      _messageTransforms = MessageTransformCache(widget.clients);
      _messageRowCache.clear();
    }
    _messageTransforms.bindChat(widget.currentChatId);
    _messageContributions.bindClients(widget.clients);
    _chatBusyNotifier.value = widget.isLoading;
    _layoutScrollController.delegate = widget.scrollController;
    final chatChanged = oldWidget.currentChatId != widget.currentChatId;
    if (!identical(oldWidget.messages, widget.messages) || chatChanged) {
      _indexMessages();
    }
    if (oldWidget.fileDirectory != widget.fileDirectory) {
      _messageRowCache.clear();
    }
    if (chatChanged) {
      _markdownPreparation.dispose();
      _markdownPreparation = TranscriptPreparationQueue(2);
      _historyLoadDirection = ScrollDirection.idle;
      _historyLoadRequest = null;
      _requestedOlderBoundary = null;
      _requestedNewerBoundary = null;
      _stopBottomFollow();
      _lastScrollMaxExtent = null;
      _messageKeys.clear();
      _mountedRows.clear();
      _visibleAnchor = null;
      widget.messageNavigation?.visibleTimestamp = null;
      _messageRowCache.clear();
      _disposeRowExtents();
      _messageAnchorsNotifier.value = const <int, ChatScrollMessageAnchor>{};
      _showNavigatorChipNotifier.value = false;
      _userScrollSessionActive = false;
      _userScrollDirection = ScrollDirection.idle;
      _clearPendingMessageJump();
      _layoutAnchorTimestamp = null;
      _layoutAnchorAtBottom = false;
      _initialLayoutOriginChosen = false;
      _scrollLayoutKey = UniqueKey();
    }
    if (_bottomStreamCompleted(oldWidget)) {
      _beginBottomFollowCompletion();
    }
    final messagesChanged =
        chatChanged ||
        oldWidget.messages.length != widget.messages.length ||
        oldWidget.messages.firstOrNull?.timestamp !=
            widget.messages.firstOrNull?.timestamp ||
        oldWidget.messages.lastOrNull?.timestamp !=
            widget.messages.lastOrNull?.timestamp;
    if (_layoutAnchorTimestamp != null &&
        !_messageIndices.containsKey(_layoutAnchorTimestamp)) {
      final anchor = _visibleAnchor;
      final preserve =
          anchor != null &&
          _messageIndices.containsKey(anchor.timestamp) &&
          !_ownsBottomScroll();
      if (preserve && widget.scrollController.hasClients) {
        _rebaseOffset = widget.scrollController.offset - anchor.absoluteTopPx;
      }
      _layoutAnchorTimestamp = preserve ? anchor.timestamp : null;
      _visibleAnchor = null;
      _layoutAnchorAtBottom = false;
      _initialLayoutOriginChosen = preserve;
      _scrollLayoutKey = UniqueKey();
    }
    _applyPendingNavigation();
    final bottomInsetChanged =
        oldWidget.bottomContentInset != widget.bottomContentInset;
    if (messagesChanged || bottomInsetChanged) {
      _scheduleHistoryLoad(_historyLoadDirection);
      _scheduleMessageAnchorCollection();
    } else if (oldWidget.isLoading != widget.isLoading ||
        oldWidget.errorMessage != widget.errorMessage ||
        oldWidget.hasNewerDisplayHistory != widget.hasNewerDisplayHistory ||
        oldWidget.isLoadingDisplayWindow != widget.isLoadingDisplayWindow) {
      _scheduleHistoryLoad(_historyLoadDirection);
      _scheduleMessageAnchorCollection();
    }
    if (messagesChanged) {
      _messageKeys.removeWhere(
        (timestamp, _) => !_messageIndices.containsKey(timestamp),
      );
      _messageRowCache.removeWhere(
        (timestamp, _) => !_messageIndices.containsKey(timestamp),
      );
      final retired = <ChatMessageExtent>[];
      if (_rowExtents.length > 160) {
        final staleKeys = _rowExtents.keys
            .where(
              (key) =>
                  key is ValueKey<int> &&
                  !_messageIndices.containsKey(key.value),
            )
            .take(_rowExtents.length - 160)
            .toList();
        for (final key in staleKeys) {
          retired.add(_rowExtents.remove(key)!);
        }
      }
      _releaseRowExtents(retired);
    }
  }

  /// Releases measurements after their old row render trees have detached.
  void _releaseRowExtents(List<ChatMessageExtent> extents) {
    if (extents.isEmpty) {
      return;
    }
    scheduleMicrotask(() {
      for (final extent in extents) {
        extent.dispose();
      }
    });
  }

  /// Retires all measurements when their chat identity leaves the transcript.
  void _disposeRowExtents() {
    _releaseRowExtents(_rowExtents.values.toList());
    _rowExtents.clear();
  }

  /// Releases timers, cached rows, and navigation state.
  @override
  void dispose() {
    _markdownPreparation.dispose();
    _messageTransforms.dispose();
    _messageContributions.dispose();
    _navigatorHideTimer?.cancel();
    _viewportResizeTimer?.cancel();
    _layoutScrollController.dispose();
    _bottomFollowTicker.dispose();
    _bottomFollowDeadlineMicroseconds = null;
    _messageAnchorsNotifier.dispose();
    _viewportHeightNotifier.dispose();
    _showNavigatorChipNotifier.dispose();
    _chatBusyNotifier.dispose();
    _messageKeys.clear();
    _mountedRows.clear();
    _messageRowCache.clear();
    _disposeRowExtents();
    super.dispose();
  }

  /// Reuses transcript content while each menu observes current chat activity.
  Widget _messageRowFor(int messageIndex, ChatUiMessage message) {
    final selected = widget.selectedMessageTimestamps.contains(
      message.timestamp,
    );
    final selectionMode = widget.isMultiSelectMode;
    final isStreaming = _isStreamingMessage(messageIndex);
    final themePreferenceSnapshot = OperitTheme.of(
      context,
    ).themePreferenceSnapshot;
    final colorScheme = Theme.of(context).colorScheme;
    final messageThemeColors = resolveChatMessageThemeColors(
      themePreferenceSnapshot,
      colorScheme,
    );
    final cached = _messageRowCache[message.timestamp];
    final cachedMessageMatches =
        cached != null &&
        cached.depthAnchor == widget.messages.lastOrNull?.timestamp &&
        cached.selected == selected &&
        cached.selectionMode == selectionMode &&
        cached.isStreaming == isStreaming &&
        cached.onIdentityTap == widget.onIdentityTap &&
        cached.chatId == widget.currentChatId &&
        cached.identityAvatarUri == widget.identityAvatarUri &&
        cached.themePreferenceSnapshot == themePreferenceSnapshot &&
        cached.messageThemeColors == messageThemeColors &&
        _sameMessageForRender(cached.message, message);
    if (cachedMessageMatches) {
      return cached.widget;
    }

    /// Builds a visual copy while actions retain the original canonical message.
    final splitter = widget.splitMarkdownContent;
    final preparation = _markdownPreparation;
    Widget renderMessage(ChatUiMessage displayMessage) =>
        TranscriptMarkdownScope(
          enabled: !isStreaming,
          child: buildThemedChatMessage(
            snapshot: themePreferenceSnapshot,
            colorScheme: colorScheme,
            key: ValueKey<String>(_messageWidgetKey(message)),
            message: displayMessage,
            onIdentityTap: widget.onIdentityTap,
            splitMarkdownContent:
                splitter == null || isStreaming || widget.transcript == null
                ? splitter
                : (content) async =>
                      await preparation.run(() => splitter(content)) ?? [],
            onDeleteMessage: widget.onDeleteMessage,
            onEditSummary: widget.onSelectMessageToEdit,
            enableDialogs: !selectionMode,
          ),
        );
    final currentChatId = widget.currentChatId;
    final chatMessage = currentChatId == null
        ? renderMessage(message)
        : TransformedChatMessage(
            cache: _messageTransforms,
            message: message,
            chatId: currentChatId,
            clients: widget.clients,
            depthAnchor: widget.messages.lastOrNull?.timestamp,
            builder: renderMessage,
          );
    final messageContent = _SelectableMessageFrame(
      selected: selected,
      selectionMode: selectionMode,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MarkdownFileScope.forParts(
            parts: message.parts,
            fallbackBasePath: widget.fileDirectory,
            clients: widget.clients,
            child: chatMessage,
          ),
          if (!selectionMode)
            if (widget.currentChatId case final chatId?)
              ChatMessageSlotHost(
                catalog: _messageContributions,
                chatId: chatId,
                message: message,
                isStreaming: isStreaming,
                onActionResult: (entry, value) => unawaited(
                  _handleMessageContribution(chatId, message, entry, value),
                ),
              ),
          if (message.sender == 'ai' && message.variantCount > 1)
            _MessageVariantSwitcher(
              message: message,
              onSelect: widget.onSelectMessageVariant,
            ),
        ],
      ),
    );
    final row = selectionMode
        ? GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => widget.onToggleMessageSelection(message.timestamp),
            child: messageContent,
          )
        : widget.currentChatId == null
        ? messageContent
        : ValueListenableBuilder<bool>(
            valueListenable: _chatBusyNotifier,
            child: messageContent,
            builder: (context, isChatBusy, child) => MessageContextMenu(
              key: ValueKey<String>('menu-${_messageWidgetKey(message)}'),
              message: message,
              chatId: widget.currentChatId!,
              messageIndex: messageIndex,
              resolveMessageIndex: () => _messageIndices[message.timestamp],
              clients: widget.clients,
              packageManager: widget.packageManager,
              onToggleFavoriteMessage: widget.onToggleFavoriteMessage,
              onDeleteMessage: widget.onDeleteMessage,
              onDeleteMessagesFrom: widget.onDeleteMessagesFrom,
              onDeleteMessageVariant: widget.onDeleteMessageVariant,
              onRollbackToMessage: widget.onRollbackToMessage,
              onSelectMessageToEdit: widget.onSelectMessageToEdit,
              onRegenerateMessage: widget.onRegenerateMessage,
              isChatBusy: isChatBusy,
              onInsertSummary: widget.onInsertSummary,
              onCreateBranch: widget.onCreateBranch,
              onReplyToMessage: widget.onReplyToMessage,
              onPlayVoice: widget.onPlayVoice,
              onToggleMultiSelectMode: widget.onToggleMultiSelectMode,
              onRefresh: widget.onRefreshRequested,
              splitMarkdownContent: widget.splitMarkdownContent,
              child: child!,
            ),
          );
    _messageRowCache[message.timestamp] = _CachedMessageRow(
      depthAnchor: widget.messages.lastOrNull?.timestamp,
      message: message,
      selected: selected,
      selectionMode: selectionMode,
      isStreaming: isStreaming,
      identityAvatarUri: widget.identityAvatarUri,
      onIdentityTap: widget.onIdentityTap,
      themePreferenceSnapshot: themePreferenceSnapshot,
      messageThemeColors: messageThemeColors,
      chatId: widget.currentChatId,
      widget: row,
    );
    return row;
  }

  /// Builds an element identity that cannot be shared by different chats.
  String _messageWidgetKey(ChatUiMessage message) {
    return '${widget.currentChatId ?? '__NO_CHAT__'}-${message.stableKey}';
  }

  /// Shows the standalone cursor only before an AI response stream is attached.
  bool _shouldShowLoadingIndicator() {
    if (!widget.isLoading || widget.messages.isEmpty) {
      return widget.isLoading && widget.messages.isEmpty;
    }
    final lastMessage = widget.messages.last;
    return lastMessage.sender == 'user' ||
        (lastMessage.sender == 'ai' &&
            lastMessage.parts.isEmpty &&
            lastMessage.contentStream == null);
  }

  /// Reports whether this AI row currently owns a live response stream.
  bool _isStreamingMessage(int index) {
    if (index < 0 || index >= widget.messages.length) {
      return false;
    }
    final message = widget.messages[index];
    return message.sender == 'ai' && message.contentStream != null;
  }

  /// Reports whether the same bottom AI message just finished streaming.
  bool _bottomStreamCompleted(ChatArea oldWidget) {
    final oldMessage = oldWidget.messages.lastOrNull;
    final message = widget.messages.lastOrNull;
    return oldWidget.currentChatId == widget.currentChatId &&
        oldMessage != null &&
        message != null &&
        oldMessage.timestamp == message.timestamp &&
        oldMessage.sender == 'ai' &&
        message.sender == 'ai' &&
        oldMessage.contentStream != null &&
        message.contentStream == null;
  }
}

/// Creates layout-aware positions while keeping the public controller attached.
class _TranscriptSliverDelegate extends SliverChildBuilderDelegate {
  const _TranscriptSliverDelegate(
    super.builder, {
    required super.childCount,
    required super.findChildIndexCallback,
    required this.estimateTail,
  });

  final double Function(int, double) estimateTail;

  @override
  double estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) =>
      trailingScrollOffset +
      estimateTail(
        lastIndex,
        (trailingScrollOffset - leadingScrollOffset) /
            (lastIndex - firstIndex + 1),
      );
}

class _TranscriptRowRegistration extends StatefulWidget {
  const _TranscriptRowRegistration({
    required this.timestamp,
    required this.rows,
    required this.child,
  });

  final int timestamp;
  final Map<int, Object> rows;
  final Widget child;

  @override
  State<_TranscriptRowRegistration> createState() =>
      _TranscriptRowRegistrationState();
}

class _TranscriptRowRegistrationState
    extends State<_TranscriptRowRegistration> {
  @override
  void initState() {
    super.initState();
    widget.rows[widget.timestamp] = this;
  }

  @override
  void dispose() {
    if (identical(widget.rows[widget.timestamp], this)) {
      widget.rows.remove(widget.timestamp);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TranscriptMessageBody extends StatefulWidget {
  const _TranscriptMessageBody({
    required this.message,
    required this.transcript,
    required this.builder,
  });

  final ChatUiMessage message;
  final ChatTranscriptController transcript;
  final Widget Function(ChatUiMessage) builder;

  @override
  State<_TranscriptMessageBody> createState() => _TranscriptMessageBodyState();
}

class _TranscriptMessageBodyState extends State<_TranscriptMessageBody> {
  Future<ChatUiMessage?>? _body;
  ChatUiMessage? _visible;

  @override
  void initState() {
    super.initState();
    _bindBody();
  }

  @override
  void didUpdateWidget(covariant _TranscriptMessageBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transcript != widget.transcript ||
        oldWidget.message.selectedVariantIndex !=
            widget.message.selectedVariantIndex) {
      _visible = null;
    }
    if (!identical(oldWidget.message, widget.message) ||
        oldWidget.transcript != widget.transcript) {
      _bindBody();
    }
  }

  void _bindBody() {
    final message = widget.message;
    if (message.parts.isEmpty && message.contentStream == null) {
      _body = widget.transcript.hydrate(message);
    } else {
      _visible = message;
      _body = null;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ChatUiMessage?>(
    future: _body,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.data != null) {
        _visible = snapshot.data;
      }
      final visible = _visible;
      if (visible != null) return widget.builder(visible);
      if (snapshot.hasError) {
        return TextButton(
          onPressed: () => setState(() {
            _body = widget.transcript.retryBody(widget.message);
          }),
          child: Text(AppLocalizations.of(context)!.retry),
        );
      }
      return const SizedBox(
        height: 54,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    },
  );
}

class _ChatLayoutScrollController extends ScrollController {
  /// Retains the external navigation controller and the current ownership policy.
  _ChatLayoutScrollController({
    required ScrollController delegate,
    required this.shouldAlignBottom,
    required this.shouldInitiallyAlignBottom,
    required this.hasBottomLayoutOrigin,
    required this.leadingScrollExtent,
    required this.layoutOriginTopPadding,
    required this.viewportCorrection,
    required this.initialOffset,
  }) : _delegate = delegate,
       super(keepScrollOffset: false);

  ScrollController _delegate;
  final ValueGetter<bool> shouldAlignBottom;
  final ValueGetter<bool> shouldInitiallyAlignBottom;
  final ValueGetter<bool> hasBottomLayoutOrigin;
  final ValueGetter<double> leadingScrollExtent;
  final ValueGetter<double> layoutOriginTopPadding;
  final double Function(double) viewportCorrection;
  final double? Function() initialOffset;
  ScrollPosition? _origin;

  /// Requests bottom alignment in the current position's next layout pass.
  void alignBottom() {
    final origin = _origin;
    if (origin is _ChatLayoutScrollPosition) origin.alignBottom();
  }

  /// Moves the active layout origin when the owner replaces its controller.
  set delegate(ScrollController value) {
    if (identical(value, _delegate)) {
      return;
    }
    final origin = _origin;
    final previous = _delegate;
    _delegate = value;
    if (origin == null) {
      return;
    }
    previous.detach(origin);
    value.attach(origin);
  }

  /// The active layout origin. A replaced viewport stays registered until it
  /// unmounts, so [positions] can briefly contain that deactivated origin.
  @override
  ScrollPosition get position {
    final origin = _origin;
    if (origin == null) {
      throw StateError('ScrollController not attached to any scroll views.');
    }
    return origin;
  }

  /// Registers a new layout origin and publishes only that origin to the owner.
  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    final previous = _origin;
    _origin = position;
    if (previous != null) {
      _delegate.detach(previous);
    }
    _delegate.attach(position);
  }

  /// Releases a viewport position. Only the active origin is on the owner.
  @override
  void detach(ScrollPosition position) {
    if (identical(position, _origin)) {
      _delegate.detach(position);
      _origin = null;
    }
    super.detach(position);
  }

  /// Starts a new layout origin without restoring offsets from another origin.
  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _ChatLayoutScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialOffset() ?? _delegate.initialScrollOffset,
      oldPosition: oldPosition,
      shouldAlignBottom: shouldAlignBottom,
      shouldInitiallyAlignBottom: shouldInitiallyAlignBottom,
      hasBottomLayoutOrigin: hasBottomLayoutOrigin,
      leadingScrollExtent: leadingScrollExtent,
      layoutOriginTopPadding: layoutOriginTopPadding,
      viewportCorrection: viewportCorrection,
    );
  }
}

/// Resolves static bottom ownership in layout instead of moving a painted frame.
class _ChatLayoutScrollPosition extends ScrollPositionWithSingleContext {
  /// Creates a position scoped to the current chat and locator layout origin.
  _ChatLayoutScrollPosition({
    required super.physics,
    required super.context,
    required super.initialPixels,
    required super.oldPosition,
    required this.shouldAlignBottom,
    required this.shouldInitiallyAlignBottom,
    required this.hasBottomLayoutOrigin,
    required this.leadingScrollExtent,
    required this.layoutOriginTopPadding,
    required this.viewportCorrection,
  }) : super(keepScrollOffset: false);

  final ValueGetter<bool> shouldAlignBottom;
  final ValueGetter<bool> shouldInitiallyAlignBottom;
  final ValueGetter<bool> hasBottomLayoutOrigin;
  final ValueGetter<double> leadingScrollExtent;
  final ValueGetter<double> layoutOriginTopPadding;
  final double Function(double) viewportCorrection;
  bool _corrected = false;
  double? _previousOriginTopPadding;
  bool _bottomAlignmentRequested = false;

  /// Reuses this coordinate system and resolves its bottom before painting.
  void alignBottom() {
    _bottomAlignmentRequested = true;
    goIdle();
    forcePixels(maxScrollExtent);
  }

  /// Requests a new layout pass with the measured bottom before any painting.
  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (hasBottomLayoutOrigin()) {
      // Viewport clamps the leading bound to zero. With a bottom origin and
      // short history, its true top is positive; retain that bound so users
      // cannot scroll into the empty space above a transcript that fits.
      minScrollExtent = viewportDimension - leadingScrollExtent();
      maxScrollExtent = math.max(minScrollExtent, maxScrollExtent);
    }
    final alignsBottom =
        _bottomAlignmentRequested ||
        shouldAlignBottom() ||
        (!haveDimensions && shouldInitiallyAlignBottom());
    final padding = layoutOriginTopPadding();
    final paddingDelta = padding - (_previousOriginTopPadding ?? padding);
    _previousOriginTopPadding = padding;
    // Prepending moves transcript-top padding away from the stable layout origin.
    // Correct that coordinate change before paint while retaining the active drag.
    if (!alignsBottom && !_corrected) {
      final measured = viewportCorrection(pixels);
      final delta = measured.abs() >= 0.5 ? measured : paddingDelta;
      final corrected = (pixels + delta)
          .clamp(minScrollExtent, maxScrollExtent)
          .toDouble();
      if (delta.abs() >= 0.5 && (corrected - pixels).abs() >= 0.5) {
        _corrected = true;
        correctPixels(corrected);
        return false;
      }
    }
    _corrected = false;
    if (alignsBottom && pixels != maxScrollExtent) {
      correctPixels(maxScrollExtent);
      return false;
    }
    final accepted = super.applyContentDimensions(
      minScrollExtent,
      maxScrollExtent,
    );
    if (accepted) _bottomAlignmentRequested = false;
    return accepted;
  }
}

/// Displays controls for selecting the active response variant of one AI message.
class _MessageVariantSwitcher extends StatelessWidget {
  const _MessageVariantSwitcher({
    required this.message,
    required this.onSelect,
  });

  final ChatUiMessage message;
  final MessageVariantAction onSelect;

  @override
  /// Builds the compact variant selection controls.
  Widget build(BuildContext context) {
    final hasPrevious = message.selectedVariantIndex > 0;
    final hasNext = message.selectedVariantIndex < message.variantCount - 1;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 16, top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          IconButton(
            tooltip: '上一条变体',
            visualDensity: VisualDensity.compact,
            onPressed: hasPrevious
                ? () async {
                    await onSelect(
                      message.timestamp,
                      message.selectedVariantIndex - 1,
                    );
                  }
                : null,
            icon: const Icon(Icons.arrow_back, size: 18),
          ),
          Text(
            '${message.selectedVariantIndex + 1} / ${message.variantCount}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          IconButton(
            tooltip: '下一条变体',
            visualDensity: VisualDensity.compact,
            onPressed: hasNext
                ? () async {
                    await onSelect(
                      message.timestamp,
                      message.selectedVariantIndex + 1,
                    );
                  }
                : null,
            icon: const Icon(Icons.arrow_forward, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ChatAreaContentColumn extends StatelessWidget {
  const _ChatAreaContentColumn({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final themePreferenceSnapshot = OperitTheme.of(
      context,
    ).themePreferenceSnapshot;
    final maxWidth = themePreferenceSnapshot.bubbleWideLayoutEnabled
        ? chatWideContentMaxWidth
        : chatContentMaxWidth;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  /// Creates a selectable transcript status or API error message.
  const _StatusMessage({required this.text, this.isError = false});

  final String text;
  final bool isError;

  /// Builds the status with an API explanation and its original error text.
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SelectableText(
        isError ? apiErrorText(text, AppLocalizations.of(context)!) : text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: isError
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SelectableMessageFrame extends StatelessWidget {
  const _SelectableMessageFrame({
    required this.selected,
    required this.selectionMode,
    required this.child,
  });

  final bool selected;
  final bool selectionMode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!selectionMode && !selected) {
      return child;
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: <Widget>[
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.08)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant.withValues(alpha: 0.45),
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: child,
        ),
        Positioned(
          left: 6,
          top: 6,
          child: Icon(
            selected ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: selected
                ? colorScheme.primary
                : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _CachedMessageRow {
  /// Records the message and rendering state represented by one retained row.
  const _CachedMessageRow({
    required this.depthAnchor,
    required this.message,
    required this.selected,
    required this.selectionMode,
    required this.isStreaming,
    required this.identityAvatarUri,
    this.onIdentityTap,
    required this.themePreferenceSnapshot,
    required this.messageThemeColors,
    required this.chatId,
    required this.widget,
  });

  final int? depthAnchor;
  final ChatUiMessage message;
  final bool selected;
  final bool selectionMode;
  final bool isStreaming;
  final String? identityAvatarUri;
  final VoidCallback? onIdentityTap;
  final ThemePreferenceSnapshot themePreferenceSnapshot;
  final ChatMessageThemeColors messageThemeColors;
  final String? chatId;
  final Widget widget;
}

/// Reports whether one cached message row can be reused unchanged.
bool _sameMessageForRender(ChatUiMessage left, ChatUiMessage right) {
  final contentStreamSame = identical(left.contentStream, right.contentStream);
  return const DeepCollectionEquality().equals(
        left.pluginExtensions,
        right.pluginExtensions,
      ) &&
      left.sender == right.sender &&
      markdownFileContextForParts(left.parts) ==
          markdownFileContextForParts(right.parts) &&
      (_sameMessagePartsForRender(left, right) ||
          _sameLiveAiStreamForRender(left, right, contentStreamSame)) &&
      left.timestamp == right.timestamp &&
      left.roleName == right.roleName &&
      left.selectedVariantIndex == right.selectedVariantIndex &&
      left.variantCount == right.variantCount &&
      left.provider == right.provider &&
      left.modelName == right.modelName &&
      left.inputTokens == right.inputTokens &&
      left.outputTokens == right.outputTokens &&
      left.cachedInputTokens == right.cachedInputTokens &&
      left.sentAt == right.sentAt &&
      left.outputDurationMs == right.outputDurationMs &&
      left.waitDurationMs == right.waitDurationMs &&
      left.displayMode == right.displayMode &&
      left.isFavorite == right.isFavorite &&
      left.isVariantPreview == right.isVariantPreview &&
      left.completedAt == right.completedAt &&
      contentStreamSame;
}

/// Reports whether one live AI stream should keep its mounted row.
bool _sameLiveAiStreamForRender(
  ChatUiMessage left,
  ChatUiMessage right,
  bool contentStreamSame,
) {
  return left.sender == 'ai' &&
      right.sender == 'ai' &&
      contentStreamSame &&
      left.contentStream != null;
}

/// Compares canonical message parts by value for message-row cache reuse.
bool _sameMessagePartsForRender(ChatUiMessage left, ChatUiMessage right) {
  if (left.parts.length != right.parts.length) {
    return false;
  }
  for (var index = 0; index < left.parts.length; index++) {
    final leftPart = left.parts[index];
    final rightPart = right.parts[index];
    if (leftPart.partId != rightPart.partId ||
        leftPart.sequence != rightPart.sequence ||
        leftPart.kind != rightPart.kind ||
        leftPart.content != rightPart.content ||
        leftPart.toolCallId != rightPart.toolCallId ||
        leftPart.toolName != rightPart.toolName ||
        !mapEquals(leftPart.attributes, rightPart.attributes)) {
      return false;
    }
  }
  return true;
}

/// Observes live bottom row growth after its first layout.
class _LiveBottomStreamSizeObserver extends SingleChildRenderObjectWidget {
  const _LiveBottomStreamSizeObserver({
    required this.observesGrowth,
    required this.onSizeGrown,
    required super.child,
  });

  final bool observesGrowth;
  final ValueChanged<double> onSizeGrown;

  /// Creates the render object that records row dimensions.
  @override
  RenderObject createRenderObject(BuildContext context) {
    return _LiveBottomStreamSizeRenderObject(
      observesGrowth: observesGrowth,
      onSizeGrown: onSizeGrown,
    );
  }

  /// Updates the callback used by the retained render object.
  @override
  void updateRenderObject(
    BuildContext context,
    _LiveBottomStreamSizeRenderObject renderObject,
  ) {
    renderObject
      ..observesGrowth = observesGrowth
      ..onSizeGrown = onSizeGrown;
  }
}

/// Reports height increases for the live bottom row.
class _LiveBottomStreamSizeRenderObject extends RenderProxyBox {
  _LiveBottomStreamSizeRenderObject({
    required bool observesGrowth,
    required ValueChanged<double> onSizeGrown,
  }) : _observesGrowth = observesGrowth,
       _onSizeGrown = onSizeGrown;

  bool _observesGrowth;
  ValueChanged<double> _onSizeGrown;
  Size? _lastSize;

  set observesGrowth(bool value) {
    if (_observesGrowth == value) {
      return;
    }
    _observesGrowth = value;
    if (!value) {
      _lastSize = null;
    }
  }

  set onSizeGrown(ValueChanged<double> value) {
    _onSizeGrown = value;
  }

  /// Reports the first layout and every later live-row height increase.
  @override
  void performLayout() {
    final previousSize = _lastSize;
    super.performLayout();
    final currentSize = size;
    if (!_observesGrowth) {
      _lastSize = null;
      return;
    }
    _lastSize = currentSize;
    if (previousSize == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onSizeGrown(0);
      });
      return;
    }
    final heightDelta = currentSize.height - previousSize.height;
    if (heightDelta <= _bottomFollowPositionTolerance) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onSizeGrown(heightDelta);
    });
  }
}

class _EmptyChatArea extends StatelessWidget {
  const _EmptyChatArea({this.showMark = true});

  /// False while the new-chat intro owns the stage, so the static wordmark
  /// and the intro animation never draw on top of each other. Swapped
  /// without a fade: a fade-out still overlaps the incoming particles.
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!showMark) {
      return const SizedBox.shrink();
    }
    return Center(
      child: Text(
        'Operit',
        style: theme.textTheme.displaySmall?.copyWith(
          color: theme.colorScheme.primary.withValues(alpha: 0.38),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
