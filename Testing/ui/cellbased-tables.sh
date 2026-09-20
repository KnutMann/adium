#!/bin/zsh
# Alle Tabellen, die noch auf dem zellbasierten Modell laufen, mit dem, was den Umbau
# schwer oder leicht macht: ob die Tabelle aus einem XIB oder aus Code kommt, ob es ein
# Outline ist, ob eigene Zellen zeichnen, ob bearbeitet oder gezogen wird. Sortiert nach
# Aufwand, die leichtesten zuerst. Zellen, die nicht im Code, sondern im XIB stecken
# (Ankreuzfelder, Bilder, Aufklappmenues), werden ueber das XIB der Klasse mitgezaehlt.
cd "$(dirname "$0")/../.."
printf "%-4s %-52s %-5s %-4s %-5s %-4s %-4s %-6s\n" "Pkt" "Datei" "Quelle" "Outl" "Zelle" "Edit" "Drag" "Streif"
command grep -rl "objectValueForTableColumn" --include="*.m" Source Plugins Frameworks/Adium Frameworks/AIUtilities \
| while read f; do
	base=$(basename "$f" .m)
	code=$(command grep -cE "\[\[NS(Table|Outline)View alloc\]|NS(Table|Outline)View \*\)\s*\[\[" "$f")
	xib=$(command grep -clE "IBOutlet.*NS(Table|Outline)View|@property.*IBOutlet.*NS(Table|Outline)View" "$f" "${f%.m}.h" 2>/dev/null | command grep -c ":[1-9]")
	outline=$(command grep -cE "NSOutlineView|outlineView:" "$f")
	cell=$(command grep -cE "setDataCell:|dataCellForTableColumn|willDisplayCell|AI[A-Za-z]*Cell\b|ImageTextCell|NSButtonCell|NSPopUpButtonCell" "$f")
	edit=$(command grep -cE "setObjectValue:.*forTableColumn|shouldEditTableColumn" "$f")
	drag=$(command grep -cE "writeRowsWithIndexes|acceptDrop|validateDrop" "$f")
	xibcells=0
	while IFS= read -r x; do
		[ -n "$x" ] || continue
		n=$(command grep -cE "(buttonCell|imageCell|popUpButtonCell|comboBoxCell|levelIndicatorCell) key=\"dataCell\"" "$x")
		xibcells=$((xibcells + n))
	done <<< "$(command grep -rl "customClass=\"$base\"" --include="*.xib" Resources Plugins Frameworks/Adium 2>/dev/null)"
	cell=$((cell + xibcells))
	# Streifen: die Regel ist, dass jede Datenliste sie hat. Im Code gesetzt oder im XIB der Klasse.
	stripes=$(command grep -c "setUsesAlternatingRowBackgroundColors:YES" "$f")
	while IFS= read -r x; do
		[ -n "$x" ] || continue
		n=$(command grep -c 'alternatingRowBackgroundColors="YES"' "$x")
		stripes=$((stripes + n))
	done <<< "$(command grep -rl "customClass=\"$base\"" --include="*.xib" Resources Plugins Frameworks/Adium 2>/dev/null)"
	st="FEHLT"; [ "$stripes" -gt 0 ] && st="ja"
	src="XIB"; [ "$code" -gt 0 ] && src="Code"
	o="-"; [ "$outline" -gt 0 ] && o="ja"
	c="-"; [ "$cell" -gt 0 ] && c="$cell"
	e="-"; [ "$edit" -gt 0 ] && e="ja"
	d="-"; [ "$drag" -gt 0 ] && d="ja"
	pts=$(( (outline>0)*4 + (cell>0)*2 + (edit>0)*2 + (drag>0)*3 ))
	printf "%-4s %-52s %-5s %-4s %-5s %-4s %-4s %-6s\n" "$pts" "${f#*/}" "$src" "$o" "$c" "$e" "$d" "$st"
done | sort -n -k1,1 -k2
