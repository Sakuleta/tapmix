cask "tapmix" do
  version "0.2.1"
  sha256 "2429020114cbbe75d5c61a52747e9284ae404edb62590554fe87c2b6e11cbf4b"

  url "https://github.com/Sakuleta/tapmix/releases/download/v#{version}/Tapmix-#{version}.zip"
  name "Tapmix"
  desc "Per-app volume mixer for macOS"
  homepage "https://github.com/Sakuleta/tapmix"

  depends_on macos: ">= :sequoia"
  app "Tapmix.app"
end
