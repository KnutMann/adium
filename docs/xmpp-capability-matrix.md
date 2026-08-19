# XMPP-Fähigkeiten: Bestand und Rangfolge

Bestandsaufnahme vom 19.08.2026, gegen libpurple 2.14.14 (`Dependencies/source/libpurple/.../jabber/`),
die Fork-Patches (`Dependencies/patches/pidgin-2.14.14/jabber/`) und den AdiumY-Baum geprüft, nicht
aus dem Gedächtnis. Dies ist das von M17 im Plattform-Fahrplan verlangte Bestandsdokument.

## Schon vorhanden, kostet nichts

- **XEP-0198 Stream Management**: upstream in libpurple 2.14 enthalten. Fertig.
- **XEP-0191 Blocking**: im prpl vollständig, über adiumPurplePrivacy/ESBlockingPlugin an die UI
  angebunden. Braucht nur eine Verifikation (M16), keinen Code.
- **XEP-0184 Quittungen / XEP-0333 Marker**: eigene Fork-Patches (receipt.c, chatmarker.c); Empfang,
  Auto-Quittung und "displayed" beim Lesen laufen. Es fehlt allein die Pro-Nachricht-Anzeige.
- Ferner abgedeckt: 0030/0115, 0045, 0249, 0085, 0203, 0199, 0084/0153, 0163, 0237, 0047/0065/0096.

**AdiumY-Vorlagen**: keine neueren XEP-Serien als die in M17 gelisteten; der AdiumY-Baum wurde nach
den XEP-Commits ARC-migriert und umformatiert, Diffs sind Designvorlage, nie cherry-pickbar. AdiumYs
eigenes XEP-Audit steht auf "Proposed", auch dort ist Konformität unverifiziert.

## Rangfolge

**Schnell übernehmbar (AdiumY-Vorlage):**
1. **XEP-0280 Carbons** + zwingend **XEP-0334 Hints**: Nachrichten vom Handy erscheinen auch hier;
   größter Alltagsgewinn. Als prpl-Patch nach dem Muster von receipt.c bauen. Risiken: Duplikate
   gegen lokale Logs, und ohne `<private/>` auf OTR-Nachrichten landen OTR-Fragmente auf anderen
   Geräten. (AdiumY 186103ce, 3512b2b8, 69406099)
2. **XEP-0352 CSI**: weniger Traffic/Wakeups bei Idle; klein, an vorhandene Idle-Erkennung
   anbinden; braucht die explizite Aktiv-Politik aus M17. (AdiumY a54fe609 + 29901c55)
3. **XEP-0402 PEP-Bookmarks**: MUC-Liste/Autojoin synchron mit Gajim/Dino/Conversations;
   überschaubar, AdiumY hat Tests (407ebcf6). 0048 solo nicht bauen, seit 2020 Deprecated.

**Überschaubar, ohne Vorlage:**
4. **XEP-0410 MUC Self-Ping**: erkennt still gestorbene Raumsitzungen nach Netzwechseln und tritt
   neu bei; kleiner Timer über vorhandenen Ping-Code, Vorsicht vor Rejoin-Schleifen.

**Wertvoll, aber eigenes Projekt:**
5. **XEP-0313 MAM**: erst nach beschlossenem Verlaufs-/Reconnect-Modell plus XEP-0359-Dedup, sonst
   Duplikat-Generator. 6. **XEP-0363 HTTP Upload**: der einzige 2026 zuverlässige Dateitransfer,
   aber HTTPS-PUT, URL-Sicherheit und UI machen es groß. 7. **XEP-0308 Korrekturen**, gebündelt mit
   dem Pro-Nachricht-Zustandsmodell der Message-View (der Blocker ist die fehlende ID-zu-DOM-
   Zuordnung, dokumentiert in adiumPurpleSignals.m); wer das eine Datenmodell baut, schaltet 0308,
   0184-Haken und 0333 pro Nachricht zugleich frei.

**Verlockend, aber nein:** OMEMO (ohne geprüftes Kryptodesign fahrlässig), 0393 Styling (Eingriff in
die gesamte Darstellung, hinter Carbons einreihen), 0444/0461 (Experimental und ohne ID-Zuordnung
nicht darstellbar), Bind2/SASL2 (Kern-OP für null sichtbaren Nutzen), MIX (kein Deployment).

**Beschlossener Fahrplan (19.08.2026): Carbons+Hints → CSI → 0402-Bookmarks, in dieser Reihenfolge,
jeweils als prpl-Patch nach dem Muster von receipt.c/chatmarker.c und mit M16-Verifikation vor dem
nächsten Schritt. XEP-0191 wird nur getestet und als vorhanden verbucht. MAM, HTTP Upload und das
Pro-Nachricht-Zustandsmodell bleiben eigene Projekte und beginnen nicht nebenbei.**
