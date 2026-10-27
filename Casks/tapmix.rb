cask "tapmix" do
  version "0.3.2"
  sha256 "5eac0a1516fc207157198a4b465dda27671725d23e1bd9dff0436aff493f8655"

  url "https://github.com/Sakuleta/tapmix/releases/download/v#{version}/Tapmix-#{version}.zip"
  name "Tapmix"
  desc "Per-app volume mixer for macOS"
  homepage "https://github.com/Sakuleta/tapmix"

  depends_on macos: ">= :sequoia"
  app "Tapmix.app"
end
