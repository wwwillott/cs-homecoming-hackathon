import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Ask for the mic immediately via `getUserMedia`.
///
/// Must run as the first await after a tap. Chrome only shows the permission
/// prompt while the click's transient user activation is still valid — any
/// earlier `await` (permissions.query, cancel, networking) silently denies.
Future<bool> ensureMicrophonePermission() async {
  try {
    final stream = await web.window.navigator.mediaDevices
        .getUserMedia(web.MediaStreamConstraints(audio: true.toJS))
        .toDart;
    for (final track in stream.getAudioTracks().toDart) {
      track.stop();
    }
    return true;
  } catch (_) {
    return false;
  }
}
