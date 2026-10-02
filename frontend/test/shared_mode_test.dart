import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orbit/graph/graph_options.dart';
import 'package:orbit/graph/graph_view.dart';
import 'package:orbit/models/contact.dart';
import 'package:orbit/models/network_tree.dart';
import 'package:orbit/models/user_mode.dart';
import 'package:orbit/services/assistant_service.dart';
import 'package:orbit/services/network_tree_service.dart';
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

  test('contactFromPerson accepts decimal alpha_score strings', () {
    final contact = NetworkTreeService.contactFromPerson(
      {
        'id': 'p1',
        'name': 'Maya',
        'alpha_score': '9.00',
        'organizations': const [],
        'contact_methods': const [],
        'notes': const [],
        'interests': const ['Robotics'],
      },
      const [],
      readOnly: true,
    );
    expect(contact.strength, 9);
    expect(contact.readOnly, isTrue);
  });

  test('askTreeIds includes primary and attached trees in shared mode', () {
    final app = _testApp();
    app.attachSharedTreeForTest(
      tree: const NetworkTree(
        id: 'attached-1',
        label: "Maya's network",
        isPrimary: false,
        isReadOnly: true,
        attributedUsername: 'maya',
      ),
      contacts: [
        Contact(id: 'p1', name: 'Priya'),
      ],
    );

    expect(app.isSharedMode, isTrue);
    expect(app.attachedContacts, hasLength(1));
    expect(app.activeSharedTree!.shortLabel, 'maya');
    expect(app.askTreeIds(), containsAll(['primary', 'attached-1']));

    app.leaveSharedMode();
    expect(app.isSharedMode, isFalse);
    expect(app.attachedContacts, isEmpty);
    expect(app.askTreeIds(), equals(['primary']));
  });

  testWidgets('shared mode uses one stage with two username anchors', (tester) async {
    final app = _testApp();
    app.username = 'will';
    app.attachSharedTreeForTest(
      tree: const NetworkTree(
        id: 'attached-1',
        label: "Maya's network",
        isPrimary: false,
        isReadOnly: true,
        attributedUsername: 'maya',
      ),
      contacts: [
        Contact(id: 'maya-contact', name: 'Leo Chen', company: 'Robotics Lab', readOnly: true),
      ],
    );
    app.loadDemoData();

    await tester.pumpWidget(
      AppScope(
        state: app,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: GraphView(
              contacts: app.contacts,
              attachedContacts: app.attachedContacts,
              colorBy: ColorBy.strength,
              sizeBy: SizeBy.strength,
              showPeerLinks: true,
              focusId: null,
              onFocusChanged: (_) {},
              anchorLabel: app.username ?? 'You',
              attachedAnchorLabel: app.activeSharedTree!.shortLabel,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(GraphView), findsOneWidget);
    final view = tester.widget<GraphView>(find.byType(GraphView));
    expect(view.anchorLabel, 'will');
    expect(view.attachedAnchorLabel, 'maya');
    expect(view.attachedContacts, isNotEmpty);
  });
}
