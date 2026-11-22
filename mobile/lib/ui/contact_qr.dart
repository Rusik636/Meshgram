import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../app_name.dart';
import '../mesh/controller.dart';
import '../mesh/network.dart';
import 'ios_control.dart';
import 'qr_scanner.dart';
import 'style.dart';
import 'page_route.dart';

Future<Peer?> showContactQr(
  BuildContext context, {
  required MeshController controller,
  required Peer peer,
  required Uri code,
  required Object heroTag,
}) {
  Widget page(BuildContext _) => _ContactQrPage(
    controller: controller,
    name: peer.name,
    code: code.toString(),
    heroTag: heroTag,
  );
  if (useIosControls) {
    return Navigator.push(context, meshPageRoute<Peer>(context, builder: page));
  }
  return Navigator.push<Peer>(
    context,
    PageRouteBuilder<Peer>(
      opaque: false,
      allowSnapshotting: false,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, _, _) => page(context),
      transitionsBuilder: (context, animation, _, child) =>
          MediaQuery.disableAnimationsOf(context)
          ? child
          : FadeTransition(
              opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
              child: child,
            ),
    ),
  );
}

Future<void> showChannelQr(
  BuildContext context, {
  required String name,
  required String invitation,
  String? network,
}) => Navigator.push<void>(
  context,
  meshPageRoute(
    context,
    builder: (_) =>
        _ContactQrPage(name: name, code: invitation, network: network),
  ),
);

Future<void> showPeerChannelQr(
  BuildContext context,
  MeshController controller,
  Peer peer,
) async {
  try {
    final network = controller.active?.network;
    final invitation = await controller.shareChannel(peer);
    if (context.mounted) {
      await showChannelQr(
        context,
        name: peer.name,
        invitation: invitation,
        network: network == null ? null : controller.label(network),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              context,
              'Не удалось прочитать ключ канала с рации',
              'Could not read the channel key from the radio',
            ),
          ),
        ),
      );
    }
  }
}

class _ContactQrPage extends StatefulWidget {
  const _ContactQrPage({
    required this.name,
    required this.code,
    this.controller,
    this.network,
    this.heroTag,
  });

  final MeshController? controller;
  final String name, code;
  final String? network;
  final Object? heroTag;

  @override
  State<_ContactQrPage> createState() => _ContactQrState();
}

class _ContactQrState extends State<_ContactQrPage>
    with SingleTickerProviderStateMixin {
  final _card = GlobalKey();
  final _shareButton = GlobalKey();
  AnimationController? _reveal;
  bool _exporting = false, _closing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!useIosControls || widget.heroTag == null) return;
    final reveal = _reveal ??= AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
      reverseDuration: const Duration(milliseconds: 260),
    );
    if (_closing) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      reveal.value = 1;
    } else if (reveal.isDismissed) {
      reveal.forward();
    }
  }

  @override
  void dispose() {
    _reveal?.dispose();
    super.dispose();
  }

  Future<void> _close([Peer? peer]) async {
    if (_closing) return;
    _closing = true;
    if (_reveal case final reveal?
        when !MediaQuery.disableAnimationsOf(context)) {
      try {
        await reveal.reverse().orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (mounted) Navigator.pop(context, peer);
  }

  Future<void> _shareLink() async {
    if (_exporting || _closing) return;
    final anchor = _shareButton.currentContext?.findRenderObject();
    if (anchor is! RenderBox || !anchor.hasSize) return;
    setState(() => _exporting = true);
    try {
      await SharePlus.instance.share(
        ShareParams(
          uri: Uri.parse(widget.code),
          sharePositionOrigin: anchor.localToGlobal(Offset.zero) & anchor.size,
        ),
      );
    } catch (_) {
      if (mounted) {
        _notice(
          tr(
            context,
            'Не удалось поделиться ссылкой',
            'Could not share the link',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _saveCode() async {
    if (_exporting || _closing) return;
    final boundary = _card.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return;
    setState(() => _exporting = true);
    try {
      final image = await boundary.toImage(pixelRatio: 4);
      final Uint8List data;
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) throw StateError('QR rendering unavailable');
        data = png.buffer.asUint8List();
      } finally {
        image.dispose();
      }
      if (!mounted) return;
      await Gal.putImageBytes(data, name: '$appName-QR');
      if (mounted) {
        _notice(
          tr(context, 'QR-код сохранён в Фото', 'QR code saved to Photos'),
        );
      }
    } catch (_) {
      if (mounted) {
        _notice(
          tr(
            context,
            'Не удалось сохранить QR-код',
            'Could not save the QR code',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _scan() async {
    if (_closing) return;
    final raw = await Navigator.push<String>(
      context,
      meshPageRoute(
        context,
        builder: (context) => MeshQrScannerPage(
          title: tr(context, 'QR-код контакта', 'Contact QR code'),
        ),
      ),
    );
    if (!mounted || raw == null) return;
    final peer = widget.controller?.findContactCode(raw);
    if (peer != null) {
      await _close(peer);
    } else {
      _notice(
        tr(
          context,
          'Контакт не найден в списке узлов выбранной рации.',
          'Contact not found in the selected radio’s node list.',
        ),
      );
    }
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    final kind = widget.controller?.active?.network;
    final network =
        widget.network ??
        (kind == null ? null : widget.controller?.label(kind));
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-.2, -.25),
            radius: 1.18,
            colors: style.dark
                ? const [
                    Color(0xff273552),
                    Color(0xff141b2b),
                    Color(0xff080a0f),
                  ]
                : const [
                    Color(0xfff1faff),
                    Color(0xffdbe9fa),
                    Color(0xffc9d8ed),
                  ],
          ),
        ),
        child: SafeArea(
          minimum: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Paint the entire QR card before inserting any UIKit surfaces.
              Positioned.fill(
                top: 48,
                bottom: 56,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final reduceMotion = MediaQuery.disableAnimationsOf(
                      context,
                    );
                    final animateContact =
                        widget.heroTag != null && !reduceMotion;
                    final nativeContact = animateContact && useIosControls;
                    final textScaler = MediaQuery.textScalerOf(context);
                    final labelHeight =
                        textScaler.scale(20) +
                        (network == null ? 0 : textScaler.scale(13));
                    final width = (constraints.maxHeight - labelHeight - 54)
                        .clamp(144.0, 312.0)
                        .clamp(0.0, constraints.maxWidth);
                    final card = SizedBox(
                      width: width,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xfff8fbff),
                          borderRadius: BorderRadius.circular(27),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              QrImageView(
                                data: widget.code,
                                size: (width - 40).clamp(0.0, 272.0),
                                version: QrVersions.auto,
                                errorCorrectionLevel: QrErrorCorrectLevel.M,
                                padding: const EdgeInsets.all(10),
                                backgroundColor: const Color(0xfff8fbff),
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.square,
                                  color: Color(0xff101a2b),
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.square,
                                  color: Color(0xff101a2b),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                widget.name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xff101a2b),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (network != null)
                                Text(
                                  network,
                                  style: const TextStyle(
                                    color: Color(0xff506585),
                                    fontSize: 13,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                    final photo = RepaintBoundary(key: _card, child: card);
                    Widget content = photo;
                    if (nativeContact) {
                      // Animate within the new page after the previous page
                      // has left the UIKit compositor.
                      final progress = _reveal!.drive(
                        CurveTween(curve: Curves.easeOutCubic),
                      );
                      final origin = Offset(
                        constraints.maxWidth / 2 - 24,
                        -constraints.maxHeight / 2 - 24,
                      );
                      content = AnimatedBuilder(
                        animation: progress,
                        child: photo,
                        builder: (context, child) => Transform.translate(
                          offset: origin * (1 - progress.value),
                          child: Transform.scale(
                            scale: .14 + .86 * progress.value,
                            child: child,
                          ),
                        ),
                      );
                    } else if (animateContact) {
                      content = Hero(
                        tag: widget.heroTag!,
                        createRectTween: (begin, end) =>
                            MaterialRectCenterArcTween(begin: begin, end: end),
                        flightShuttleBuilder: (_, _, _, _, _) =>
                            FittedBox(fit: BoxFit.contain, child: card),
                        child: photo,
                      );
                    }
                    return Center(
                      child: SingleChildScrollView(
                        clipBehavior: nativeContact ? Clip.none : Clip.hardEdge,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: content,
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 48,
                child: PageHeading(
                  widget.controller == null
                      ? tr(context, 'QR-код канала', 'Channel QR code')
                      : tr(context, 'QR-код контакта', 'Contact QR code'),
                  padding: EdgeInsets.zero,
                ),
              ),
              PositionedDirectional(
                start: 0,
                top: 0,
                child: GlassButton(
                  icon: Icons.close_rounded,
                  label: tr(context, 'Закрыть', 'Close'),
                  onTap: () => unawaited(_close()),
                ),
              ),
              if (widget.controller != null)
                PositionedDirectional(
                  end: 0,
                  top: 0,
                  child: GlassButton(
                    icon: Icons.qr_code_scanner_rounded,
                    label: tr(context, 'Сканировать QR-код', 'Scan a QR code'),
                    onTap: () => unawaited(_scan()),
                  ),
                ),
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GlassButton(
                      key: _shareButton,
                      icon: Icons.ios_share_rounded,
                      label: tr(context, 'Поделиться', 'Share'),
                      onTap: _exporting ? null : () => unawaited(_shareLink()),
                    ),
                    const SizedBox(width: 16),
                    GlassButton(
                      icon: Icons.download_rounded,
                      label: tr(context, 'Сохранить QR-код', 'Save QR code'),
                      onTap: _exporting ? null : () => unawaited(_saveCode()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
