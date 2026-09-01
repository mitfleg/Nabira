cask "nabira" do
  version "3.4.4"
  sha256 "74d4f545378168f81c5fa1e49fe744a0d17a02af3d53f7b6a95a7f728a89fa5b"

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
