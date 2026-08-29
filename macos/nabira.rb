cask "nabira" do
  version "3.3.0"
  sha256 "f736a0dfc6e5907ec25fcbe58aa5b59e053a00b52ee2607313c338f07e3ba484"

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
