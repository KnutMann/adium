# Test harnesses

One directory per thing under test, each harness beside what it exercises.
Nothing here runs automatically: these are run by a person, usually against a
running service or a built application, and several need a server or a device.

The one-line summaries come from each script's own header, and are written
here by Utilities/script-index.py. A script listed without one has no header,
and that is the thing to fix rather than to describe here.

## bonjour

* `bonjour/bonjour-test.sh`  Two neighbours on one machine: one waits, one sends a greeting

## omemo

* `omemo/media-test.sh`  Build and run the check on encrypted file sharing (XEP-0454), against a published NIST vector
* `omemo/message-test.sh`  Build and run the check on the OMEMO wire form: one payload, one wrapped key per device, the
* `omemo/roundtrip-test.sh`  Build and run the picomemo round trip: does X3DH, the double ratchet and the payload
* `omemo/stanza-test.sh`  Build and run the check on the OMEMO stanza itself, against the real xmlnode from libpurple
* `omemo/store-test.sh`  Build and run the check on the durable half of OMEMO: identity, sessions, skipped keys and

## speech

* `speech/voice-test.sh`  Build and run the speech migration check: do the stored rate, pitch and voice identifier

## ui

* `ui/cellbased-tables.sh`  Every table still running on the cell based model, with what makes converting it hard
* `ui/contactlist/list-shots.sh`  Photographs Adium's contact list without starting Adium
* `ui/editor/editor-shots.sh`  Photographs the contact list appearance editor without running Adium
* `ui/entry/entry-shots.sh`  Photographs the message field with its accessory buttons, without running Adium
* `ui/formula/formula-shots.sh`  Photographs the formula editor without running Adium
* `ui/messagestyle/style-shots.sh`  Photographs a message style without running Adium: a short made-up conversation,
* `ui/nibs/nib-audit.sh`  Every nib a class names must be in the built application
* `ui/voice/voice-shots.sh`  Photographs the voice recorder's shelf without running Adium, and without a

## voice

* `voice/opus-test.sh`  Build and run the voice note encoder's checks: does the reader that decides say yes?

## webrtc

* `webrtc/callwindow-test.sh`  Build and run the call window's geometry check: the real window, once without a
* `webrtc/capture-call.sh`  Who says what during a call, read off the wire
* `webrtc/jingle-fullstack-test.sh`  Build and run the whole-stack call check: two controllers with real peer
* `webrtc/jingle-session-test.sh`  Build and run the two-machine conversation checks: a whole call talked
* `webrtc/jingle-test.sh`  Build and run the Jingle engine's round-trip checks. The engine is
* `webrtc/probe.sh`  Build and run the WebRTC loopback probe: two peer connections in one
* `webrtc/videoview-test.sh`  Build and run the video view's own checks: a frame in, a picture out

## xmpp

* `xmpp/entrypoint.sh`  Generate a self-signed certificate for localhost on first start, then run
* `xmpp/fallback-test.sh`  Build and run the XEP-0428 range check: does the marked stretch come out of the body,
* `xmpp/hostheader-test.sh`  Check that this platform still lets us choose the Host header ourselves
* `xmpp/mucselfping-test.sh`  Build and run the check that Adium reads a MUC self-ping answer (XEP-0410) and a MUC status
* `xmpp/mucselfping-wire.sh`  Build and run the check that a real MUC service answers a self-ping the way XEP-0410's table
* `xmpp/nickcolor-test.sh`  Build and run the XEP-0392 check: does our nickname colour land on the same hue angle
* `xmpp/peer/capscheck.py`  Checks a contact's call capabilities exactly the way Conversations does
* `xmpp/peer/fakepeer.py`  A stand-in for Conversations: speaks the call signalling, judges what Adium says
* `xmpp/peer/http_upload_probe.py`  Walks the exact road Adium's AMPurpleJabberHTTPFileUpload takes, without Adium
* `xmpp/peer/muc_reactions.py`  MUC reaction checks (XEP-0444 with XEP-0359) for the Adium test server
* `xmpp/peer/omemo_pep.py`  OMEMO announcement checks (XEP-0384) for the Adium test server
* `xmpp/peer/peer.py`  Counterpart tooling for the Adium XMPP test server
* `xmpp/peer/ringtest.py`  Rings the Adium under test with a real XEP-0353 propose and reports every
* `xmpp/peer/roster.py`  Make the test accounts contacts of each other
* `xmpp/peer/run.sh`  Run the peer tool inside its own virtualenv, creating it on first use
* `xmpp/peer/selftest.py`  Automated feature checks for the Adium XMPP test server
* `xmpp/peer/sendfile.py`  Offer Adium a file transfer (XEP-0096 SI over XEP-0047 IBB)
* `xmpp/regwire.sh`  Build and run the registration watcher: what libpurple reports, and in which order, while an
* `xmpp/sendpath-test.sh`  Build and run the check that a stanza survives being written out and read back, which is the
* `xmpp/server.sh`  Manage the Adium XMPP test server (Prosody in Docker)
* `xmpp/smsession-test.sh`  Build and run the check that the XEP-0198 queue belongs to an account rather than to its name
* `xmpp/smwire.sh`  Build and run the wire watcher: what goes out and what comes back while signing on
* `xmpp/styling-test.sh`  Build and run the XEP-0393 reader's checks: what is markup, and what is ordinary writing?
