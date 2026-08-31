cask "seen" do
  version "0.1.4"
  sha256 "NEW1261"

  url "https://github.com/execsumo/seen/releases/download/v#{version}/Seen-#{version}.dmg"
  name "Seen"
  desc "Seen menu bar app"
  homepage "https://github.com/execsumo/seen"

  depends_on macos: :sequoia

  app "Seen.app"
  # `seen mcp` is the MCP transport, so the CLI has to be on PATH for any agent
  # integration to work — shipping the app alone leaves `claude mcp add seen --
  # seen mcp` as command-not-found.
  binary "#{appdir}/Seen.app/Contents/Resources/bin/seen"

  uninstall quit: "com.execsumo.seen"

  zap trash: [
    "~/Library/Application Support/Seen",
    "~/Library/Caches/com.execsumo.seen",
    "~/Library/Preferences/com.execsumo.seen.plist",
  ]
end
