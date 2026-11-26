# Mobile Games

Eine Flutter-App (Android ab Version 10, iPhone und iPad) mit zwölf Spielen:

| Mehrspieler (online P2P und an einem Gerät) | Spieler | Einzelspieler |
| --- | --- | --- |
| ♟️ Schach (+ Computer) | 2 | 🟤 Kugellabyrinth (Bewegungssensor, 26 Level + endlos erzeugte, auch ohne Rand) |
| ⚪ Dame (+ Computer) | 2 | 🀄 Mahjong (immer lösbar) |
| ⭕ Mühle (+ Computer) | 2 | 🐍 Snake • 🃏 Solitär (Klondike) |
| 🚢 Schiffe versenken (+ Computer, Pass & Play) | 2 | 🎯 Darts allein (501/301/Rund um die Uhr) |
| 🔴 Vier in einer Reihe (+ Computer) | 2–4 | 🎱 Billard allein (8 zum Schluss / Reihenfolge 1–15) |
| 🎲 Würfelkönig (+ Computer, Handy schütteln zum Würfeln) | 1–4 | |
| 🎯 Darts | 2–4 | |
| 🎱 Billard 8-Ball | 2 | |

Dazu: 🏆 **Turniermodus** (mehrere Spiele × mehrere Runden gegen Freunde, Punktetabelle),
**Freundschaftsanfragen** (beide stehen danach in der Liste des anderen), **Freundesliste mit Online-Status**, **Chat** mit Freunden (auch offline zugestellt),
**Chat im Spiel**, Pop-up und System-Benachrichtigung bei Einladungen und Nachrichten.
🏅 **Bestenliste** für die Einzelspieler-Spiele (Snake, Solitär, Mahjong, Kugellabyrinth,
Würfelkönig allein, Darts allein, Billard allein): eigene Top 10, Freunde und weltweit.
Solitär zählt Punkte nach den klassischen Windows-Regeln inkl. Zeitbonus.
🔊 **Sounds** (Kugelklacken, Würfel, Karten, Spielsteine, Sieg …) – selbst erzeugt mit
`tool/make_sounds.py`, abschaltbar oben auf der Startseite.
🎮 Und irgendwo steckt ein Geheimnis für Kenner alter Konsolen …

**Widgets** (Android und iOS 17+): 🎲 *Würfel* – 1–6 Würfel direkt auf dem Startbildschirm,
antippen zum Würfeln (iOS: Anzahl über „Widget bearbeiten“; 📳 öffnet den Würfelbecher, dort
klappt auch Schütteln). 🎮 *Spieleabend* – ungelesene Nachrichten, Freundesanfragen, wer online
ist und die zuletzt gespielten Spiele zum direkten Starten.

🕹️ **Handhelds mit Controller** (z. B. AYN Thor, Odin, Retroid) und Querformat: Auf breiten
Bildschirmen wandern Statuszeile, Punkte und Knöpfe in eine Seitenleiste, das Brett bekommt die
volle Höhe; App-Leisten werden auf niedrigen Bildschirmen schmaler. Steuerung:
**Steuerkreuz/linker Stick** wechselt zwischen Knöpfen (ein gelber, leuchtender Rahmen zeigt,
wo man ist; aus dem Suchfeld geht es mit hoch/runter wieder heraus), **A** drückt, **B** geht zurück.
Der **rechte Stick** blendet einen Zeiger ein – **A** oder **R1** tippt dort, gedrückt halten
zieht (Karten, Queue). Snake lenkt mit dem Steuerkreuz (A startet, Start pausiert),
das Kugellabyrinth kippt per Stick/Steuerkreuz oder Bewegungssensor; Snake und Labyrinth
legen ihr Hochkant-Feld im Querformat quer. Auf dem unteren Thor-Bildschirm läuft die App
ebenfalls (Hochkant-Ansicht).

📟 **Zweiter Bildschirm** (Dual-Screen wie AYN Thor): Unten läuft ein eigener kleiner Teil der
App – wie beim DS. *Würfelkönig*: Würfel oben, der Block unten (Feld antippen zum Eintragen,
Würfeln-Knopf). *Stichprophet*: Punkteblock mit Ansagen/Stichen der Runde unten, dort auch
Stiche ansagen und Trumpf wählen. *Sudoku*: großer Ziffernblock unten, oben wählt das
Steuerkreuz das Feld. *Schiffe versenken*: eigene Flotte unten, oben das ganze Meer zum Schießen.
*Schocken*: Spielertabelle mit Deckeln unten. *Darts*: Board oben, Punktetafel unten.
*Snake, Kugellabyrinth, Solitär, Mahjong*: Punkte/Zeit und Knöpfe (Start/Pause, Neu, Tipp,
Rückgängig) unten. *Letzte Karte, Stapelfix, Domino*: die eigene Hand unten (spielbare Karten
hell, antippen zum Ablegen; Ziehen/Passen), der Tisch oben. *Schach*: Zugliste und geschlagene
Figuren unten. *Online-Spiele*: der Chat mit Schnellantworten unten. Andere Spiele zeigen unten,
wer dran ist, ohne Spiel eine Controller-Übersicht. Abschaltbar über das Symbol oben auf der Startseite. Wird die App
versehentlich auf dem unteren Bildschirm gestartet, bietet sie den Wechsel nach oben an
(auch später über ⤒ auf der Startseite).

## Download

Jeder Push auf `main` baut per GitHub Actions automatisch eine APK:

* **Releases** → neuester Eintrag `Build N` → `MobileGames-N.apk` herunterladen und installieren
  (Installation aus unbekannten Quellen erlauben).
* Alternativ unter **Actions → Build → Artifacts**.
* **iPhone & iPad:** Im selben Release liegt `MobileGames-N-iOS-iPadOS-unsigned.ipa`
  (eine universelle App für iOS und iPadOS). Sie ist *unsigniert* und lässt sich erst nach
  eigenem Signieren installieren (z. B. AltStore/Sideloadly oder Apple-Developer-Account).
* **Windows:** `MobileGames-N-Windows-Setup.exe` (ohne Admin-Rechte; unsigniert, daher bei
  SmartScreen „Weitere Informationen“ → „Trotzdem ausführen“) oder `…-Windows-portable.zip`.
* **macOS (ab 12):** `MobileGames-N-macOS.dmg` → App in „Programme“ ziehen, beim ersten Start
  Rechtsklick → „Öffnen“ (nicht notarisiert). Oder per Homebrew:
  ```
  brew tap sommer2019/mobilegames https://github.com/Sommer2019/MobileGames
  brew install --cask mobile-games
  brew upgrade --cask --greedy mobile-games   # Update auf den neuesten Build
  ```
* **Linux:** `MobileGames-N-Linux-amd64.deb` (`sudo apt install ./MobileGames-N-Linux-amd64.deb`)
  oder `…-Linux-x64.tar.gz` entpacken und `MobileGames/mobile_games` starten.
  Am Computer gibt es keine Widgets; QR-Codes scannen geht nur am Mac (sonst Code eintippen).
* **Web-App (ohne Installation, auch iPhone):** https://sommer2019.github.io/MobileGames/
  in Safari öffnen → Teilen → „Zum Home-Bildschirm“. Startet dann wie eine App im Vollbild und
  ist nach jedem Push auf `main` automatisch aktuell. Ohne Widgets und ohne Benachrichtigungen
  bei geschlossener App. Die Web-App hat ein eigenes Konto; über „Konto auf neues Handy
  übertragen“ lässt sich das bisherige mitnehmen.

## Serverloser Multiplayer

Es gibt **kein eigenes Backend**, nichts muss betrieben oder bezahlt werden.

* **Konto:** Beim ersten Start wird auf dem Gerät ein Schlüsselpaar (secp256k1) erzeugt.
  Daraus ergibt sich ein kurzer **Freundescode** wie `K7Q2M-9XW4P` (Hash des Schlüssels, über
  einen signierten Nostr-Eintrag auflösbar, nicht fälschbar) und ein **QR-Code**. Kein Login.
* **Freundesliste:** Freundescode kopieren und teilen, beim Freund unter
  *Konto & Freunde → Freund* einfügen. Ob Freunde online sind, sieht man am grünen Punkt.
* **Gegner finden:** Für die Vermittlung (Matchmaking, Einladungen, Online-Status) werden
  öffentliche, kostenlose [Nostr](https://nostr.com)-Relays genutzt. Nachrichten sind
  signiert und Ende-zu-Ende verschlüsselt (NIP-44) und werden von den Relays nicht
  gespeichert (ephemere Events).
* **Freunde:** Wer einen Freundescode hinzufügt, schickt eine Anfrage (auch an Offline-Freunde).
  Nimmt der andere an, sind beide gegenseitig befreundet.
* **Turnier:** Der Host wählt Spiele und Rundenzahl und lädt 1–3 Freunde ein. Alle Partien laufen
  im selben Raum; Sieg 3 Punkte, Unentschieden 1 Punkt. Wer anfängt, wechselt von Partie zu Partie.
* **Räume:** Bei 3–4 Spielern ist der Host der Knotenpunkt: Er hält zu jedem Mitspieler eine
  eigene P2P-Verbindung und leitet Züge weiter (eine gemeinsame Reihenfolge für alle).
* **Bestenliste:** Jeder veröffentlicht seine Bestwerte als ersetzbaren Nostr-Eintrag
  (NIP-78). Ohne Server lassen sich die Werte nicht prüfen; die Freunde-Ansicht ist daher die
  aussagekräftigste, offensichtlich unmögliche Werte werden ausgefiltert.
* **Chat:** Freundes-Chats sind verschlüsselte Nostr-Direktnachrichten (NIP-44). Diese
  speichern die Relays, damit sie auch ankommen, wenn der Freund gerade offline ist.
* **Benachrichtigungen:** Läuft die App im Hintergrund, kommen Einladungen und Nachrichten als
  System-Benachrichtigung. Auf Android hält ein kleiner Vordergrund-Dienst die Verbindung offen
  (abschaltbar unter *Konto & Freunde → Benachrichtigungen*, dort auch ein Test-Knopf).
  Ist die App ganz geschlossen – oder auf iOS länger im Hintergrund – geht das ohne eigenen
  Push-Server nicht; Nachrichten werden dann beim nächsten Öffnen nachgeladen.
* **Spielen:** Danach verbinden sich die Geräte direkt per **WebRTC (Peer-to-Peer)**.
  Wenn beide Netze keine Direktverbindung zulassen (strenges NAT, kein TURN-Server),
  laufen die Spielzüge automatisch verschlüsselt über die Relays weiter. Das Symbol oben
  rechts zeigt `P2P` oder `Relay`.

## iOS-App signieren

Die `.ipa` aus dem Release ist unsigniert. Möglichkeiten:

1. **AltStore / SideStore** (kostenlos, eigene Apple-ID): AltServer auf Mac/PC installieren,
   iPhone per Kabel verbinden, AltStore aufs iPhone bringen, dann in AltStore die `.ipa` öffnen.
   Gilt 7 Tage, AltStore erneuert es automatisch (max. 3 Apps).
2. **Sideloadly** (Windows/Mac, kostenlos): `.ipa` hineinziehen, Apple-ID eingeben, installieren.
   Auf dem Gerät unter *Einstellungen → Allgemein → VPN & Geräteverwaltung* dem Entwickler
   vertrauen. Ebenfalls 7 Tage gültig.
3. **Apple Developer Program** (99 €/Jahr): ein Jahr gültig, TestFlight für Freunde möglich.
   Die Pipeline kann dann mit Zertifikat + Provisioning-Profil als Secrets automatisch signieren.

Ab iOS 16 muss außerdem der **Entwicklermodus** aktiviert sein
(*Einstellungen → Datenschutz & Sicherheit → Entwicklermodus*).

## Entwicklung

```bash
flutter pub get
flutter analyze
flutter test          # Spiellogik, Krypto, Matchmaking, Netzwerk, Widgets
flutter run
```

Struktur:

```
lib/core/nostr/   Schlüssel, Signaturen, Verschlüsselung, Relay-Verbindungen
lib/core/net/     Messenger, Matchmaker, GameSession (WebRTC + Relay-Fallback)
lib/core/         Konto, Freundesliste, Online-Status
lib/games/<spiel> Spiellogik (rein Dart, getestet) + Bildschirm
lib/ui/           Startseite, Lobby, Freunde
test/             Unit- und Widget-Tests
```

### Geobingo: Street-View-Schlüssel

Die Geo-Spiele laufen ohne Schlüssel mit **Panoramax** (freie Straßenbilder, viel in Frankreich)
und **KartaView** (früher OpenStreetView).
Für Google Street View und Mapillary braucht es Schlüssel. Die Build-Pipeline nimmt sie als
Repository-Variable oder -Secret:

* `GOOGLE_MAPS_KEY` – Google Cloud: Projekt mit Zahlungsart anlegen, **Maps JavaScript API**
  aktivieren, API-Schlüssel erstellen. Unter „Schlüssel einschränken“ als Website
  `https://sommer2019.github.io/*` eintragen (die App lädt Street View von dieser Adresse aus)
  und nur die Maps JavaScript API erlauben. Unter „Kontingente“ ein Tageslimit für
  „Dynamic Street View“ setzen, z. B. 150 – dann bleibt es im Gratiskontingent von
  5.000 Panoramen im Monat.
* `MAPILLARY_TOKEN` – kostenlos: bei mapillary.com anmelden → Developers → App registrieren →
  „Client Token“ kopieren (beginnt mit `MLY|`).

Lokal: `flutter run --dart-define=GOOGLE_MAPS_KEY=… --dart-define=MAPILLARY_TOKEN=…`.
Ortssuche und Ländererkennung laufen über OpenStreetMap (Nominatim), die Karte im
Mapillary-Modus über OpenFreeMap – beides ohne Schlüssel.

### Release-Signierung (optional, empfohlen)

Ohne Konfiguration wird die APK mit einem Debug-Schlüssel signiert, der in CI bei jedem
Lauf neu entsteht – Updates lassen sich dann nicht über eine alte Version installieren.
Für stabile Updates einen eigenen Schlüssel als Repository-Secrets hinterlegen:

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mobilegames
base64 -w0 release.jks   # Ausgabe als Secret ANDROID_KEYSTORE_BASE64
```

Secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`.
