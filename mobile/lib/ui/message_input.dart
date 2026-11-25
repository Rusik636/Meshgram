// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat_workspace.dart' show meshDesktop;
import 'ios_control.dart';
import 'sheet_control_clip.dart';
import 'style.dart';

typedef MessageInputAccessory = ({
  String title,
  String text,
  Uint8List? image,
  bool link,
});

class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onSend,
    this.enabled = true,
    this.coveredByModal = false,
    this.hidesMovingText = false,
    this.accessory,
    this.onOpenAccessory,
    this.onDismissAccessory,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSend;
  final bool enabled, coveredByModal, hidesMovingText;
  final MessageInputAccessory? accessory;
  final VoidCallback? onOpenAccessory, onDismissAccessory;

  @override
  MessageInputState createState() => MessageInputState();
}

class MessageInputState extends State<MessageInput> {
  final _focus = FocusNode();
  final _flutterEditor = GlobalKey();
  final _nativeEditor = GlobalKey();
  bool _pendingFocus = false;

  void dismissKeyboard() {
    _pendingFocus = false;
    _focus.unfocus();
    if (_native) _send('dismissKeyboard', true);
  }

  void focusInput() {
    if (!widget.enabled || widget.coveredByModal) return;
    if (_native) {
      _pendingFocus = _channel == null;
      _send('focus', true);
    } else {
      _focus.requestFocus();
    }
  }

  Future<Rect?> textBounds(RenderObject ancestor) async {
    final key = _native ? _nativeEditor : _flutterEditor;
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero, ancestor: ancestor);
    if (!_native) {
      if (meshDesktop(context)) {
        final editor = _focus.context
            ?.findAncestorStateOfType<EditableTextState>()
            ?.renderEditable;
        if (editor != null && editor.hasSize) {
          return editor.localToGlobal(Offset.zero, ancestor: ancestor) &
              editor.size;
        }
      }
      return Rect.fromLTWH(
        origin.dx + 16,
        origin.dy + 14,
        (box.size.width - 32).clamp(0.0, double.infinity),
        (box.size.height - 28).clamp(0.0, double.infinity),
      );
    }
    try {
      final frame = await _channel?.invokeListMethod<num>('textBounds');
      if (frame == null || frame.length != 4) return null;
      return Rect.fromLTWH(
        origin.dx + frame[0],
        origin.dy + frame[1],
        frame[2].toDouble(),
        frame[3].toDouble(),
      );
    } on MissingPluginException {
      return null;
    }
  }

  MethodChannel? _channel;
  TextEditingValue? _nativeValue;
  Map<String, Object>? _appearance;
  Map<String, Object>? _nativeAccessory;
  double _height = 46;
  bool _accessoryHeightChanging = false;
  Duration _heightDuration = const Duration(milliseconds: 100);

  bool get _native => useIosControls;

  @override
  void initState() {
    super.initState();
    if (_native) widget.controller.addListener(_syncEditing);
  }

  @override
  void didUpdateWidget(MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final enabledChanged = widget.enabled != oldWidget.enabled;
    if (enabledChanged && !widget.enabled) dismissKeyboard();
    if (_native && oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncEditing);
      widget.controller.addListener(_syncEditing);
      _syncEditing();
    }
    if (_native &&
        (enabledChanged ||
            widget.coveredByModal != oldWidget.coveredByModal ||
            widget.hidesMovingText != oldWidget.hidesMovingText)) {
      if (widget.coveredByModal) _pendingFocus = false;
      _syncAppearance();
      if (enabledChanged && widget.enabled) {
        _send('editing', _editingArguments(widget.controller.value));
      }
    }
    if (_native && widget.accessory != oldWidget.accessory) {
      _accessoryHeightChanging =
          (widget.accessory == null) != (oldWidget.accessory == null);
      _syncAccessory();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_native) {
      _syncAppearance();
      _syncAccessory();
    }
  }

  void _syncAccessory() {
    final accessory = _accessoryArguments;
    if (!mapEquals(accessory, _nativeAccessory)) {
      _nativeAccessory = accessory;
      _send('accessory', accessory);
    }
  }

  Map<String, Object> get _accessoryArguments {
    final accessory = widget.accessory;
    if (accessory == null) return const {};
    return {
      'title': accessory.title,
      'text': accessory.text,
      'image': ?accessory.image,
      'openLabel': accessory.link
          ? tr(context, 'Открыть ссылку', 'Open link')
          : tr(
              context,
              'Перейти к исходному сообщению',
              'Go to original message',
            ),
      'dismissLabel': accessory.link
          ? tr(context, 'Убрать предпросмотр', 'Remove preview')
          : tr(context, 'Отменить ответ', 'Cancel reply'),
    };
  }

  void _syncAppearance() {
    final style = MeshStyle.of(context);
    final appearance = <String, Object>{
      'enabled': widget.enabled,
      'coveredByModal': widget.coveredByModal,
      'hidesMovingText': widget.hidesMovingText,
      'placeholder': tr(context, 'Сообщение', 'Message'),
      'dark': style.dark,
      'highContrast': MediaQuery.highContrastOf(context),
      'surface': style.surface.toARGB32(),
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

  Map<String, Object> _editingArguments(TextEditingValue value) {
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);
    return {'text': value.text, 'start': selection.start, 'end': selection.end};
  }

  void _syncEditing() {
    final value = widget.controller.value;
    if (value.text == _nativeValue?.text &&
        value.selection == _nativeValue?.selection) {
      return;
    }
    _nativeValue = value;
    _send('editing', _editingArguments(value));
  }

  void _created(int id) {
    final channel = _channel = MethodChannel('meshgrame/composer/$id');
    channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'editing':
          if (!widget.enabled) return;
          final arguments = call.arguments as Map;
          final text = arguments['text'] as String;
          final next = TextEditingValue(
            text: text,
            selection: TextSelection(
              baseOffset: arguments['start'] as int,
              extentOffset: arguments['end'] as int,
            ),
          );
          final changed = widget.controller.text != text;
          _nativeValue = next;
          if (widget.controller.value != next) widget.controller.value = next;
          if (changed) widget.onChanged(text);
        case 'height':
          final height = (call.arguments as num).toDouble().clamp(42.0, 240.0);
          if (height != _height) {
            setState(() {
              _height = height;
              _heightDuration = _accessoryHeightChanging
                  ? const Duration(milliseconds: 400)
                  : const Duration(milliseconds: 100);
              _accessoryHeightChanging = false;
            });
          }
        case 'openAccessory':
          widget.onOpenAccessory?.call();
        case 'dismissAccessory':
          widget.onDismissAccessory?.call();
      }
    });
    _nativeValue = null;
    _syncEditing();
    if (_appearance case final appearance?) _send('appearance', appearance);
    _send('accessory', _accessoryArguments);
    if (_pendingFocus) focusInput();
  }

  @override
  void dispose() {
    if (_native) widget.controller.removeListener(_syncEditing);
    _channel?.setMethodCallHandler(null);
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _handleDesktopKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (!widget.enabled ||
        widget.coveredByModal ||
        !_focus.hasPrimaryFocus ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        (key != LogicalKeyboardKey.enter &&
            key != LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }
    final pressed = LogicalKeyboardKey.collapseSynonyms({
      ...HardwareKeyboard.instance.logicalKeysPressed,
      // macOS can report a modifier without its left/right hardware flag.
      if (Theme.of(context).platform == TargetPlatform.macOS)
        // ignore: deprecated_member_use
        ...RawKeyboard.instance.keysPressed,
    });
    if (pressed.contains(LogicalKeyboardKey.control) ||
        pressed.contains(LogicalKeyboardKey.meta) ||
        pressed.contains(LogicalKeyboardKey.alt)) {
      return KeyEventResult.ignored;
    }
    final value = widget.controller.value;
    if (value.isComposingRangeValid && !value.composing.isCollapsed) {
      return KeyEventResult.skipRemainingHandlers;
    }
    if (pressed.contains(LogicalKeyboardKey.shift)) {
      final editorContext = _focus.context;
      if (editorContext == null || !value.selection.isValid) {
        return KeyEventResult.ignored;
      }
      Actions.maybeInvoke(
        editorContext,
        ReplaceTextIntent(
          value.copyWith(
            selection: TextSelection.collapsed(offset: value.selection.end),
          ),
          '\n',
          value.selection,
          SelectionChangedCause.keyboard,
        ),
      );
    } else if (event is KeyDownEvent) {
      widget.onSend?.call();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    if (_native) {
      return TweenAnimationBuilder<double>(
        tween: Tween(end: _height),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : _heightDuration,
        curve: Curves.easeInOut,
        builder: (context, height, editor) =>
            SizedBox(height: height, child: editor),
        child: MeshIosGlassFrame(
          child: MeshSheetControlClip(
            child: UiKitView(
              key: _nativeEditor,
              viewType: 'meshgrame/composer',
              creationParams: {
                ...?_appearance,
                ..._editingArguments(widget.controller.value),
                'accessory': _accessoryArguments,
                'visualOutset': meshIosGlassOutset,
              },
              creationParamsCodec: const StandardMessageCodec(),
              gestureRecognizers: {
                Factory<OneSequenceGestureRecognizer>(
                  EagerGestureRecognizer.new,
                ),
              },
              onPlatformViewCreated: _created,
            ),
          ),
        ),
      );
    }
    final desktop = meshDesktop(context);
    final field = TextField(
      key: _flutterEditor,
      controller: widget.controller,
      enabled: widget.enabled,
      focusNode: _focus,
      minLines: 1,
      maxLines: 4,
      textCapitalization: TextCapitalization.sentences,
      onChanged: widget.onChanged,
      style: widget.hidesMovingText
          ? const TextStyle(color: Colors.transparent)
          : null,
      showCursor: widget.hidesMovingText ? false : null,
      decoration: InputDecoration(
        hintText: tr(context, 'Сообщение', 'Message'),
        border: InputBorder.none,
        // The non-dense decorator centers short lines within its 48 pt height.
        isDense: !desktop,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
    final editor = desktop
        ? Focus(
            canRequestFocus: false,
            onKeyEvent: _handleDesktopKey,
            child: field,
          )
        : field;
    if (MediaQuery.disableAnimationsOf(context)) return editor;
    return AnimatedSize(
      alignment: Alignment.bottomCenter,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: editor,
    );
  }
}
