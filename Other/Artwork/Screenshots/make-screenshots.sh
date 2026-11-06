#!/bin/bash
# Takes the README's two pictures, conversation.png and preferences.png, from a demo copy of
# the built application that runs beside the real Adium without ever seeing its data: the copy
# gets a home of its own through CFFIXED_USER_HOME, an invented account on the local Prosody
# test server, four invented contacts with duck avatars, and a scripted conversation. The
# pictures are then taken while each window is in front, which brings the demo onto the
# screen for about half a minute.
#
# Needs: build/Release/Adium.app (./install.sh --build-only), the test server running
# (Testing/xmpp/server.sh start, after colima start), the peer tool's virtualenv
# (any Testing/xmpp/peer/run.sh command creates it), Docker on PATH, Xcode's clang, and the
# Accessibility permission for the terminal this runs from, which the clicks need.
#
#   Other/Artwork/Screenshots/make-screenshots.sh          take both pictures, then clean up
#   Other/Artwork/Screenshots/make-screenshots.sh --keep   leave the demo running afterwards
#
# The pictures of 6 November 2026 were taken with these steps run one by one; this file is
# their sequence. Everything it makes lands in build/screenshots.
set -e
REPO=$(cd "$(dirname "$0")/../../.." && pwd)
HERE=$REPO/Other/Artwork/Screenshots
WORK=$REPO/build/screenshots
PY=$REPO/Testing/xmpp/peer/.venv/bin/python
APP=$WORK/Adium.app
HOME_DIR=$WORK/home
USERDIR="$HOME_DIR/Library/Application Support/Adium 2.0/Users/Default"
KEEP=${1:-}
nap() { python3 -c "import time; time.sleep($1)"; }
say() { printf '\033[1m== %s\033[0m\n' "$*"; }

say "Preflight"
[ -d "$REPO/build/Release/Adium.app" ] || { echo "no build/Release/Adium.app; run ./install.sh --build-only first"; exit 1; }
[ -x "$PY" ] || { echo "no peer virtualenv; run Testing/xmpp/peer/run.sh selftest once"; exit 1; }
docker exec adium-xmpp prosodyctl status >/dev/null 2>&1 || { echo "the test server is not running; Testing/xmpp/server.sh start"; exit 1; }
osascript -e 'tell application "System Events" to count processes' >/dev/null 2>&1 || { echo "System Events refuses; grant the terminal Accessibility"; exit 1; }
FRONT=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true')

say "A demo copy with a home of its own"
rm -rf "$WORK"; mkdir -p "$WORK/avatars" "$USERDIR"
cp -R "$REPO/build/Release/Adium.app" "$APP"
clang -framework Cocoa -o "$WORK/winlist" "$HERE/winlist.m"
clang -framework Cocoa -framework ApplicationServices -o "$WORK/click" "$HERE/click.m"
for c in Blue Green Purple Red Yellow; do
	sips -s format png -Z 128 "$REPO/Resources/Dock Icons/Adiumy $c.AdiumIcon/ApplicationIcon.png" --out "$WORK/avatars/$c.png" >/dev/null
done
sips -s format tiff "$WORK/avatars/Red.png" --out "$WORK/avatars/Red.tiff" >/dev/null
sips -s format png -Z 160 "$REPO/Resources/AdiumyButler.png" --out "$WORK/butler-160.png" >/dev/null   # the best dressed duck, 160 points tall in the conversation
read -r _ _ SCREEN_W SCREEN_H <<< "$(osascript -e 'tell application "Finder" to get bounds of window of desktop' | tr -d ',')"

say "The accounts on the test server"
for u in ada tobias mira lars noor; do
	docker exec adium-xmpp prosodyctl deluser "$u@localhost" >/dev/null 2>&1 || true   # also drops the message archive
	docker exec adium-xmpp prosodyctl register "$u" localhost "$u-pw" >/dev/null 2>&1
done
SCREENSHOT_AVATARS=$WORK/avatars "$PY" -I -W ignore::DeprecationWarning "$HERE/stage.py" prepare

say "The demo's preferences"
plist() { printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n<dict>\n%s</dict>\n</plist>\n' "$2" > "$USERDIR/$1.plist"; }
plist Accounts "	<key>Accounts</key>
	<array>
		<dict>
			<key>ObjectID</key><string>1</string>
			<key>Service</key><string>Jabber</string>
			<key>Type</key><string>libpurple-Jabber</string>
			<key>UID</key><string>ada@localhost</string>
		</dict>
	</array>
	<key>TopAccountID</key><integer>2</integer>
"
plist Appearance "	<key>Appearance Style</key><integer>2</integer>
"
plist "Message Entry" "	<key>Voice Note Button</key><true/>
	<key>Formula Editor Button</key><true/>
"
plist FileTransfer "	<key>FT AutoAccept</key><integer>2</integer>
"
plist "WebKit Message Display" "	<key>Message Style</key><string>im.adium.Smooth Operator.style</string>
	<key>im.adium.Smooth Operator.style:Variant</key><string>Dark</string>
"
plist "Window Positions" "	<key>Message Window-{{0, 0}, {$SCREEN_W, $SCREEN_H}}</key><string>300 $((SCREEN_H - 100 - 500)) 560 448 0 0 $SCREEN_W $SCREEN_H</string>
"
security add-internet-password -U -s "Jabber.ada@localhost" -a "ada@localhost" -w "ada-pw" -T "$APP" -j "Adium README screenshot demo"

say "Launching the demo"
(cd "$WORK" && CFFIXED_USER_HOME="$HOME_DIR" nohup "$APP/Contents/MacOS/Adium" -AppleLanguages '(en-US)' -AppleLocale en_US > "$WORK/adium.log" 2>&1 & echo $! > "$WORK/pid")
PID=$(cat "$WORK/pid"); nap 12
osascript - "$APP" "$WORK/avatars/Red.tiff" <<'AS'
on run argv
	using terms from application "Adium"
		tell application (item 1 of argv)
			set enabled of account 1 to true
			set display name of account 1 to "Ada"
			set image of account 1 to (read (POSIX file (item 2 of argv)) as TIFF picture)
			go online account 1
			delay 5
			repeat with u in {"tobias@localhost", "mira@localhost", "lars@localhost", "noor@localhost"}
				GetURL ("xmpp:" & u & "?message")
				delay 0.6
			end repeat
			delay 1
			repeat with c in chats
				if name of c is "tobias@localhost" then become active c
			end repeat
		end tell
	end using terms from
end run
AS

say "The conversation"
PICTURE=$("$PY" -I -W ignore::DeprecationWarning "$HERE/upload.py" "$WORK/butler-160.png" image/png | awk '/^PUT 201/{print $3}')
[ -n "$PICTURE" ] || { echo "the picture did not reach the server"; exit 1; }
: > "$WORK/commands.txt"
SCREENSHOT_AVATARS=$WORK/avatars "$PY" -I -u -W ignore::DeprecationWarning "$HERE/stage.py" online "$WORK/commands.txt" > "$WORK/peers.log" 2>&1 &
PEERS=$!; nap 5
"$HERE/conversation.sh" "$APP" "$WORK/commands.txt" "$PICTURE"

say "In front of the screen"
open "$APP"; nap 2
osascript - "$PID" <<'AS'
on run argv
	tell application "System Events"
		set p to first process whose unix id is (item 1 of argv as integer)
		set w to window "Tobias Rehn" of p
		set position of w to {300, 100}
		set size of w to {560, 500}
	end tell
end run
AS
nap 2
"$WORK/click" click 829 556 >/dev/null; nap 3       # the microphone beside the message field: the shelf opens and records
"$WORK/click" click 813 543 >/dev/null; nap 1       # pause
osascript - "$PID" <<'AS'
on run argv
	tell application "System Events"
		set p to first process whose unix id is (item 1 of argv as integer)
		repeat with mi in menu items of menu 1 of menu bar item 2 of menu bar 1 of p
			set n to name of mi
			if n is not missing value then
				if n starts with "Xtras" then click mi
			end if
		end repeat
		delay 2
		repeat with w in windows of p
			if (name of w) starts with "Xtras" then
				set position of w to {340, 140}
				set size of w to {878, 560}
				perform action "AXRaise" of w
			end if
		end repeat
	end tell
end run
AS
nap 1
"$WORK/click" scroll 440 500 -40 >/dev/null; nap 3  # the sidebar down to its last row, Xtras Manager, which the menu selected
PW=$("$WORK/winlist" "$PID" | awk -F'\t' '$3 ~ /^878x560/ {print $1; exit}')
screencapture -x -l "$PW" "$HERE/preferences.png"
osascript - "$PID" <<'AS'
on run argv
	tell application "System Events"
		set p to first process whose unix id is (item 1 of argv as integer)
		perform action "AXRaise" of window "Tobias Rehn" of p
	end tell
end run
AS
nap 3
CW=$("$WORK/winlist" "$PID" | awk -F'\t' '$5=="Tobias Rehn" {print $1; exit}')
screencapture -x -l "$CW" "$HERE/conversation.png"
open -a "$FRONT" 2>/dev/null || true
echo "wrote $HERE/preferences.png and $HERE/conversation.png"

if [ "$KEEP" != "--keep" ]; then
	say "Cleaning up"
	osascript -l JavaScript -e "Application($PID).quit()" >/dev/null 2>&1 || true
	kill "$PEERS" 2>/dev/null || true
	security delete-internet-password -s "Jabber.ada@localhost" -a "ada@localhost" >/dev/null 2>&1 || true
fi
