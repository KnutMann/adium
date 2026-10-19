# The conversation is rendered by WKWebView

**Decision.** The message view is a `WKWebView`, driven by
`AIWebKitMessageViewWKController` in Plugins/WebKit Message View. WebKit 1,
that is `WebView`, `WebFrame` and `windowScriptObject`, is used nowhere in the
application. Message styles are what they always were: HTML, CSS and JavaScript
in an `.AdiumMessageStyle` bundle.

**Why.** It came out of the deprecation hunt. WebKit 1 has been deprecated since
macOS 10.14 and the message view was the largest single source of warnings in
the tree. Past the count, WebKit 1 renders inside the application's process and
WebKit 2 does not, so a message style that misbehaves costs a content process
and not the conversation window. And it is the API Apple will stop shipping one
day. The message view is the one component the application cannot live
without, which is why it is the one that could not stay on it.

**What it costs.** Everything WKWebView does, it does asynchronously and in
another process, and the controller is shaped by that:

* Content is queued until the page says it is ready; nothing is injected into a
  page that has not loaded.
* JavaScript talks back through a script message handler, not through
  `windowScriptObject`; the context menu is built on the JavaScript side and
  answered through that bridge.
* The page is loaded as a file with read access to the whole volume, which is
  the only sanctioned way it may embed the style's resources, avatars and
  received images.
* The style's default font is applied after load, because WKWebView has no
  font preferences.
* A file dropped onto the view lands in WebKit's process, not in a drop target
  the old view forwarded to. The sample conversation in the settings lost that
  and nothing else.

One lesson from the removal: a subclass keeps its parent alive. The chat window
had run on WKWebView since 9 August, but the preview in the message settings
was a subclass of the old controller, and eighteen hundred lines stayed in the
build for a hundred and thirteen. Check what inherits from a class before
calling it dormant.

**Verified** 19 October 2026: `grep -rn '\bWebView\b\|WebFrame\b\|windowScriptObject'`
over Source, Plugins and Frameworks finds eight files, and every hit is a
comment or a `#pragma mark`.
