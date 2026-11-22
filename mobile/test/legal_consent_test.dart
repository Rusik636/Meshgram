// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meshgrame/ui/about.dart';
import 'package:meshgrame/ui/legal_consent.dart';

class _Documents extends CachingAssetBundle {
  _Documents(this.documents);
  final Map<String, String> documents;

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(utf8.encode(documents[key]!));
}

void main() {
  test(
    'consent revision follows the documents and Meshgram attribution',
    () async {
      const notices = 'assets/about/third-party.json';
      final docs = {
        agreementAsset: 'agreement',
        privacyAsset: 'policy',
        agplAsset: 'AGPL',
        notices: '[{"title":"Meshgram","text":"notice"}]',
      };
      final original = await legalRevision(_Documents(docs));
      for (final asset in [agreementAsset, privacyAsset, agplAsset, notices]) {
        final changed = {
          ...docs,
          asset: asset == notices
              ? '[{"title":"Meshgram","text":"new notice"}]'
              : 'new document',
        };
        expect(await legalRevision(_Documents(changed)), isNot(original));
      }
      final other = {
        ...docs,
        notices: '[{"title":"Other","text":"other"},{"title":"Meshgram","text":"notice"}]',
      };
      expect(await legalRevision(_Documents(other)), original);
    },
  );

  testWidgets(
    'both documents open before acceptance and both boxes are required',
    (tester) async {
      int starts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LegalConsentPage(
            onAccept: () async {
              starts++;
            },
          ),
        ),
      );
      final button = find.widgetWithText(FilledButton, 'Continue');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      for (final entry in {
        'License agreement': agreementAsset,
        'Privacy policy': privacyAsset,
      }.entries) {
        await tester.tap(find.text(entry.key));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester.widget<DocumentPage>(find.byType(DocumentPage)).asset,
          entry.value,
        );
        Navigator.of(tester.element(find.byType(DocumentPage))).pop();
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }
      final boxes = find.byType(CheckboxListTile);
      await tester.tap(boxes.first);
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(boxes.last);
      await tester.pump();
      await tester.tap(boxes.first);
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(boxes.first);
      await tester.pump();
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(starts, 1);
    },
  );
}
