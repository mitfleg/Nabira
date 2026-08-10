cask "ruswitcher" do
  version "3.2.0"
  sha256 "009da93d523c0e85c9c6005d568fc6558a2ce4204bb703ea99a621ae6720d011"

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
