import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/group_event.dart';

/// The native stream: one long-lived HTTP response, read as it arrives.
///
/// Reconnection is written out here because nothing on this platform does it
/// for us. The loop is deliberately dumb — wait three seconds, try again,
/// forever — and that is enough: the stream carries no history, so a
/// reconnect is not a resync, it is just a new connection. Whoever is
/// listening reloads once and is up to date.
///
/// WHY THIS IS A StreamController AND NOT AN `async*` GENERATOR, which is
/// what it was first and what it obviously wants to be:
///
/// An `async*` that sits in `await for` over the response is suspended inside
/// the socket read whenever the group is quiet — which is almost always. Ask
/// it to stop and you deadlock: cancelling waits for the generator to finish,
/// the generator cannot move until the inner stream is cancelled, and the
/// inner stream will not budge until the socket produces something it never
/// will. Measured before this rewrite, `cancel()` had not returned after five
/// seconds; the screen calls it on every dispose.
///
/// Written this way, cancelling kills the socket FIRST and lets everything
/// else unwind behind it.
Stream<GroupEvent> openGroupEvents(Uri url) {
  final client = HttpClient();
  StreamSubscription<String>? lines;
  var closed = false;
  late final StreamController<GroupEvent> controller;

  Future<void> readOnce() async {
    final request = await client.getUrl(url);
    request.headers.set('accept', 'text/event-stream');
    request.headers.set('cache-control', 'no-cache');

    final response = await request.close();

    if (response.statusCode != 200) {
      // 401 or 404: the token expired, or we are not in this group any more.
      // Still worth retrying on a schedule — a new sign-in fixes the first —
      // but there is nothing to read right now.
      await response.drain<void>();
      return;
    }

    // Completed when the connection ends, however it ends. Awaiting this is
    // what keeps the loop from opening a second connection over the first.
    final ended = Completer<void>();
    void finish() {
      if (!ended.isCompleted) ended.complete();
    }

    lines = response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        // Comments (': ping') and the retry hint are the server keeping the
        // connection alive. Only data lines carry an event.
        if (!line.startsWith('data: ')) return;

        try {
          final event = GroupEvent.tryParse(
            jsonDecode(line.substring(6)) as Object?,
          );
          if (event != null && !controller.isClosed) controller.add(event);
        } on FormatException {
          // A half-written line on a dropped connection. The next one is
          // fine, and this one was never money.
        }
      },
      onDone: finish,
      onError: (Object _) => finish(),
      cancelOnError: true,
    );

    await ended.future;
  }

  Future<void> keepReading() async {
    while (!closed) {
      try {
        await readOnce();
      } on Object {
        // A dropped connection is the normal way this ends. Falling through
        // to the delay and trying again is the whole recovery story.
      }

      if (closed) return;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  controller = StreamController<GroupEvent>(
    onListen: () {
      unawaited(keepReading());
    },
    onCancel: () {
      closed = true;

      // ORDER MATTERS. Destroying the socket is what makes the line
      // subscription finish; cancelling that first would be waiting on a
      // read that is never going to complete.
      client.close(force: true);
      unawaited(lines?.cancel());
    },
  );

  return controller.stream;
}
