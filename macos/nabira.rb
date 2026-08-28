cask "nabira" do
  version "3.3.0"
  sha256 "22e1ffa0c2021eb75c0d341d175ef7da310b5411e82456125d8f24fa59a02a19"

  url "https://github.com/mitfleg/Nabira/releases/download/v#{version}/Nabira-#{version}.dmg"
  name "Nabira"
  desc "Lightweight keyboard layout switcher, free alternative to PuntoSwitcher"
  homepage "https://github.com/mitfleg/Nabira"

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
