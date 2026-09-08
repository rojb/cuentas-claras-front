import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../models/group_event.dart';

/// The browser stream: `EventSource`, which the page already has.
///
/// It parses the wire format and reconnects on its own, honouring the
/// `retry:` the server sends. That is most of what the native side had to
/// write by hand, and it is the reason this file is six lines of real work.
///
/// Errors are not forwarded to the listener. An EventSource error is almost
/// always "the connection dropped, I am about to try again", and turning
/// every one of those into an error on the stream would tear down a
/// subscription that was about to recover by itself. The screen keeps
/// working the way it did before any of this existed: pull to refresh.
Stream<GroupEvent> openGroupEvents(Uri url) {
  web.EventSource? source;
  late final StreamController<GroupEvent> controller;

  controller = StreamController<GroupEvent>(
    onListen: () {
      source = web.EventSource(url.toString())
        ..onmessage = ((web.MessageEvent message) {
          final data = message.data;
          if (!data.isA<JSString>()) return;

          final event = GroupEvent.tryParse(
            jsonDecode((data as JSString).toDart) as Object?,
          );
          if (event != null && !controller.isClosed) controller.add(event);
        }).toJS;
    },
    onCancel: () {
      source?.close();
      source = null;
    },
  );

  return controller.stream;
}
