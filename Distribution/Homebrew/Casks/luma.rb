cask "luma" do
  version "0.2.1"
  sha256 "0674d90616412ef8735194d9cb88bf0304dafed47d9ce48e87b8abd84f8c1c9a"

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
