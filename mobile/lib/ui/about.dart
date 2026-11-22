// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_name.dart';
import 'page_route.dart';
import 'profile_page.dart';
import 'style.dart';

const _assetDir = 'assets/about';
const _appInfo = MethodChannel('meshgrame/app_info');

typedef _BuildInfo = ({String version, String number, DateTime? date});

Future<_BuildInfo?> _loadBuildInfo() async {
  try {
    final values = await _appInfo.invokeMapMethod<String, String>('buildInfo');
    if (values == null ||
        values['version'] == null ||
        values['number'] == null) {
      return null;
    }
    return (
      version: values['version']!,
      number: values['number']!,
      date: DateTime.tryParse(values['date'] ?? '')?.toLocal(),
    );
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final _info = _loadBuildInfo();

  Widget _row(String title, IconData icon, Widget page) => MeshRow(
    title: title,
    icon: icon,
    tint: MeshStyle.of(context).accent,
    onTap: () => _push(context, page),
  );

  @override
  Widget build(BuildContext context) {
    final agreement = tr(
      context,
      'Лицензионное соглашение',
      'License agreement',
    );
    final privacy = tr(
      context,
      'Политика конфиденциальности',
      'Privacy policy',
    );
    final licenses = tr(context, 'Лицензии', 'Licenses');
    return Scaffold(
      body: FutureBuilder<_BuildInfo?>(
        future: _info,
        builder: (context, snapshot) {
          final info = snapshot.data;
          final date = info?.date;
          final formattedDate = date == null
              ? null
              : MaterialLocalizations.of(context).formatCompactDate(date);
          final buildText = info == null
              ? snapshot.connectionState == ConnectionState.done
                    ? tr(
                        context,
                        'Данные сборки недоступны',
                        'Build information unavailable',
                      )
                    : ''
              : [
                  tr(
                    context,
                    'Версия ${info.version}',
                    'Version ${info.version}',
                  ),
                  tr(context, 'Сборка ${info.number}', 'Build ${info.number}'),
                  if (formattedDate != null)
                    tr(
                      context,
                      'Дата сборки $formattedDate',
                      'Build date $formattedDate',
                    ),
                ].join('\n');
          return ProfilePage(
            heading: tr(context, 'О приложении', 'About'),
            title: appName,
            showExpandedTitle: false,
            subtitle: buildText,
            subtitleMaxLines: 3,
            avatarSize: 116,
            avatar: ClipRRect(
              borderRadius: BorderRadius.circular(27),
              child: Image.asset(
                '$_assetDir/meshgrame-icon.png',
                fit: BoxFit.cover,
              ),
            ),
            padding: meshScrollPadding(
              context,
              const EdgeInsets.only(bottom: 20),
            ),
            leading: _back(context),
            trailing: info == null
                ? null
                : GlassButton(
                    icon: Icons.copy_rounded,
                    label: tr(
                      context,
                      'Копировать данные сборки',
                      'Copy build information',
                    ),
                    onTap: () async {
                      await Clipboard.setData(
                        ClipboardData(text: '$appName\n$buildText'),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              tr(
                                context,
                                'Данные сборки скопированы',
                                'Build information copied',
                              ),
                            ),
                          ),
                        );
                      }
                    },
                  ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: MeshGroup(
                  children: [
                    _row(
                      agreement,
                      Icons.article_outlined,
                      _DocumentPage(
                        title: agreement,
                        asset: '$_assetDir/license-agreement.md',
                      ),
                    ),
                    _row(
                      privacy,
                      Icons.privacy_tip_outlined,
                      _DocumentPage(
                        title: privacy,
                        asset: '$_assetDir/privacy-policy.md',
                      ),
                    ),
                    _row(
                      licenses,
                      Icons.balance_rounded,
                      _LicensesPage(title: licenses),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

void _push(BuildContext context, Widget page) => unawaited(
  Navigator.of(context)
      .push(meshPageRoute<void>(context, builder: (_) => page)),
);

GlassButton _back(BuildContext context) => GlassButton(
  icon: Icons.arrow_back_ios_new_rounded,
  label: tr(context, 'Назад', 'Back'),
  onTap: () => Navigator.of(context).pop(),
);

Future<void> _openLink(BuildContext context, String url) async {
  final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.inAppWebView);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(context, 'Не удалось открыть ссылку', 'Could not open link'),
        ),
      ),
    );
  }
}

class _DocumentPage extends StatefulWidget {
  const _DocumentPage({required this.title, this.asset, this.text, this.url});

  final String title;
  final String? asset, text, url;

  @override
  State<_DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<_DocumentPage> {
  late final _content = widget.asset == null
      ? Future.value(widget.text ?? '')
      : rootBundle
            .loadString(widget.asset!)
            .then((body) => [?widget.text, body].join('\n\n'));
  static final _externalLink = RegExp(r'^\[(.+)\]\((https://[^\s)]+)\)$');

  @override
  Widget build(BuildContext context) {
    final style = MeshStyle.of(context);
    return FutureBuilder<String>(
      future: _content,
      builder: (context, snapshot) {
        final legalText = widget.asset?.endsWith('.md') ?? false;
        final body = snapshot.data?.trim();
        return Scaffold(
          body: PinnedPageList(
            padding: meshScrollPadding(
              context,
              const EdgeInsets.only(bottom: 20),
            ),
            header: PageHeading(widget.title, leading: _back(context)),
            children: [
              if (snapshot.hasError)
                _paragraph(
                  tr(context, 'Документ недоступен', 'Document unavailable'),
                  style,
                )
              else if (body == null)
                const Center(child: CircularProgressIndicator())
              else if (legalText) ...[
                for (final block in body.split(RegExp(r'\r?\n\s*\r?\n')))
                  if (!block.startsWith('# ')) _legalBlock(block, style),
              ] else if (body.isNotEmpty)
                _paragraph(body, style),
              if (widget.url case final url?)
                TextButton(
                  onPressed: () => _openLink(context, url),
                  child: Text(
                    tr(context, 'Источник и условия', 'Source and terms'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _legalBlock(String block, MeshStyle style) {
    if (block.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
        child: Semantics(
          header: true,
          child: Text(
            block.substring(3),
            style: TextStyle(
              color: style.text,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    if (_externalLink.firstMatch(block) case final link?) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextButton(
            onPressed: () => _openLink(context, link[2]!),
            child: Text(link[1]!),
          ),
        ),
      );
    }
    return _paragraph(block, style);
  }

  Widget _paragraph(String text, MeshStyle style) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: SelectableText(
      text,
      style: TextStyle(color: style.text, fontSize: 15, height: 1.48),
    ),
  );
}

typedef _Notice = ({
  String title,
  String license,
  String? asset,
  String? text,
  String? url,
});

const _licenseNames = {
  'flutterblueplus license version 1.6': 'FlutterBluePlus License 1.6',
  'flutterblueplus license': 'FlutterBluePlus License',
  'apache license': 'Apache-2.0',
  'gnu lesser general public license': 'LGPL',
  'gnu general public license': 'GPL',
  'mozilla public license': 'MPL',
  'sil open font license': 'OFL',
  'neither the name of the': 'BSD-3-Clause',
  'permission is hereby granted, free of charge, to any person obtaining':
      'MIT',
  'bsd-style license': 'BSD',
  'redistribution and use in source and binary forms': 'BSD',
  'public domain': 'Public domain',
};

Future<List<_Notice>> _loadNotices() async {
  final extra = jsonDecode(
    await rootBundle.loadString('$_assetDir/third-party.json'),
  ) as List;
  final android = defaultTargetPlatform == TargetPlatform.android;
  final entries = <String, List<(String?, String)>>{};
  await for (final entry in LicenseRegistry.licenses) {
    final body = entry.paragraphs
        .map((paragraph) => paragraph.text)
        .join('\n\n');
    final normalized = body.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    final type = _licenseNames.entries
        .where((item) => normalized.contains(item.key))
        .firstOrNull
        ?.value;
    for (final package in entry.packages) {
      entries.putIfAbsent(package, () => []).add((type, body));
    }
  }
  return [
    for (final item in extra)
      if (item['platform'] != 'android' || android)
        (
          title: item['title'] as String,
          license: item['license'] as String,
          asset: item['asset'] as String?,
          text: item['text'] as String?,
          url: item['url'] as String?,
        ),
    for (final entry
        in entries.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
      (
        title: entry.key,
        license: entry.value
            .map((item) => item.$1)
            .nonNulls
            .toSet()
            .join(' · '),
        asset: null,
        text: entry.value
            .map((item) => item.$2)
            .toSet()
            .join('\n\n————————\n\n'),
        url: null,
      ),
  ];
}

class _LicensesPage extends StatefulWidget {
  const _LicensesPage({required this.title});
  final String title;

  @override
  State<_LicensesPage> createState() => _LicensesPageState();
}

class _LicensesPageState extends State<_LicensesPage> {
  late final _notices = _loadNotices();

  @override
  Widget build(BuildContext context) {
    final padding = meshScrollPadding(
      context,
      const EdgeInsets.only(bottom: 20),
    );
    final style = MeshStyle.of(context);
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: padding.copyWith(bottom: 0),
            child: PageHeading(widget.title, leading: _back(context)),
          ),
          Expanded(
            child: FutureBuilder<List<_Notice>>(
              future: _notices,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      tr(
                        context,
                        'Лицензии недоступны',
                        'Licenses unavailable',
                      ),
                    ),
                  );
                }
                final rows = snapshot.data;
                if (rows == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView.separated(
                  padding: padding.copyWith(
                    top: 0,
                    left: padding.left + 16,
                    right: padding.right + 16,
                  ),
                  itemCount: rows.length,
                  separatorBuilder: (context, index) =>
                      Divider(height: 1, color: style.separator),
                  itemBuilder: (context, index) {
                    final notice = rows[index];
                    return MeshRow(
                      title: notice.title,
                      subtitle: notice.license.isEmpty
                          ? tr(
                              context,
                              'Уведомление правообладателя',
                              'Copyright notice',
                            )
                          : notice.license,
                      icon: Icons.description_outlined,
                      tint: style.accent,
                      onTap: () => _push(
                        context,
                        _DocumentPage(
                          title: notice.title,
                          asset: notice.asset,
                          text: notice.text,
                          url: notice.url,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
