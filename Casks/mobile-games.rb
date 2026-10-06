# Homebrew cask for the macOS app.
#   brew tap sommer2019/mobilegames https://github.com/Sommer2019/MobileGames
#   brew install --cask mobile-games
# Always installs the newest build; update with
#   brew upgrade --cask --greedy mobile-games
cask "mobile-games" do
  version :latest
  sha256 :no_check

  url "https://github.com/Sommer2019/MobileGames/releases/latest/download/MobileGames-macOS.zip"
  name "Mobile Games"
  desc "Board and arcade games, alone or online with friends"
  homepage "https://github.com/Sommer2019/MobileGames"

  depends_on macos: ">= :monterey"

  app "Mobile Games.app"

  # The app is not notarized (no paid Apple developer account), so macOS
  # would refuse to open it after the download.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Mobile Games.app"]
  end

  zap trash: [
    "~/Library/Containers/de.sommer.mobilegames",
    "~/Library/Application Scripts/de.sommer.mobilegames",
  ]
end
