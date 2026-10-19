# picomemo does the OMEMO cryptography

**Decision.** The cryptographic half of OMEMO, X3DH, the double ratchet and the
protobuf encoding, comes from picomemo, fetched and built by
`Dependencies/picomemo/fetch-picomemo.sh` and pinned by commit. Device lists,
bundles, stanzas and trust are Adium's own work. The crypto backend is OpenSSL
rather than picomemo's bundled HACL*, because this application ships an OpenSSL 3
already for Telegram.

**Why, and the correction that makes this page worth reading.** The comment in
the fetch script says picomemo was chosen over the better known libraries because
it is ISC licensed while the alternatives are GPLv3 or AGPL, and those "would
have taken the GPL v2 option away from the finished application".

That reason does not hold, and it did not hold when it was written. The GPLv2
option for the finished application was already gone: five shipped plug-ins are
GPL-3.0 and OpenSSL has been Apache 2.0 since 3.0. Nobody noticed until the
licences of the whole bundle were measured on 13 October 2026.

The choice is still right, for a smaller and more honest reason: ISC is simply
less restrictive than GPLv3 or AGPL, it keeps the option open for anybody
downstream who wants it, and picomemo does one thing rather than bringing a
framework. But the argument that it preserved something for *this* application
was wrong, and the comment in the script still says so.

**What it costs.** picomemo links OpenSSL, which means `AdiumLibpurple` pulls 25
undefined EVP symbols and the bundle carries `libcrypto.3.dylib` whether or not
Telegram is in it. Switching picomemo to its bundled HACL* backend would remove
that one dependency, but not the Apache licence from the bundle, because Telegram
needs OpenSSL regardless.

**Verified** 19 October 2026: the comment quoted above is still in
`fetch-picomemo.sh` lines 5 to 7, and `collect-licenses.sh` counts five GPL-3.0
plug-ins.
