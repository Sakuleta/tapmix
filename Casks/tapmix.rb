cask "tapmix" do
  version "0.2.3"
  sha256 "6ad0f84df9681965af078afaedc3c9e3eca441595545519d2d95b6b38280666f"

  url "https://github.com/Sakuleta/tapmix/releases/download/v#{version}/Tapmix-#{version}.zip"
  name "Tapmix"
  desc "Per-app volume mixer for macOS"
  homepage "https://github.com/Sakuleta/tapmix"

  depends_on macos: ">= :sequoia"
  app "Tapmix.app"
end
