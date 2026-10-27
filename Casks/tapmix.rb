cask "tapmix" do
  version "0.3.1"
  sha256 "87eb35d6575b5897443fc10d54980722ae2df7ba921263771307a758ab1cee3e"

  url "https://github.com/Sakuleta/tapmix/releases/download/v#{version}/Tapmix-#{version}.zip"
  name "Tapmix"
  desc "Per-app volume mixer for macOS"
  homepage "https://github.com/Sakuleta/tapmix"

  depends_on macos: ">= :sequoia"
  app "Tapmix.app"
end
