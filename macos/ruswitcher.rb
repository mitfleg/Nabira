cask "ruswitcher" do
  version "3.1.0"
  sha256 "ebf0576c741b741e28790151213f4769567d262fd8b8b06b34c1eeb932e9de21"

  url "https://github.com/rashn/RuSwitcher/releases/download/v#{version}/RuSwitcher-#{version}.dmg"
  name "RuSwitcher"
  desc "Lightweight keyboard layout switcher, free alternative to PuntoSwitcher"
  homepage "https://github.com/rashn/RuSwitcher"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :ventura

  app "RuSwitcher.app"

  zap trash: [
    "~/Library/Logs/RuSwitcher",
    "~/Library/Preferences/com.ruswitcher.app.plist",
  ]
end
