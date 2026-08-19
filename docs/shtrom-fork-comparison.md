# Vergleich mit shtrom/adium (hg-Konserve der 1.6/1.7-Linie)

Geprüft am 2026-08-22 gegen unseren master. [shtrom/adium](https://github.com/shtrom/adium) ist ein
echter GitHub-Fork (SHAs vergleichbar, letzter Push Dezember 2020) und konserviert den **finalen
Mercurial-Stand** bis 2016, den der GitHub-Spiegel nie bekam: `adium-1.6` ist der nie
veröffentlichte 1.6-Kandidat (267 Commits gegenüber unserer Linie), `master` das instabilere
1.7hg/default (~30 weitere). Merge-Basis mit uns ist schon das 1.5.9-Changelog (2013) — die
1.5.10.x-Inhalte existieren auf beiden Linien mit verschiedenen SHAs, weshalb die rohen Zahlen
stark übertreiben.

## Schon bei uns (über 1.5.10.x geerbt oder selbst gebaut, keine Aktion)

SSLRead-EOF-Behandlung in ssl-cdsa (#16356), Reachability über Schlaf/Aufwachen, HiDPI-Erkennung
bei Zweitmonitor (#16552), Konten-nibs aus dem eigenen Bundle laden (#16591, bei uns über
ai_loadNibNamed gelöst), libotr 4.0.0 samt SMP, MySpace-Entfernung, RBSplitView-Entfernung,
libpurple-Stände (wir: 2.14.14).

## Ernte-Kandidaten (bei uns fehlend, geprüft)

Commits referenzieren shtrom/adium. Reihenfolge nach Wert:

1. **Cocoa-Neubau des libpurple-Request-UIs** — `b558e23d8` (+ `99e69e1d8`, `061335c4e`):
   AMPurpleRequestFieldsController ohne WebView, eigene xibs je Feldtyp (Boolean, Choice, Integer,
   List, MultiList, MultilineString, SecureString, String). Bei uns ist genau diese Klasse der
   **letzte WebView-Nutzer** (Deprecation-Rest in modernisation.md). Konzept und Feldlogik
   übernehmen; ob xibs von 2013 oder unsere AISettingsFormView die Darstellung stellt, ist beim
   Einbau zu entscheiden.
2. **Verschlüsselungs-Details-Fenster** — `918aa4980` (+ `175`/`edceaa599`-Umfeld): Vor der
   Zertifikatsansicht ein Fenster mit Aussteller, TLS-Version, Cipher, MAC, Schlüsselaustausch;
   zieht ~350 Zeilen SecureTransport-Introspektion in ssl-cdsa nach sich. Vorbehalt: wir wollen
   ssl-cdsa mittelfristig auf OpenSSL heben — die UI-Seite bleibt, die Introspektion wäre neu zu
   schreiben.
3. **windowWillClose: super zuerst** — `5f1abc62b` (#16579): AIAuthorizationRequestsWindowController
   und AISpecialPasswordPromptController rufen super am Ende; der Fix zieht es an den Anfang, weil
   super die Controller-Freigabe anstößt. **Bug bei uns noch vorhanden** (beide Dateien noch MRR).
4. **Einfüge-Privatsphäre** — `a80f5d288`: Beim Einfügen von HTML keine eingebetteten Bilder
   nachladen (WebResourceLoadDelegate, der nil liefert). Verhindert ungewollte Netzzugriffe beim
   Paste. Bei uns fehlt das; AIMessageEntryTextView.
5. **Mitternachts-Rotation der Transkripte** — `24ff5d93c` (#6786) + Schutz `628253902`:
   Tagelange Chats werden um Mitternacht geteilt. Unser AILoggerPlugin rotiert gar nicht.
6. **XtrasInstaller-Fixes** — `771b5a417` (#16795, sharedApplication-Delegate statt NSApp; bei uns
   noch alte Form, Source/XtrasInstaller.m:410) und `fa6c033b5` (#16288 Installation von der
   Website).
7. **Transkript-Viewer: Auswahl nach Löschen** — `f8f0d9f1c` (#11420). Zustand bei uns ungeprüft.
8. **Link-Scanner** — `026e9bdc6` (#16217/#16413, Scan-Position nach Fund weiterrücken,
   MIN_LINK_LENGTH 4). Unser AHHyperlinkScanner ist strukturell anders; erst prüfen, ob die
   Bug-Klasse existiert.
9. **Emoticon-Menü-Paket** — Trenner je Pack `d9a2f8805` (#16452), Abschalt-Option `149909ebb`
   (#16407), Pfeil-Cursor `727c3b355` (#16432), Ausrichtung `6737b11e1` (#16434), Toolbar-Item
   raus `4170f0088` (#16396). Passt zum offenen Punkt „Emoticon-Tastatur" der UI-Inventur.
10. **Kleinkram**: Edit-Menü-Einträge `72c4c165b` (#16416), DDG-Suche im Kontextmenü `2666f79b4`,
    kombiniertes Link/Browser-Toolbar-Item `baf2dd8a4` (#15404), OTR an zuletzt aktive Instanz
    `f6076f069`, OTR-Logging-Frage ohne Fokusklau `0c279dec0`, isOnline-Schnellpfad
    `8626e38ff` (1.7), SenTestingKit→XCTest `50f1bb7c2` (1.7, falls Tests wiederbelebt werden).

## Themen-Zweige des Forks (eigene Inventur wert)

`Lurch4Adium-0.0.4/*` (**OMEMO**, XEP-0384 — für den XMPP-Fahrplan relevant),
`HistoricMUCMessages`, `IRCServerConsole`, `AddConfigureRoomForMUCs`, `EmoticonsMenu`,
`AdiumApplescriptRunnerUsingXPC` (unser AppKit-am-Mainthread-Problem!), `AutoLayout`,
`PreferencesRedux`, `Sandboxing`, `eventloop_libdispatch`, `voice-video`, `fix-autoscroll`,
`TorProxyType`, `AILoggerWithBlocks`, `JSXtras`. Tot: `GTalkOAuth2Support`/`GoogleOAuth2`,
`MSN-XMPP`, `libotr4.0.0` (gemerged), `10.6+`.

Der Klon liegt sitzungsgebunden im Scratchpad; dauerhafte Quelle ist GitHub.
