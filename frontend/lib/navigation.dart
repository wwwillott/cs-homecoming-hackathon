import 'package:flutter/material.dart';

import 'models/contact.dart';
import 'screens/capture_screen.dart';
import 'screens/contact_detail_screen.dart';
import 'screens/contact_editor_screen.dart';
import 'services/recap_service.dart';
import 'state/app_state.dart';

class Breakpoints {
  static const rail = 720.0;
  static const split = 1000.0;
  static const extendedRail = 1280.0;
}

bool isSplitLayout(BuildContext context) => MediaQuery.sizeOf(context).width >= Breakpoints.split;

Route<T> _fadeRoute<T>(Widget page, {String? name, bool fullscreen = false}) {
  return PageRouteBuilder<T>(
    settings: RouteSettings(name: name),
    fullscreenDialog: fullscreen,
    transitionDuration: const Duration(milliseconds: 340),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(
            begin: fullscreen ? const Offset(0, 0.06) : const Offset(0.05, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

String contactRouteName(String id) => 'contact/$id';

/// Opens a contact: inline on wide layouts, as a pushed page on phones.
void openContact(BuildContext context, String id) {
  final app = AppScope.read(context);
  if (isSplitLayout(context)) {
    app.selectContact(id);
    app.setTab(AppTab.people);
  } else {
    app.navigatorKey.currentState!.push(
      _fadeRoute(ContactDetailScreen(contactId: id), name: contactRouteName(id)),
    );
  }
}

Future<void> pushContactPage(NavigatorState nav, String id) =>
    nav.push(_fadeRoute(ContactDetailScreen(contactId: id), name: contactRouteName(id)));

Future<Contact?> openEditor(
  BuildContext context, {
  Contact? initial,
  RecapDraft? draft,
}) {
  return AppScope.read(context).navigatorKey.currentState!.push<Contact>(
        _fadeRoute(
          ContactEditorScreen(initial: initial, draft: draft),
          name: draft != null ? 'draft' : 'editor',
          fullscreen: true,
        ),
      );
}

Route<void> captureRoute() => _fadeRoute(const CaptureScreen(), name: 'capture', fullscreen: true);

Future<void> openCapture(BuildContext context) =>
    AppScope.read(context).navigatorKey.currentState!.push(captureRoute());

Route<Contact> draftRoute(RecapDraft draft) => _fadeRoute(
      ContactEditorScreen(draft: draft),
      name: 'draft',
      fullscreen: true,
    );
