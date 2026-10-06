#!/usr/bin/env bash
# Packs the Linux bundle as .deb: packaging/linux/make_deb.sh <version> <out.deb>
set -euo pipefail
version="$1"
out="$2"
root="$(mktemp -d)"
mkdir -p "$root/DEBIAN" "$root/opt/mobile-games" "$root/usr/bin" \
  "$root/usr/share/applications" "$root/usr/share/icons/hicolor/512x512/apps"
cp -r build/linux/x64/release/bundle/. "$root/opt/mobile-games/"
ln -s /opt/mobile-games/mobile_games "$root/usr/bin/mobile-games"
cp packaging/linux/mobile-games.desktop "$root/usr/share/applications/"
cp assets/icon/icon.png "$root/usr/share/icons/hicolor/512x512/apps/mobile-games.png"
cat > "$root/DEBIAN/control" <<CONTROL
Package: mobile-games
Version: $version
Section: games
Priority: optional
Architecture: amd64
Maintainer: Sommer2019 <noreply@github.com>
Depends: libgtk-3-0 | libgtk-3-0t64, libsecret-1-0, libasound2 | libasound2t64, libgstreamer1.0-0, libgstreamer-plugins-base1.0-0, gstreamer1.0-plugins-good
Homepage: https://github.com/Sommer2019/MobileGames
Description: Mobile Games
 Schach, Schiffe versenken, 4 gewinnt, Kniffel, Darts, Billard und mehr -
 allein oder online mit Freunden, ohne eigenen Server.
CONTROL
dpkg-deb --build --root-owner-group "$root" "$out"
rm -rf "$root"
