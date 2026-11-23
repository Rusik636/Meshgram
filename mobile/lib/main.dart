// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_name.dart';
import 'local_notifications.dart';
import 'mesh/controller.dart';
import 'mesh/store.dart';
import 'radio/ble_transport.dart';
import 'radio/lan_transport.dart';
import 'radio/meshcore.dart';
import 'radio/meshtastic.dart';
import 'ui/home.dart';
import 'ui/legal_consent.dart';
import 'ui/mesh_icon.dart';
import 'ui/style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final symbolsReady = prepareMeshIosSymbols();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
  final preferences = await SharedPreferences.getInstance();
  final revision = await legalRevision(rootBundle);
  // Have the same glyphs available before either native buttons or the
  // Flutter controls behind a modal can appear.
  await symbolsReady;
  if (preferences.getString(legalConsentKey) != revision) {
    runApp(
      MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('ru'), Locale('en')],
        theme: const MeshStyle(false).theme(),
        darkTheme: const MeshStyle(true).theme(),
        themeMode: switch (MeshStore(preferences).appearance) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        },
        home: LegalConsentPage(
          onAccept: () async {
            if (!await preferences.setString(legalConsentKey, revision)) {
              throw StateError('Could not save legal consent');
            }
            await _startMessenger(preferences);
          },
        ),
      ),
    );
    return;
  }
  await _startMessenger(preferences);
}

Future<void> _startMessenger(SharedPreferences preferences) async {
  await BleTransport.enableStateRestoration();
  final notifications = LocalMessageNotifications();
  final controller = MeshController(
    store: MeshStore(preferences),
    transport: BleTransport(),
    lanTransport: LanTransport(),
    adapters: const [MeshCoreAdapter(), MeshtasticAdapter()],
    preview: const bool.fromEnvironment('MESHGRAME_PREVIEW'),
    onIncomingMessage: notifications.received,
    onIncomingReaction: notifications.receivedReaction,
    isChatForeground: () => notifications.isForeground,
  );
  await notifications.start(controller);
  runApp(
    MeshGrame(
      controller: controller,
      notifications: LocalMessageNotifications.supported && !controller.preview
          ? notifications
          : null,
    ),
  );
  unawaited(
    controller.restoreConnection(
      eligible:
          notifications.isForeground ||
              defaultTargetPlatform != TargetPlatform.iOS
          ? null
          : notifications.supportsRadio,
    ),
  );
}

class MeshGrame extends StatelessWidget {
  const MeshGrame({
    super.key,
    required this.controller,
    this.locale,
    this.notifications,
  });
  final MeshController controller;
  final Locale? locale;
  final LocalMessageNotifications? notifications;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('ru'), Locale('en')],
      theme: const MeshStyle(false).theme(),
      darkTheme: const MeshStyle(true).theme(),
      themeMode: switch (controller.appearance) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      builder: (context, child) {
        if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
          return child!;
        }
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemStatusBarContrastEnforced: false,
            statusBarIconBrightness:
                Theme.of(context).brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: child!,
        );
      },
      home: MeshHome(controller: controller, notifications: notifications),
    ),
  );
}
