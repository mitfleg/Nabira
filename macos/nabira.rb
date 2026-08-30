cask "nabira" do
  version "3.4.1"
  sha256 "e8b39b34e19113023cda8e88fc430c9a4c3654e6104d56a7177f8142a347692d"

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
