#!/bin/zsh
# Run the peer tool inside its own virtualenv, creating it on first use.
#
#   ./run.sh echo                     answer everything sent to peer@localhost
#   ./run.sh send "Text" [--to JID]   send one message as peer@localhost
#   ./run.sh second-device            sit on the adium account as a second device
#   ./run.sh selftest                 automated feature checks against the server
#   ./run.sh muc-reactions            group-chat reaction checks (XEP-0444/0359)

set -e
cd "$(dirname "$0")"

if [ ! -d .venv ]; then
	python3 -m venv .venv
	./.venv/bin/pip -q install -r requirements.txt
fi

case "$1" in
	selftest)      shift; exec ./.venv/bin/python selftest.py "$@" ;;
	muc-reactions) shift; exec ./.venv/bin/python muc_reactions.py "$@" ;;
	*)             exec ./.venv/bin/python peer.py "$@" ;;
esac
