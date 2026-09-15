#!/bin/zsh
# Manage the Adium XMPP test server (Prosody in Docker).
#
#   ./server.sh start      build the image if needed, start the server, create accounts
#   ./server.sh stop       stop and remove the container (data volume survives)
#   ./server.sh status     is it running, and which accounts exist
#   ./server.sh logs       follow the server log
#   ./server.sh reset      stop and DELETE the data volume (accounts, archive, certificate)
#   ./server.sh selftest   run the automated feature checks (see peer/selftest.py)
#   ./server.sh muc-reactions  group-chat reaction checks (see peer/muc_reactions.py)
#   ./server.sh omemo-pep      OMEMO announcement checks (see peer/omemo_pep.py)
#   ./server.sh trust      let this Mac accept the server's certificate, so that file
#                          uploads from Adium reach it instead of falling back
#   ./server.sh untrust    take that back
#
# Test accounts (password matches user name with "-pw" appended):
#   adium@localhost   the account to configure in Adium
#   peer@localhost    the counterpart the peer tool speaks as
#   admin@localhost   admin, rarely needed

set -e
cd "$(dirname "$0")"

CONTAINER=adium-xmpp
IMAGE=adium-xmpp
VOLUME=adium-xmpp-data
CERT_VOLUME=adium-xmpp-certs

ACCOUNTS=(adium peer admin)

start() {
	docker build -q -t "$IMAGE" . >/dev/null
	if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
		echo "$CONTAINER läuft bereits"
	else
		docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
		docker run -d --name "$CONTAINER" \
			-p 127.0.0.1:5222:5222 \
			-p 127.0.0.1:5281:5281 \
			-v "$VOLUME":/var/lib/prosody \
			-v "$CERT_VOLUME":/etc/prosody/certs \
			"$IMAGE" >/dev/null
		echo "$CONTAINER gestartet (localhost:5222, Upload auf 5281)"
	fi

	# Wait for the server to accept commands, then make sure the accounts exist.
	# prosodyctl exits 0 even for unknown commands, so the only reliable and
	# idempotent way is to register and let "already exists" fail quietly.
	for i in $(seq 1 20); do
		docker exec "$CONTAINER" prosodyctl status >/dev/null 2>&1 && break
		sleep 0.5
	done

	for user in "${ACCOUNTS[@]}"; do
		if docker exec "$CONTAINER" prosodyctl register "$user" localhost "$user-pw" >/dev/null 2>&1; then
			echo "Konto angelegt: $user@localhost (Passwort: $user-pw)"
		fi
	done
}

stop() {
	docker rm -f "$CONTAINER" >/dev/null 2>&1 && echo "$CONTAINER gestoppt" || echo "$CONTAINER lief nicht"
}

status() {
	if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
		docker ps --filter "name=$CONTAINER" --format 'läuft seit {{.RunningFor}} — Ports {{.Ports}}'
		for user in "${ACCOUNTS[@]}"; do
			if docker exec "$CONTAINER" test -e "/var/lib/prosody/localhost/accounts/$user.dat"; then
				echo "Konto: $user@localhost"
			fi
		done
	else
		echo "$CONTAINER läuft nicht"
	fi
}

logs() {
	docker logs -f "$CONTAINER"
}

reset() {
	stop
	docker volume rm "$VOLUME" "$CERT_VOLUME" >/dev/null 2>&1 || true
	echo "Datenvolumes gelöscht"
}

selftest() {
	start
	exec ./peer/run.sh selftest
}

# Where the certificate is put when it is taken out of the container
CERT_FILE="${TMPDIR:-/tmp}/adium-xmpp-localhost.crt"

fetch_certificate() {
	start
	docker exec "$CONTAINER" cat /etc/prosody/certs/localhost.crt > "$CERT_FILE"
	[ -s "$CERT_FILE" ] || { echo "Zertifikat nicht gefunden"; exit 1; }
}

# Uploads from Adium go over HTTPS, and a self-signed certificate is refused like any other
# unknown one: the upload fails and Adium falls back to the classic transfer, which looks like a
# bug in the upload code and is not. Trusting this one certificate, for this one name, makes the
# path testable. It lands in the login keychain, not the system one, so no administrator rights
# are involved and "untrust" undoes it completely.
trust() {
	fetch_certificate
	echo "Zertifikat: $CERT_FILE"
	security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$CERT_FILE"
	echo "localhost wird jetzt vertraut. Adium neu starten, damit es die Änderung sieht."
	echo "Rückgängig: ./server.sh untrust"
}

untrust() {
	fetch_certificate
	security remove-trusted-cert "$CERT_FILE" 2>/dev/null || true
	security delete-certificate -c localhost "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null || true
	echo "Vertrauen für localhost entfernt."
}

omemo_pep() {
	start
	exec ./peer/run.sh omemo-pep
}

muc_reactions() {
	start
	exec ./peer/run.sh muc-reactions
}

case "$1" in
	start)         start ;;
	stop)          stop ;;
	status)        status ;;
	logs)          logs ;;
	reset)         reset ;;
	selftest)      selftest ;;
	muc-reactions) muc_reactions ;;
	omemo-pep)     omemo_pep ;;
	trust)         trust ;;
	untrust)       untrust ;;
	*)             sed -n '2,20p' "$0"; exit 1 ;;
esac
