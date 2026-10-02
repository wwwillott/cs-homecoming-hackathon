import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/graph/graph_options.dart';
import 'package:orbit/graph/graph_view.dart';
import 'package:orbit/models/contact.dart';
import 'package:orbit/models/network_tree.dart';
import 'package:orbit/models/user_mode.dart';
import 'package:orbit/services/assistant_service.dart';
import 'package:orbit/services/recap_service.dart';
import 'package:orbit/state/app_state.dart';
import 'package:orbit/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppState _testApp() {
  SharedPreferences.setMockInitialValues({});
  return AppState(
    recapService: MockRecapService(),
    assistant: MockAssistantService(
      contacts: () => const [],
      mode: () => UserMode.seeker,
      userName: () => 'Will',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('askTreeIds includes primary and attached trees in shared mode', () {
    final app = _testApp();
    app.attachSharedTreeForTest(
      tree: const NetworkTree(
        id: 'attached-1',
        label: "Maya's network",
        isPrimary: false,
        isReadOnly: true,
      ),
      contacts: [
        Contact(id: 'p1', name: 'Priya'),
      ],
    );

    expect(app.isSharedMode, isTrue);
    expect(app.attachedContacts, hasLength(1));
    expect(app.askTreeIds(), containsAll(['primary', 'attached-1']));

    app.leaveSharedMode();
    expect(app.isSharedMode, isFalse);
    expect(app.attachedContacts, isEmpty);
    expect(app.askTreeIds(), equals(['primary']));
  });

  testWidgets('shared mode renders two graph clouds with distinct anchors', (tester) async {
    final app = _testApp();
    app.attachSharedTreeForTest(
      tree: const NetworkTree(
        id: 'attached-1',
        label: "Maya's network",
        isPrimary: false,
        isReadOnly: true,
      ),
      contacts: [
        Contact(id: 'maya-contact', name: 'Leo Chen', company: 'Robotics Lab', readOnly: true),
      ],
    );
    // Seed the primary cloud.
    app.loadDemoData();

    await tester.pumpWidget(
      AppScope(
        state: app,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Column(
              children: [
                if (app.isSharedMode)
                  Text('Shared with ${app.activeSharedTree!.shortLabel}'),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: GraphView(
                          contacts: app.contacts,
                          colorBy: ColorBy.strength,
                          sizeBy: SizeBy.strength,
                          showPeerLinks: true,
                          focusId: null,
                          onFocusChanged: (_) {},
                          anchorLabel: 'You',
                        ),
                      ),
                      Expanded(
                        child: GraphView(
                          contacts: app.attachedContacts,
                          colorBy: ColorBy.strength,
                          sizeBy: SizeBy.strength,
                          showPeerLinks: true,
                          focusId: null,
                          onFocusChanged: (_) {},
                          anchorLabel: app.activeSharedTree?.shortLabel ?? 'Them',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Shared with Maya'), findsOneWidget);
    expect(find.byType(GraphView), findsNWidgets(2));
    final views = tester.widgetList<GraphView>(find.byType(GraphView)).toList();
    expect(views.map((view) => view.anchorLabel), containsAll(['You', 'Maya']));
    expect(views.last.contacts.any((c) => c.readOnly), isTrue);
  });
}
