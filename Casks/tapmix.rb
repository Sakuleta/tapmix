cask "tapmix" do
  version "0.3.0"
  sha256 "eed9e848d2a1852d5a79f9a34ab10aa443c0d3f3ff08ec029c4746ec0a84f0d6"

  url "https://github.com/Sakuleta/tapmix/releases/download/v#{version}/Tapmix-#{version}.zip"
  name "Tapmix"
  desc "Per-app volume mixer for macOS"
  homepage "https://github.com/Sakuleta/tapmix"

  depends_on macos: ">= :sequoia"
  app "Tapmix.app"
end
