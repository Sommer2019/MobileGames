# Mobile Games

Eine Flutter-App (Android ab Version 10, zusätzlich iOS) mit sieben Spielen:

| Mehrspieler (online P2P oder offline) | Einzelspieler |
| --- | --- |
| ♟️ Schach (inkl. Computergegner) | 🟤 Kugellabyrinth (Bewegungssensor, 5 Level) |
| 🚢 Schiffe versenken (inkl. Computergegner) | 🀄 Mahjong (immer lösbar generiert) |
| 🔴 4 gewinnt (inkl. Computergegner) | 🎱 Billard (alle Kugeln mit wenig Stößen versenken) |
| 🎲 Kniffel (1–4 Spieler offline, 2 online) | |

## Download

Jeder Push auf `main` baut per GitHub Actions automatisch eine APK:

* **Releases** → neuester Eintrag `Build N` → `MobileGames-N.apk` herunterladen und installieren
  (Installation aus unbekannten Quellen erlauben).
* Alternativ unter **Actions → Build → Artifacts**.
* Für iOS wird eine *unsignierte* `.ipa` als Artifact gebaut. Installieren lässt sie sich
  nur nach eigenem Signieren (z. B. AltStore/Sideloadly oder mit Apple-Developer-Account).

## Serverloser Multiplayer

Es gibt **kein eigenes Backend**, nichts muss betrieben oder bezahlt werden.

* **Konto:** Beim ersten Start wird auf dem Gerät ein Schlüsselpaar (secp256k1) erzeugt.
  Der öffentliche Schlüssel ist dein **Freundescode** (`npub1…`). Kein Login, keine E-Mail.
* **Freundesliste:** Freundescode kopieren und teilen, beim Freund unter
  *Konto & Freunde → Freund* einfügen. Ob Freunde online sind, sieht man am grünen Punkt.
* **Gegner finden:** Für die Vermittlung (Matchmaking, Einladungen, Online-Status) werden
  öffentliche, kostenlose [Nostr](https://nostr.com)-Relays genutzt. Nachrichten sind
  signiert und Ende-zu-Ende verschlüsselt (NIP-04) und werden von den Relays nicht
  gespeichert (ephemere Events).
* **Spielen:** Danach verbinden sich die Geräte direkt per **WebRTC (Peer-to-Peer)**.
  Wenn beide Netze keine Direktverbindung zulassen (strenges NAT, kein TURN-Server),
  laufen die Spielzüge automatisch verschlüsselt über die Relays weiter. Das Symbol oben
  rechts zeigt `P2P` oder `Relay`.

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
