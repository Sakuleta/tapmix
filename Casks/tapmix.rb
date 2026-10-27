cask "tapmix" do
  version "0.2.2"
  sha256 "b8ef7637f13d0ec1d532d0b22c29c0d6161ac9f9ca82d20cdb5f7f1cb30ce2c6"

  url "https://github.com/Sakuleta/tapmix/releases/download/v#{version}/Tapmix-#{version}.zip"
  name "Tapmix"
  desc "Per-app volume mixer for macOS"
  homepage "https://github.com/Sakuleta/tapmix"

  depends_on macos: ">= :sequoia"
  app "Tapmix.app"
end
