// Meshgram — Rusik636 — https://github.com/Rusik636/Meshgram
// AGPL-3.0-only with attribution under section 7(b); see NOTICE.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:meshgrame/ui/mesh_map.dart';
import 'package:meshgrame/ui/style.dart';

void main() {
  testWidgets('a node marker takes taps above the map attribution', (
    tester,
  ) async {
    final map = MapController();
    addTearDown(map.dispose);
    final credit = find.byType(MeshMapAttribution);
    await tester.pumpWidget(_map(map, const []));
    await tester.pumpAndSettle();
    final target = tester.getCenter(credit);
    final position = map.camera.screenOffsetToLatLng(target);
    var opened = false;
    await tester.pumpWidget(
      _map(map, [
        MeshMapPin.node(
          position: (
            latitude: position.latitude,
            longitude: position.longitude,
          ),
          id: 'edge',
          name: 'Edge relay',
          showLabel: false,
          onTap: () => opened = true,
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(MeshAvatar)).contains(target), isTrue);

    await tester.tapAt(target);
    expect(opened, isTrue);
  });

  testWidgets('a location preview passes taps and long presses through', (
    tester,
  ) async {
    const position = (latitude: 55.75, longitude: 49.14);
    var previewOpened = 0;
    var pinOpened = 0;
    var menuOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GestureDetector(
            onLongPress: () => menuOpened = true,
            child: MeshLocationPreview(
              position: position,
              loadTiles: false,
              onTap: () => previewOpened++,
              pin: MeshMapPin.node(
                position: position,
                id: 'relay',
                name: 'Relay',
                onTap: () => pinOpened++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final marker = tester.getCenter(find.byType(MeshAvatar));
    final credit = tester.getRect(find.byType(MeshMapAttribution));
    expect(credit.bottom, tester.getRect(find.byType(MeshMap)).bottom);

    await tester.tapAt(marker);
    await tester.pumpAndSettle();
    expect(previewOpened, 1);
    expect(pinOpened, 0);

    await tester.longPressAt(credit.center);
    await tester.pumpAndSettle();
    expect(menuOpened, isTrue);
    expect(previewOpened, 1);
  });

  testWidgets('closest bubbles merge at their midpoint and split on tap', (
    tester,
  ) async {
    final map = MapController();
    addTearDown(map.dispose);
    const first = (latitude: 0.0, longitude: 0.0);
    const second = (latitude: 0.0, longitude: .87890625);
    const third = (latitude: 0.0, longitude: 4.833984375);
    var opened = '';
    await tester.pumpWidget(
      _map(map, [
        const MeshMapPin.node(position: first, id: 'relay-a', name: 'Relay A'),
        const MeshMapPin.node(position: second, id: 'relay-b', name: 'Relay B'),
        MeshMapPin.node(
          position: third,
          id: 'relay-c',
          name: 'Relay C',
          onTap: () => opened = 'relay-c',
        ),
        const MeshMapPin(
          position: (latitude: -4, longitude: 2),
          label: 'Meeting point',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    final label = find.text('3');
    final target = map.camera.latLngToScreenOffset(
      LatLng(0, (first.longitude + second.longitude) / 4 + third.longitude / 2),
    );
    expect(tester.getCenter(label).dx, closeTo(target.dx, .1));
    expect(find.text('Meeting point'), findsOneWidget);
    expect(find.byIcon(Icons.place_rounded), findsOneWidget);

    await tester.tap(label);
    await tester.pumpAndSettle();
    expect(map.camera.zoom, greaterThan(4));
    expect(find.text('3'), findsNothing);
    expect(find.text('2'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is MeshAvatar && widget.name == 'Relay C',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Relay C'));
    expect(opened, 'relay-c');
  });

  testWidgets('coincident nodes open a picker with individual avatars', (
    tester,
  ) async {
    final map = MapController();
    addTearDown(map.dispose);
    const position = (latitude: 0.0, longitude: 0.0);
    var opened = '';
    await tester.pumpWidget(
      _map(map, [
        MeshMapPin.node(
          position: position,
          id: 'alpha',
          name: 'Repeater',
          onTap: () => opened = 'alpha',
        ),
        MeshMapPin.node(
          position: position,
          id: 'beta',
          name: 'Repeater',
          onTap: () => opened = 'beta',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(ListTile),
        matching: find.byType(MeshAvatar),
      ),
      findsNWidgets(2),
    );
    await tester.tap(find.text('beta'));
    await tester.pumpAndSettle();
    expect(opened, 'beta');
    expect(tester.takeException(), isNull);
  });

  testWidgets('groups nearby nodes across the antimeridian while panning', (
    tester,
  ) async {
    final map = MapController();
    addTearDown(map.dispose);
    await tester.pumpWidget(
      _map(map, const [
        MeshMapPin.node(
          position: (latitude: 0, longitude: 179.7),
          id: 'east',
          name: 'East node',
        ),
        MeshMapPin.node(
          position: (latitude: 0, longitude: -179.7),
          id: 'west',
          name: 'West node',
        ),
      ], longitude: 179.9),
    );
    await tester.pumpAndSettle();
    final group = find.text('2');
    final firstX = tester.getCenter(group).dx;
    expect(map.move(const LatLng(0, -179.9), 4), isTrue);
    await tester.pumpAndSettle();
    expect(group, findsOneWidget);
    expect(tester.getCenter(group).dx, closeTo(firstX, 5));
  });

  testWidgets('avatars and cluster counts retain their size at the map edge', (
    tester,
  ) async {
    final map = MapController();
    addTearDown(map.dispose);
    await tester.pumpWidget(
      _map(map, const [
        MeshMapPin.node(
          position: (latitude: 0, longitude: 0),
          id: 'alpha',
          name: 'Alpha',
        ),
        MeshMapPin.node(
          position: (latitude: 0, longitude: 0),
          id: 'beta',
          name: 'Beta',
        ),
        MeshMapPin.node(
          position: (latitude: 0, longitude: 10),
          id: 'solo',
          name: 'Solo',
        ),
      ]),
    );
    await tester.pumpAndSettle();
    final count = find.text('2');
    final avatar = find.byWidgetPredicate(
      (widget) => widget is MeshAvatar && widget.name == 'Solo',
    );
    final countWidth = tester.getRect(count).width;
    final avatarWidth = tester.getRect(avatar).width;

    expect(map.move(const LatLng(0, 34), 4), isTrue);
    await tester.pumpAndSettle();
    expect(tester.getCenter(count).dx, inExclusiveRange(0, 20));
    expect(tester.getRect(count).width, closeTo(countWidth, .01));

    expect(map.move(const LatLng(0, 44), 4), isTrue);
    await tester.pumpAndSettle();
    expect(tester.getCenter(avatar).dx, inExclusiveRange(0, 20));
    expect(tester.getRect(avatar).width, closeTo(avatarWidth, .01));
  });

  testWidgets(
    'merged bubbles mix both avatar colors into a vertical gradient',
    (tester) async {
      final map = MapController();
      addTearDown(map.dispose);
      const first = 'Alpha';
      const second = 'Beta';
      await tester.pumpWidget(
        _map(map, const [
          MeshMapPin.node(
            position: (latitude: 0, longitude: 0),
            id: 'alpha',
            name: first,
          ),
          MeshMapPin.node(
            position: (latitude: 0, longitude: 0),
            id: 'beta',
            name: second,
          ),
        ]),
      );
      await tester.pumpAndSettle();
      final fill = find.descendant(
        of: find.byKey(const ValueKey((false, 'alpha'))),
        matching: find.byType(DecoratedBox),
      );
      final decoration =
          tester.widget<DecoratedBox>(fill).decoration as BoxDecoration;
      final gradient = decoration.gradient! as LinearGradient;
      final (firstTop, firstBottom) = MeshAvatar.colorsFor(first);
      final (secondTop, secondBottom) = MeshAvatar.colorsFor(second);
      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
      expect(gradient.colors, [
        Color.lerp(firstTop, secondTop, .5),
        Color.lerp(firstBottom, secondBottom, .5),
      ]);
    },
  );

  testWidgets('merges and splits the silhouettes before revealing the faces', (
    tester,
  ) async {
    final map = MapController();
    addTearDown(map.dispose);
    const pins = [
      MeshMapPin.node(
        position: (latitude: 0, longitude: 0),
        id: 'west',
        name: 'West relay',
      ),
      MeshMapPin.node(
        position: (latitude: 0, longitude: 8),
        id: 'east',
        name: 'East relay',
      ),
    ];
    await tester.pumpWidget(_map(map, pins, longitude: 4));
    await tester.pumpAndSettle();

    final body = find.descendant(
      of: find.byKey(const ValueKey((true, 'west'))),
      matching: find.byType(AnimatedContainer),
    );
    final filters = find.byType(ImageFiltered);
    final name = find.text('West relay');
    expect(filters, findsNWidgets(2));
    expect(tester.getSize(body).width, 52);
    expect(name, findsOneWidget);

    expect(map.move(const LatLng(0, 4), 3), isTrue);
    await tester.pump();
    final before = tester.getCenter(body).dx;
    final count = find.text('2');
    final face = find.ancestor(of: count, matching: find.byType(Opacity)).first;
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.getCenter(body).dx, greaterThan(before));
    expect(tester.getSize(body).width, inExclusiveRange(52, 58.2));
    expect(tester.widget<Opacity>(face).opacity, 0);
    expect(find.descendant(of: filters, matching: count), findsNothing);
    expect(name, findsNothing);
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(face).opacity, 1);

    final mergedDiameter = tester.getSize(body).width;
    expect(map.move(const LatLng(0, 4), 4), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.getSize(body).width, inExclusiveRange(52, mergedDiameter));
    await tester.pumpAndSettle();
    expect(tester.getSize(body).width, 52);
    expect(count, findsNothing);
    expect(name, findsOneWidget);
  });
}

Widget _map(
  MapController controller,
  List<MeshMapPin> pins, {
  double longitude = 0,
}) => MaterialApp(
  theme: const MeshStyle(false).theme(),
  home: Scaffold(
    body: MeshMap(
      center: (latitude: 0, longitude: longitude),
      zoom: 4,
      controller: controller,
      loadTiles: false,
      pins: pins,
    ),
  ),
);
