-- Prosody configuration for the Adium XMPP test server.
--
-- One virtual host, "localhost", reachable only from this machine. Encryption
-- is offered (self-signed certificate, generated on first start) but not
-- required, so both TLS and plaintext paths can be exercised from Adium.

admins = { "admin@localhost" }

data_path = "/var/lib/prosody"
pidfile = "/var/run/prosody/prosody.pid"

modules_enabled = {
	-- Required for a functioning server
	"roster";
	"saslauth";
	"tls";
	"disco";
	"presence";
	"message";
	"iq";

	-- Discovery and keepalive
	"version";
	"uptime";
	"time";
	"ping";

	-- Storage-backed basics
	"private";
	"vcard4";
	"vcard_legacy";
	"blocklist";
	"pep";

	-- The features the Adium XMPP roadmap develops against
	"carbons";     -- XEP-0280 Message Carbons
	"mam";         -- XEP-0313 Message Archive Management
	"csi_simple";  -- XEP-0352 Client State Indication
	"bookmarks";   -- XEP-0402 PEP Native Bookmarks (with legacy conversion)
	"http_file_share"; -- XEP-0363 HTTP upload, for pictures sent as their address
}

-- The upload slots must name https addresses: Adium refuses plain http ones.
-- The certificate is the same self-signed one the XMPP port offers.
https_ports = { 5281 }
https_certificate = "certs/localhost.crt"
http_external_url = "https://localhost:5281/"

-- Accounts are created with prosodyctl (see server.sh), not in-band
allow_registration = false

authentication = "internal_hashed"

-- Offer TLS, require nothing: the rig must serve both test paths
c2s_require_encryption = false
allow_unencrypted_plain_auth = true

-- Keep the archive small; this server holds test chatter, not history
archive_expires_after = "1w"

log = {
	info = "*console";
}

certificates = "certs"

VirtualHost "localhost"

Component "conference.localhost" "muc"
	modules_enabled = { "muc_mam" }
