#!/bin/sh
# Generate a self-signed certificate for localhost on first start, then run
# Prosody in the foreground. The certificate lives in the data volume, so it
# survives container rebuilds and Adium only has to trust it once.
set -e

CERT_DIR=/etc/prosody/certs

if [ ! -f "$CERT_DIR/localhost.crt" ]; then
	openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
		-keyout "$CERT_DIR/localhost.key" \
		-out "$CERT_DIR/localhost.crt" \
		-subj "/CN=localhost" \
		-addext "subjectAltName=DNS:localhost,IP:127.0.0.1"
	chmod 600 "$CERT_DIR/localhost.key"
fi

exec prosody -F
