cask "nabira" do
  version "3.4.6"
  sha256 "181d203ab23da170c45b17da0a75eabbf74eed44eb48eec2f73add0f7765abdc"

  url "https://nabira.site/downloads/Nabira-macOS.dmg?version=#{version}"
  name "Nabira"
  desc "Lightweight keyboard layout switcher, free alternative to PuntoSwitcher"
  homepage "https://nabira.site"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :ventura

  app "Nabira.app"

  zap trash: [
    "~/Library/Logs/Nabira",
    "~/Library/Preferences/com.mitfleg.nabira.app.plist",
  ]
end
