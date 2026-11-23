// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../app_name.dart';
import 'about.dart';
import 'mesh_icon.dart';
import 'page_route.dart';
import 'style.dart';

const legalConsentKey = 'meshgram.acceptedLegalRevision';

Future<String> legalRevision(AssetBundle bundle) async {
  final texts = await Future.wait([
    for (final path in [agreementAsset, privacyAsset, agplAsset])
      bundle.loadString(path),
  ]);
  final notices = jsonDecode(
    await bundle.loadString('assets/about/third-party.json'),
  ) as List;
  final attribution =
      notices.singleWhere((item) => item['title'] == 'Meshgram')['text']
          as String;
  return sha256
      .convert(utf8.encode(jsonEncode([...texts, attribution])))
      .toString();
}

class LegalConsentPage extends StatefulWidget {
  const LegalConsentPage({super.key, required this.onAccept});
  final Future<void> Function() onAccept;

  @override
  State<LegalConsentPage> createState() => _LegalConsentPageState();
}

class _LegalConsentPageState extends State<LegalConsentPage> {
  bool _license = false;
  bool _privacy = false;
  bool _saving = false;
  bool _failed = false;

  Future<void> _accept() async {
    if (_saving || !_license || !_privacy) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      await widget.onAccept();
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _saving = false;
        });
      }
    }
  }

  Widget _document(
    String title,
    String asset,
    String label,
    bool checked,
    ValueChanged<bool> change,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(title),
          trailing: const MeshIcon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            meshPageRoute<void>(
              context,
              builder: (_) => DocumentPage(title: title, asset: asset),
            ),
          ),
        ),
        CheckboxListTile(
          value: checked,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(label),
          onChanged: _saving
              ? null
              : (value) => setState(() => change(value == true)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = MeshStyle.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(21),
                      child: Image.asset(
                        'assets/about/meshgrame-icon.png',
                        width: 88,
                        height: 88,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    appName,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    tr(
                      context,
                      'Прочитайте и примите оба документа, чтобы продолжить.',
                      'Read and accept both documents to continue.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Material(
                    color: style.surface,
                    borderRadius: BorderRadius.circular(18),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        _document(
                          tr(
                            context,
                            'Лицензионное соглашение',
                            'License agreement',
                          ),
                          agreementAsset,
                          tr(
                            context,
                            'Принимаю лицензионное соглашение',
                            'I accept the license agreement',
                          ),
                          _license,
                          (v) => _license = v,
                        ),
                        const Divider(height: 1),
                        _document(
                          tr(
                            context,
                            'Политика конфиденциальности',
                            'Privacy policy',
                          ),
                          privacyAsset,
                          tr(
                            context,
                            'Принимаю политику конфиденциальности',
                            'I accept the privacy policy',
                          ),
                          _privacy,
                          (v) => _privacy = v,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_failed)
                    Text(
                      tr(
                        context,
                        'Не удалось продолжить. Попробуйте ещё раз.',
                        'Could not continue. Please try again.',
                      ),
                    ),
                  FilledButton(
                    onPressed: _license && _privacy && !_saving
                        ? _accept
                        : null,
                    child: Text(tr(context, 'Продолжить', 'Continue')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
