# Mobile Games für die Nintendo Switch

Homebrew-Version (offline) mit allen Spielen der App: Schach, Schiffe versenken,
Vier in einer Reihe, Dame, Mühle, Würfelkönig, Darts, Billard, Snake, Solitär, Kugellabyrinth,
Mahjong und Würfelbecher –
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
Labyrinth: Stick neigt das Brett (Y schaltet auf Joy-Con-Bewegung, falls verfügbar).
Darts: Stick zielt, A wirft. Billard: Stick zielt, L/R fein, A halten = Stoßkraft,
X legt die Weiße (Ball in der Hand), Y wählt Effet.
Würfelbecher: Y legt den gewählten Würfel beiseite, L/R ändern die Anzahl,
X löscht den Verlauf. Im Handheld-Modus geht alles auch per Touch.

## Geheimnisse
Im Hauptmenü ↑ ↑ ↓ ↓ ← → ← → B A + drücken (wie der Geheimcode in der App, nur mit
B, A und + statt Lautstärke und Ladekabel). Danach gibt es die Kachel „Geheimmenü“:
Retro-Modus (Retro-Handy-Snake, Pixel-Billard), Disco-Kugeln, Gummiball, Albtraum-Labyrinth,
Großmeister (stärkerer Computer bei Schach und Dame), Glückspilz-Computer (Würfelkönig) und
Easy Mode (alle Labyrinth-Level frei).

## Bauen
- Switch: `make` mit devkitPro (`switch-sdl2`, `switch-sdl2_ttf`)
- PC zum Ausprobieren: `make -f Makefile.pc && ./build_pc/mobilegames`
  (Tastatur: Pfeile, Enter = A, Esc = B, Y/X, Q/E = L/R, P = +)
- Regeltests: `make -f Makefile.pc test`
