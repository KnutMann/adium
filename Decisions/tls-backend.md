# Secure Transport is the only TLS backend, and that was chosen

**Decision.** TLS for every libpurple connection goes through
`Plugins/Purple Service/libpurple_extensions/ssl-cdsa.c`, on Apple's Secure
Transport, compiled into AdiumLibpurple with `HAVE_CDSA` defined in
`AdiumLibpurple.xcconfig`. Nothing else is compiled. libpurple is configured with
`--enable-gnutls=no --enable-nss=no`, so its own two SSL plug-ins are not built
and the bundle ships none. Secure Transport is deprecated and this is deliberate.

**Why not Network.framework.** It was examined on 19 August 2026 and does not
fit, for a reason that has nothing to do with TLS. This code does not open
connections. It wraps a socket libpurple hands it, which has already been
tunnelled through the user's per-account proxy: `SSLSetConnection(ctx, gsc->fd)`
on a descriptor `purple_proxy` produced, HTTP, SOCKS4 or SOCKS5, configured in
Adium's own proxy pane. `NWConnection` cannot adopt an existing descriptor. It
would establish the connection itself, silently bypassing every per-account
proxy, and it speaks no SOCKS4 at all, which Adium's interface offers. For
somebody routing an account through Tor that is not a nuance, it is the feature.

**Why not GnuTLS or NSS**, which libpurple does ship: both are another library to
build, bundle, pin and keep patched, for something the operating system already
does, and neither has the certificate trust panel this application shows. They
were turned off in the build rather than left as a fallback, which is the honest
position: an uncompiled fallback is not a fallback.

**What it costs** 31 deprecation warnings in that one file are the small part.
The real cost is that there is exactly one TLS implementation and no second path
compiled, so when Secure Transport stops working rather than merely warning,
every account stops at once and the fix is new code rather than a build flag.

**The way off it**, when it is needed, keeps the proxy behaviour byte-identical:
a backend that wraps the same descriptor the same way, over OpenSSL, which this
bundle already ships for Telegram and OMEMO. What it has to bring with it is the
trust-decision hook, `register_certificate_ui_cb`, which is cdsa-specific today,
handing the chain over as `SecCertificateRef` so the certificate panel and the
per-account policy keep working unchanged. That is a piece of work with live
testing per protocol, not a swap.

**Reconsider when** Secure Transport stops working, or sooner: having no second
backend is a risk somebody may want to buy down before it is urgent.

**Verified** 19 October 2026: `HAVE_CDSA` in `AdiumLibpurple.xcconfig` line 42,
`ssl-cdsa.c` referenced four times in the project file, `build_purple.sh` lines
168 and 169 disabling GnuTLS and NSS, no SSL plug-in in `Dependencies/build/lib/purple-2/`,
and zero GnuTLS or NSS symbols in the shipped libpurple.
