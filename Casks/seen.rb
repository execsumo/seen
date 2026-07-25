cask "seen" do
  version "0.1.0"
  sha256 "7f2086be1b73855a5ac344d3818d7c450bdcd0c70ba3ba288f597314c26e6275"

  url "https://github.com/execsumo/seen/releases/download/v#{version}/Seen-#{version}.dmg"
  name "Seen"
  desc "Seen menu bar app"
  homepage "https://github.com/execsumo/seen"

  depends_on macos: :sequoia

  app "Seen.app"

  uninstall quit: "com.execsumo.seen"

  zap trash: [
    "~/Library/Application Support/Seen",
    "~/Library/Caches/com.execsumo.seen",
    "~/Library/Preferences/com.execsumo.seen.plist",
  ]
end
