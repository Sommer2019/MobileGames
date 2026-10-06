# Mobile Games für die Nintendo Switch

Homebrew-Version (offline) mit Schach, Schiffe versenken, 4 gewinnt, Dame,
Mühle, Kniffel, Snake, Solitär und Würfelbecher –
Regeln wie in der App. C++17 mit SDL2/SDL2_ttf, Texte in der Systemschrift
der Switch.

Nur dieser Branch (`switch`) baut die Switch-Version (`.github/workflows/switch.yml`);
jeder Push legt ein Release `switch-build-N` mit `MobileGames-Switch-N.nro` an.

## Installieren
Konsole mit Custom Firmware (z. B. Atmosphère): die `.nro` nach `sdmc:/switch/`
kopieren und im Homebrew-Menü starten. Rekorde und Würfelverlauf liegen in
`sdmc:/switch/mobilegames/save.txt`.

## Steuerung
Steuerkreuz/Stick bewegen, A bestätigen, B zurück, + Pause/Beenden.
Würfelbecher: Y legt den gewählten Würfel beiseite, L/R ändern die Anzahl,
X löscht den Verlauf. Im Handheld-Modus geht alles auch per Touch.

## Bauen
- Switch: `make` mit devkitPro (`switch-sdl2`, `switch-sdl2_ttf`)
- PC zum Ausprobieren: `make -f Makefile.pc && ./build_pc/mobilegames`
  (Tastatur: Pfeile, Enter = A, Esc = B, Y/X, Q/E = L/R, P = +)
- Regeltests: `make -f Makefile.pc test`
