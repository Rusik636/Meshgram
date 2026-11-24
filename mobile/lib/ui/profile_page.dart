// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'ios_control.dart';
import 'mesh_scroll_edge.dart';
import 'profile_wallpaper.dart';
import 'style.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.avatar,
    required this.avatarSize,
    required this.padding,
    required this.children,
    this.identity,
    this.showExpandedTitle = true,
    this.subtitleMaxLines = 1,
    this.heading,
    this.backgroundColor,
    this.leading,
    this.trailing,
  });

  final String title, subtitle;
  final String? identity, heading;
  final Color? backgroundColor;
  final bool showExpandedTitle;
  final int subtitleMaxLines;
  final Widget avatar;
  final double avatarSize;
  final EdgeInsets padding;
  final List<Widget> children;
  final Widget? leading, trailing;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _scroll = ScrollController();
  var _travel = 0.0;
  var _keepCollapsed = false;
  var _headerOverlapsContent = false;

  @override
  void initState() {
    super.initState();
    if (useIosControls) _scroll.addListener(_updatePaintOrder);
  }

  void _updatePaintOrder() {
    final overlaps = _scroll.offset > _travel;
    if (overlaps == _headerOverlapsContent) return;
    setState(() => _headerOverlapsContent = overlaps);
  }

  void _beginGesture() {
    // A new pull from the top may expand the profile. A fling from the
    // content stops at the compact header, even if it reaches it mid-gesture.
    _keepCollapsed = _scroll.hasClients && _scroll.offset > _travel + 0.5;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Material(type: MaterialType.transparency, child: _layout());

  Widget _layout() => LayoutBuilder(
    builder: (context, constraints) {
      final style = MeshStyle.of(context);
      final android = Theme.of(context).platform == TargetPlatform.android;
      final titleStyle = DefaultTextStyle.of(context).style.copyWith(
        fontSize: 27,
        fontWeight: FontWeight.w700,
        color: style.text,
      );
      final compactStyle = titleStyle.copyWith(fontSize: 17);
      final subtitleStyle = TextStyle(fontSize: 15, color: style.secondary);
      final scaler = MediaQuery.textScalerOf(context);
      final titlePainter = TextPainter(
        text: TextSpan(text: widget.title, style: titleStyle),
        textDirection: Directionality.of(context),
        textScaler: scaler,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0, constraints.maxWidth - 36));
      final titleHeight = widget.showExpandedTitle
          ? titlePainter.height + 3
          : 0;
      titlePainter
        ..text = TextSpan(text: widget.subtitle, style: subtitleStyle)
        ..maxLines = widget.subtitleMaxLines
        ..layout(maxWidth: math.max(0, constraints.maxWidth - 36));
      final subtitleHeight = math.max(titlePainter.height, scaler.scale(20));
      final safe = MediaQuery.paddingOf(context);
      final side =
          math.max(
            safe.left + (widget.leading == null ? 0 : 52),
            safe.right + (widget.trailing == null ? 0 : 52),
          ) +
          16;
      final maxNameWidth = math.max(
        0.0,
        constraints.maxWidth -
            2 * side -
            _ProfileHeader._compactAvatar -
            _ProfileHeader._compactGap,
      );
      titlePainter
        ..text = TextSpan(text: widget.title, style: compactStyle)
        ..maxLines = 1
        ..layout(maxWidth: maxNameWidth);
      final compactNameWidth = math.min(
        maxNameWidth,
        titlePainter.width.ceilToDouble(),
      );
      titlePainter.dispose();
      final collapsedHeight = widget.padding.top + _ProfileHeader.toolbarHeight;
      _travel = 10 + widget.avatarSize + 13 + titleHeight + subtitleHeight + 18;
      final expandedHeight = collapsedHeight + _travel;
      _headerOverlapsContent = _scroll.hasClients && _scroll.offset > _travel;
      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _beginGesture(),
        onPointerPanZoomStart: (_) => _beginGesture(),
        onPointerSignal: (_) => _beginGesture(),
        child: MeshScrollViewport(
          tint: widget.backgroundColor ?? style.canvas,
          fadeTop: false,
          edgeExtent: math.max(18.0, widget.padding.bottom),
          blur: widget.backgroundColor == null,
          child: CustomScrollView(
            controller: _scroll,
            // Let glass buttons stretch over the expanded header's lower edge.
            // Paint the compact toolbar over content once it starts overlapping.
            paintOrder: useIosControls && !_headerOverlapsContent
                ? SliverPaintOrder.lastIsTop
                : SliverPaintOrder.firstIsTop,
            // Material's stretch transforms the entire viewport, including the
            // pinned toolbar. Move the sliver content using scroll physics.
            scrollBehavior: android
                ? ScrollConfiguration.of(context).copyWith(overscroll: false)
                : null,
            physics: _ProfileScrollPhysics(
              travel: () => _travel,
              keepCollapsed: () => _keepCollapsed,
              pinLeadingEdge: android,
              parent: android ? const BouncingScrollPhysics() : null,
            ),
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _ProfileHeader(
                  page: widget,
                  minExtent: collapsedHeight,
                  maxExtent: expandedHeight,
                  titleStyle: titleStyle,
                  subtitleStyle: subtitleStyle,
                  compactStyle: compactStyle,
                  compactNameWidth: compactNameWidth,
                  wallpaper: switch (widget.identity) {
                    final identity? => ProfileWallpaper(
                      identity: identity,
                      coverage: expandedHeight,
                    ),
                    null => null,
                  },
                ),
              ),
              SliverPadding(
                padding: widget.padding.copyWith(top: 0),
                sliver: SliverList.list(children: widget.children),
              ),
              SliverLayoutBuilder(
                builder: (context, layout) => SliverToBoxAdapter(
                  child: SizedBox(
                    height: math.max(
                      0,
                      layout.viewportMainAxisExtent +
                          _travel -
                          layout.precedingScrollExtent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _ProfileHeader extends SliverPersistentHeaderDelegate {
  const _ProfileHeader({
    required this.page,
    required this.minExtent,
    required this.maxExtent,
    required this.titleStyle,
    required this.subtitleStyle,
    required this.compactStyle,
    required this.compactNameWidth,
    required this.wallpaper,
  });

  static const toolbarHeight = 64.0;
  static const _compactAvatar = 32.0;
  static const _compactGap = 10.0;

  final ProfilePage page;
  @override
  final double minExtent, maxExtent;
  final TextStyle titleStyle, subtitleStyle, compactStyle;
  final double compactNameWidth;
  final Widget? wallpaper;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final travel = maxExtent - minExtent;
    final offset = shrinkOffset.clamp(0.0, travel);
    final progress = offset / travel;
    final expandedOpacity = (1 - progress / .54).clamp(0.0, 1.0);
    final compactOpacity = ((progress - .61) / .34).clamp(0.0, 1.0);
    final toolbarOpacity = (1 - progress / .56).clamp(0.0, 1.0);
    final backdropFade = Curves.easeInOut.transform(
      ((progress - .65) / .35).clamp(0.0, 1.0),
    );
    final canvas = page.backgroundColor ?? MeshStyle.of(context).canvas;
    final safeTop = page.padding.top;
    final safeArea = MediaQuery.paddingOf(context);
    final leadingX = 16.0 + safeArea.left;
    final trailingX = 16.0 + safeArea.right;
    final toolbarCenter = safeTop + toolbarHeight / 2;
    final expandedTitleTop = minExtent + 10 + page.avatarSize + 13;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backdropFade == 0 ? canvas : null,
        gradient: backdropFade == 0
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  canvas.withValues(alpha: 1 - .08 * backdropFade),
                  canvas.withValues(alpha: 1 - .24 * backdropFade),
                  canvas.withValues(alpha: 1 - .46 * backdropFade),
                  canvas.withValues(alpha: 1 - backdropFade),
                ],
                stops: const [0, .42, .69, 1],
              ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compactWidth =
              _compactAvatar +
              (compactNameWidth > 0 ? _compactGap + compactNameWidth : 0);
          final compactX = (constraints.maxWidth - compactWidth) / 2;
          final avatarX = lerpDouble(
            (constraints.maxWidth - page.avatarSize) / 2,
            compactX,
            progress,
          )!;
          final avatarScale = lerpDouble(
            1,
            _compactAvatar / page.avatarSize,
            progress,
          )!;
          final nameX = avatarX + page.avatarSize * avatarScale + _compactGap;
          final nameWidth = math.min(
            compactNameWidth,
            constraints.maxWidth -
                trailingX -
                (page.trailing == null ? 0 : 52) -
                nameX,
          );
          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (wallpaper case final wallpaper? when progress < 1)
                  Positioned(
                    top: -offset,
                    height: maxExtent,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: ((1 - progress) / .30).clamp(0.0, 1.0),
                        child: wallpaper,
                      ),
                    ),
                  ),
                if (expandedOpacity > 0)
                  Positioned(
                    top: expandedTitleTop - offset * .72,
                    left: 18,
                    right: 18,
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: expandedOpacity,
                        child: Column(
                          children: [
                            if (page.showExpandedTitle) ...[
                              Semantics(
                                header: true,
                                child: Text(
                                  page.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: titleStyle,
                                ),
                              ),
                              const SizedBox(height: 3),
                            ],
                            Text(
                              page.subtitle,
                              maxLines: page.subtitleMaxLines,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: subtitleStyle,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (page.heading case final heading? when toolbarOpacity > 0)
                  Positioned(
                    top: safeTop,
                    height: toolbarHeight,
                    left: leadingX + 48,
                    right: trailingX + 48,
                    child: Center(
                      child: Opacity(
                        opacity: toolbarOpacity,
                        child: Text(
                          heading,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle.copyWith(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: lerpDouble(
                    minExtent + 10,
                    toolbarCenter - _compactAvatar / 2,
                    progress,
                  ),
                  left: avatarX,
                  width: page.avatarSize,
                  height: page.avatarSize,
                  child: IgnorePointer(
                    child: Transform.scale(
                      alignment: Alignment.topLeft,
                      scale: avatarScale,
                      child: page.avatar,
                    ),
                  ),
                ),
                if (compactOpacity > 0 && nameWidth > 0)
                  Positioned(
                    top: safeTop,
                    height: toolbarHeight,
                    left: nameX,
                    width: nameWidth,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Opacity(
                        opacity: compactOpacity,
                        child: Semantics(
                          header: true,
                          child: Text(
                            page.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: compactStyle,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (page.leading case final leading?)
                  Positioned(
                    left: leadingX,
                    top: safeTop,
                    height: toolbarHeight,
                    child: Center(child: leading),
                  ),
                if (page.trailing case final trailing?)
                  Positioned(
                    right: trailingX,
                    top: safeTop,
                    height: toolbarHeight,
                    child: Center(child: trailing),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  bool shouldRebuild(_ProfileHeader oldDelegate) =>
      page != oldDelegate.page ||
      minExtent != oldDelegate.minExtent ||
      maxExtent != oldDelegate.maxExtent ||
      titleStyle != oldDelegate.titleStyle ||
      subtitleStyle != oldDelegate.subtitleStyle ||
      compactNameWidth != oldDelegate.compactNameWidth;
}

class _ProfileScrollPhysics extends ScrollPhysics {
  const _ProfileScrollPhysics({
    required this.travel,
    required this.keepCollapsed,
    required this.pinLeadingEdge,
    super.parent,
  });

  final double Function() travel;
  final bool Function() keepCollapsed;
  final bool pinLeadingEdge;

  @override
  _ProfileScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _ProfileScrollPhysics(
        travel: travel,
        keepCollapsed: keepCollapsed,
        pinLeadingEdge: pinLeadingEdge,
        parent: buildParent(ancestor),
      );

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    final stop = travel();
    if (keepCollapsed() && position.pixels >= stop && value < stop) {
      return value - stop;
    }
    if (pinLeadingEdge && value < position.minScrollExtent) {
      return value - position.minScrollExtent;
    }
    return super.applyBoundaryConditions(position, value);
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final stop = travel();
    final offset = position.pixels;
    if (offset > 0 && offset < stop && !position.outOfRange) {
      final collapse = velocity.abs() > 360 ? velocity > 0 : offset >= stop / 2;
      final target = collapse ? stop : 0.0;
      final speedLimit = (target - offset).abs() * 12;
      return ScrollSpringSimulation(
        SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: 1),
        offset,
        target,
        velocity.clamp(-speedLimit, speedLimit),
        tolerance: toleranceFor(position),
      );
    }
    return super.createBallisticSimulation(position, velocity);
  }
}
