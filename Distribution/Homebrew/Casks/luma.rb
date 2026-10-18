cask "luma" do
  version "0.2.0"
  sha256 "b5f4df979a02fb9fe0fe051608b4541145687e42659df8692bceb5765662f028"

  url "https://github.com/felixlheureux/luma/releases/download/v#{version}/Luma-#{version}-arm64.dmg"
  name "Luma"
  desc "Local-first storage review and maintenance"
  homepage "https://github.com/felixlheureux/luma"

  livecheck do
    skip "Development prereleases are reviewed manually"
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Luma.app"

  uninstall quit: "app.luma.mac"

  caveats do
    <<~EOS
      Development build. macOS may block first launch.
      Homebrew preserves quarantine and does not change system security settings.
    EOS
  end
end
