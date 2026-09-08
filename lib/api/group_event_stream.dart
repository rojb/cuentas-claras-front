/// Opens the server-sent event stream for one group.
///
/// TWO IMPLEMENTATIONS, because the two platforms disagree about what an SSE
/// client is. A browser has `EventSource` built in — it parses the wire
/// format and reconnects on its own, and reimplementing that on top of fetch
/// would be writing a worse copy of something already in the page. Native
/// has no such thing, so there it is a long-lived HTTP response read line by
/// line, with the reconnection loop written out by hand.
///
/// The conditional export is what keeps that out of the rest of the app: the
/// controller asks for a Stream and never learns which one it got.
library;

export 'group_event_stream_io.dart'
    if (dart.library.js_interop) 'group_event_stream_web.dart';
