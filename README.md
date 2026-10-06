# Mobile Games

Eine Flutter-App (Android ab Version 10, iPhone und iPad) mit zwölf Spielen:

| Mehrspieler (online P2P und an einem Gerät) | Spieler | Einzelspieler |
| --- | --- | --- |
| ♟️ Schach (+ Computer) | 2 | 🟤 Kugellabyrinth (Bewegungssensor, 26 Level, auch ohne Rand) |
| ⚪ Dame (+ Computer) | 2 | 🀄 Mahjong (immer lösbar) |
| ⭕ Mühle (+ Computer) | 2 | 🐍 Snake • 🃏 Solitär (Klondike) |
| 🚢 Schiffe versenken (+ Computer, Pass & Play) | 2 | 🎯 Darts allein (501/301/Rund um die Uhr) |
| 🔴 4 gewinnt (+ Computer) | 2–4 | 🎱 Billard allein (8 zum Schluss / Reihenfolge 1–15) |
| 🎲 Kniffel (+ Computer, Handy schütteln zum Würfeln) | 1–4 | |
| 🎯 Darts | 2–4 | |
| 🎱 Billard 8-Ball | 2 | |

Dazu: 🏆 **Turniermodus** (mehrere Spiele × mehrere Runden gegen Freunde, Punktetabelle),
**Freundschaftsanfragen** (beide stehen danach in der Liste des anderen), **Freundesliste mit Online-Status**, **Chat** mit Freunden (auch offline zugestellt),
**Chat im Spiel**, Pop-up und System-Benachrichtigung bei Einladungen und Nachrichten.
🏅 **Bestenliste** für die Einzelspieler-Spiele (Snake, Solitär, Mahjong, Kugellabyrinth,
Kniffel allein, Darts allein, Billard allein): eigene Top 10, Freunde und weltweit.
Solitär zählt Punkte nach den klassischen Windows-Regeln inkl. Zeitbonus.
🔊 **Sounds** (Kugelklacken, Würfel, Karten, Spielsteine, Sieg …) – selbst erzeugt mit
`tool/make_sounds.py`, abschaltbar oben auf der Startseite.
🎮 Und irgendwo steckt ein Geheimnis für Kenner alter Konsolen …

**Widgets** (Android und iOS 17+): 🎲 *Würfel* – 1–6 Würfel direkt auf dem Startbildschirm,
antippen zum Würfeln (iOS: Anzahl über „Widget bearbeiten“; 📳 öffnet den Würfelbecher, dort
klappt auch Schütteln). 🎮 *Spieleabend* – ungelesene Nachrichten, Freundesanfragen, wer online
ist und die zuletzt gespielten Spiele zum direkten Starten.

## Download

Jeder Push auf `main` baut per GitHub Actions automatisch eine APK:

* **Releases** → neuester Eintrag `Build N` → `MobileGames-N.apk` herunterladen und installieren
  (Installation aus unbekannten Quellen erlauben).
* Alternativ unter **Actions → Build → Artifacts**.
* **iPhone & iPad:** Im selben Release liegt `MobileGames-N-iOS-iPadOS-unsigned.ipa`
  (eine universelle App für iOS und iPadOS). Sie ist *unsigniert* und lässt sich erst nach
  eigenem Signieren installieren (z. B. AltStore/Sideloadly oder Apple-Developer-Account).
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
  signiert und Ende-zu-Ende verschlüsselt (NIP-04) und werden von den Relays nicht
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
* **Chat:** Freundes-Chats sind verschlüsselte Nostr-Direktnachrichten (NIP-04). Diese
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
