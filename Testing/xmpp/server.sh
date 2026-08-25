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
			-v "$VOLUME":/var/lib/prosody \
			-v "$CERT_VOLUME":/etc/prosody/certs \
			"$IMAGE" >/dev/null
		echo "$CONTAINER gestartet (localhost:5222)"
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
	*)             sed -n '2,17p' "$0"; exit 1 ;;
esac
