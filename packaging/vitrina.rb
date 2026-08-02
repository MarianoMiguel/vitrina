# Homebrew cask for Vitrina.
#
# This file is the template that will live in the tap repository
# (MarianoMiguel/homebrew-tap as Casks/vitrina.rb) once the first signed
# release artifact exists. Until then `brew install marianomiguel/tap/vitrina`
# is not yet live: the sha256 below must be filled from the released zip, and
# the release workflow keeps both in sync.
cask "vitrina" do
  version "0.1.0"
  sha256 "REPLACE_WITH_RELEASE_ZIP_SHA256"

  url "https://github.com/MarianoMiguel/vitrina/releases/download/v#{version}/Vitrina-#{version}.zip"
  name "Vitrina"
  desc "Dynamic screen sharing target for macOS - share one stable virtual display, switch what it shows"
  homepage "https://github.com/MarianoMiguel/vitrina"

  depends_on macos: ">= :sonoma"

  app "Vitrina.app"

  zap trash: [
    "~/Library/Logs/Vitrina",
    "~/Library/Preferences/computer.interstellar.vitrina.plist",
  ]
end
