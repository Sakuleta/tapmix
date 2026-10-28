cask "tapmix" do
  version "0.3.3"
  sha256 "dbaf9569bbb748dc2979022734a890fc13f73fa27559dc692eae0076a27353be"

  url "https://github.com/Sakuleta/tapmix/releases/download/v#{version}/Tapmix-#{version}.zip"
  name "Tapmix"
  desc "Per-app volume mixer for macOS"
  homepage "https://github.com/Sakuleta/tapmix"

  depends_on macos: ">= :sequoia"
  app "Tapmix.app"
end
