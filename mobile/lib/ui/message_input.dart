// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ios_control.dart';
import 'style.dart';

class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.controller,
    required this.onChanged,
    this.coveredByModal = false,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool coveredByModal;

  @override
  MessageInputState createState() => MessageInputState();
}

class MessageInputState extends State<MessageInput> {
  final _focus = FocusNode();
  bool _pendingFocus = false;

  void dismissKeyboard() {
    _pendingFocus = false;
    _focus.unfocus();
    if (_native) _send('dismissKeyboard', true);
  }

  void focusInput() {
    if (widget.coveredByModal) return;
    if (_native) {
      _pendingFocus = _channel == null;
      _send('focus', true);
    } else {
      _focus.requestFocus();
    }
  }

  MethodChannel? _channel;
  String? _nativeText;
  Map<String, Object>? _appearance;
  double _height = 46;

  bool get _native => useIosControls;

  @override
  void initState() {
    super.initState();
    if (_native) widget.controller.addListener(_syncText);
  }

  @override
  void didUpdateWidget(MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_native && oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncText);
      widget.controller.addListener(_syncText);
      _syncText();
    }
    if (_native && widget.coveredByModal != oldWidget.coveredByModal) {
      _pendingFocus = false;
      _syncAppearance();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_native) _syncAppearance();
  }

  void _syncAppearance() {
    final style = MeshStyle.of(context);
    final appearance = <String, Object>{
      'coveredByModal': widget.coveredByModal,
      'placeholder': tr(context, 'Сообщение', 'Message'),
      'dark': style.dark,
      'foreground': style.text.toARGB32(),
      'secondary': style.secondary.toARGB32(),
      'accent': style.accent.toARGB32(),
    };
    if (!mapEquals(appearance, _appearance)) {
      _appearance = appearance;
      _send('appearance', appearance);
    }
  }

  void _send(String method, Object value) {
    final channel = _channel;
    if (channel != null) {
      unawaited(
        channel
            .invokeMethod<void>(method, value)
            .then<void>(
              (_) {},
              onError: (Object error) {
                if (error is! MissingPluginException) throw error;
              },
            ),
      );
    }
  }

  void _syncText() {
    final text = widget.controller.text;
    if (text == _nativeText) return;
    _nativeText = text;
    _send('replaceText', text);
  }

  void _created(int id) {
    final channel = _channel = MethodChannel('meshgrame/composer/$id');
    channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'text':
          final value = call.arguments as String;
          _nativeText = value;
          if (widget.controller.text != value) {
            widget.controller.text = value;
            widget.onChanged(value);
          }
        case 'height':
          final height = (call.arguments as num).toDouble().clamp(42.0, 160.0);
          if (height != _height) setState(() => _height = height);
      }
    });
    _nativeText = null;
    _syncText();
    if (_appearance case final appearance?) _send('appearance', appearance);
    if (_pendingFocus) focusInput();
  }

  @override
  void dispose() {
    if (_native) widget.controller.removeListener(_syncText);
    _channel?.setMethodCallHandler(null);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_native) {
      return SizedBox(
        height: _height,
        child: UiKitView(
          viewType: 'meshgrame/composer',
          creationParams: {...?_appearance, 'text': widget.controller.text},
          creationParamsCodec: const StandardMessageCodec(),
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
          },
          onPlatformViewCreated: _created,
        ),
      );
    }
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      minLines: 1,
      maxLines: 4,
      textCapitalization: TextCapitalization.sentences,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        hintText: tr(context, 'Сообщение', 'Message'),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
