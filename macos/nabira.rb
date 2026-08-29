cask "nabira" do
  version "3.3.1"
  sha256 "65d576a1861ea9509832818915d0b14c8a3af8b7955613c048a07812a6755056"

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
