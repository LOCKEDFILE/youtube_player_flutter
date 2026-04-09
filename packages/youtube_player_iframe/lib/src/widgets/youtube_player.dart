import 'dart:async';

// Copyright 2022 Sarbagya Dhaubanjar. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:youtube_player_iframe/src/widgets/fullscreen_youtube_player.dart';

import '../controller/youtube_player_controller.dart';
import '../player_value.dart';

/// A widget to play or stream Youtube Videos.
///
/// See also:
///
///  * [FullscreenYoutubePlayer], which play or stream Youtube Videos in fullscreen mode.
class YoutubePlayer extends StatefulWidget {
  /// A widget to play or stream Youtube Videos.
  const YoutubePlayer({
    super.key,
    required this.controller,
    this.aspectRatio = 16 / 9,
    this.gestureRecognizers = const <Factory<OneSequenceGestureRecognizer>>{},
    this.backgroundColor,
    @Deprecated('Unused parameter. Use `YoutubePlayerParam.userAgent` instead.')
    this.userAgent,
    this.enableFullScreenOnVerticalDrag = true,
    this.keepAlive = false,
  });

  /// The [controller] for this player.
  final YoutubePlayerController controller;

  /// Aspect ratio for the player.
  final double aspectRatio;

  /// Which gestures should be consumed by the youtube player.
  ///
  /// It is possible for other gesture recognizers to be competing with the player on pointer
  /// events, e.g if the player is inside a [ListView] the [ListView] will want to handle
  /// vertical drags. The player will claim gestures that are recognized by any of the
  /// recognizers on this list.
  ///
  /// By default vertical and horizontal gestures are absorbed by the player.
  /// Passing an empty set will ignore the defaults.
  ///
  /// This is ignored on web.
  final Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers;

  /// The background color of the [WebView].
  ///
  /// Default to [ColorScheme.surface].
  final Color? backgroundColor;

  /// The value used for the HTTP User-Agent: request header.
  ///
  /// When null the platform's webview default is used for the User-Agent header.
  ///
  /// By default `userAgent` is null.
  final String? userAgent;

  /// Enables switching full screen mode on vertical drag in the player.
  ///
  /// Default is true.
  final bool enableFullScreenOnVerticalDrag;

  /// Whether to keep the state of the player alive when it is not visible.
  final bool keepAlive;

  @override
  State<YoutubePlayer> createState() => _YoutubePlayerState();
}

class _YoutubePlayerState extends State<YoutubePlayer>
    with AutomaticKeepAliveClientMixin {
  late final YoutubePlayerController _controller;
  bool _isShowingAndroidFullscreenWidget = false;
  bool _isClosingAndroidFullscreenWidget = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;

    _initPlayer();
  }

  @override
  void didUpdateWidget(YoutubePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.backgroundColor != oldWidget.backgroundColor) {
      _updateBackgroundColor(widget.backgroundColor);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    Widget player = _buildWebViewWidget(context);

    if (widget.enableFullScreenOnVerticalDrag) {
      player = GestureDetector(
        onVerticalDragUpdate: _fullscreenGesture,
        child: player,
      );
    }

    final content = OrientationBuilder(
      builder: (context, orientation) {
        return AspectRatio(
          aspectRatio: orientation == Orientation.landscape
              ? MediaQuery.of(context).size.aspectRatio
              : widget.aspectRatio,
          child: player,
        );
      },
    );

    if (kIsWeb) return content;

    return StreamBuilder<YoutubePlayerValue>(
      stream: _controller.stream,
      initialData: _controller.value,
      builder: (context, snapshot) {
        final isFullScreen =
            snapshot.data?.fullScreenOption.enabled ?? false;

        return PopScope(
          canPop: !isFullScreen,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;

            if (isFullScreen) {
              _controller.exitFullScreen();
            }
          },
          child: content,
        );
      },
    );
  }

  Widget _buildWebViewWidget(BuildContext context) {
    PlatformWebViewWidgetCreationParams params =
        PlatformWebViewWidgetCreationParams(
      controller: _controller.webViewController.platform,
      layoutDirection: Directionality.of(context),
      gestureRecognizers: widget.gestureRecognizers,
    );

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      params = AndroidWebViewWidgetCreationParams
          .fromPlatformWebViewWidgetCreationParams(
        params,
        displayWithHybridComposition: true,
      );
    }

    return WebViewWidget.fromPlatformCreationParams(params: params);
  }

  void _fullscreenGesture(DragUpdateDetails details) {
    final delta = details.delta.dy;

    if (delta.abs() > 10) {
      delta.isNegative
          ? _controller.enterFullScreen()
          : _controller.exitFullScreen();
    }
  }

  void _updateBackgroundColor(Color? backgroundColor) {
    if (defaultTargetPlatform == TargetPlatform.macOS) return;
    final bgColor = backgroundColor ?? Theme.of(context).colorScheme.surface;
    _controller.webViewController.setBackgroundColor(bgColor);
  }

  Future<void> _initPlayer() async {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _updateBackgroundColor(widget.backgroundColor);
    });

    await _configureAndroidFullscreenCallbacks();

    await _controller.init();
  }

  Future<void> _configureAndroidFullscreenCallbacks() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final platformController = _controller.webViewController.platform;
    if (platformController is! AndroidWebViewController) return;

    await platformController.setCustomWidgetCallbacks(
      onShowCustomWidget: (widget, onCustomWidgetHidden) {
        if (!mounted || _isShowingAndroidFullscreenWidget) return;

        _isShowingAndroidFullscreenWidget = true;
        _isClosingAndroidFullscreenWidget = false;
        _controller.enterFullScreen(lock: false);

        Navigator.of(context, rootNavigator: true)
            .push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (context) {
                  return Scaffold(
                    backgroundColor: Colors.black,
                    body: PopScope(
                      canPop: true,
                      onPopInvokedWithResult: (didPop, _) {
                        if (didPop && !_isClosingAndroidFullscreenWidget) {
                          _isClosingAndroidFullscreenWidget = true;
                          onCustomWidgetHidden();
                        }
                      },
                      child: SizedBox.expand(child: widget),
                    ),
                  );
                },
              ),
            )
            .whenComplete(() {
              _isShowingAndroidFullscreenWidget = false;
              _isClosingAndroidFullscreenWidget = false;
            });
      },
      onHideCustomWidget: () {
        if (
          mounted &&
          _isShowingAndroidFullscreenWidget &&
          !_isClosingAndroidFullscreenWidget
        ) {
          _isClosingAndroidFullscreenWidget = true;
          Navigator.of(context, rootNavigator: true).pop();
        }

        _controller.exitFullScreen(lock: false);
      },
    );
  }

  @override
  void dispose() {
    final platformController = _controller.webViewController.platform;
    if (platformController is AndroidWebViewController) {
      unawaited(
        platformController.setCustomWidgetCallbacks(
          onShowCustomWidget: null,
          onHideCustomWidget: null,
        ),
      );
    }

    super.dispose();
  }

  @override
  bool get wantKeepAlive => widget.keepAlive;
}
