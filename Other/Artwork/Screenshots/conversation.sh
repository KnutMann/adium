#!/bin/bash
# The conversation behind conversation.png. Tobias acts through the command file stage.py
# watches; Ada, the demo account, speaks through Adium's own scripting dictionary.
# Run by make-screenshots.sh: conversation.sh <demo Adium.app> <command file> <picture address>
APP=$1; CMD=$2; PICTURE=$3
tobias() { echo "$*" >> "$CMD"; }
pause() { python3 -c "import time; time.sleep($1)"; }
ada() { osascript - "$APP" "$*" <<'AS'
on run argv
	using terms from application "Adium"
		tell application (item 1 of argv)
			repeat with c in chats
				if name of c is "tobias@localhost" then send c message (item 2 of argv)
			end repeat
		end tell
	end using terms from
end run
AS
}
tobias typing;                                                        pause 2
tobias say Back from the ridge walk, legs are done;                   pause 3
ada "Worth it?";                                                      pause 3
tobias displayed;                                                     pause 2
tobias say Completely. Found this fellow at the summit hut:;          pause 2
tobias pic "$PICTURE";                                                pause 5
ada "That is the best dressed duck I have seen all year";             pause 3
tobias displayed;                                                     pause 1
tobias react ❤️;                                                      pause 3
