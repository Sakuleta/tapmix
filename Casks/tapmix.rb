cask "tapmix" do
  version "0.2.4"
  sha256 "2464f0553474e27e7b45b7811ff57a5b1fb20f35d08e9c06520b647240428c77"

  url "https://github.com/Sakuleta/tapmix/releases/download/v#{version}/Tapmix-#{version}.zip"
  name "Tapmix"
  desc "Per-app volume mixer for macOS"
  homepage "https://github.com/Sakuleta/tapmix"

  depends_on macos: ">= :sequoia"
  app "Tapmix.app"
end
