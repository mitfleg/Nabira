cask "nabira" do
  version "3.4.7"
  sha256 "14ae41c4e30c37708c7836735d526130db6040d3bf53d823636d4ec583f4f8e7"

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
