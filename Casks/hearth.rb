cask "hearth" do
  version "1.0.0"
  sha256 "28d5bccb8b5ca62ea57baafa063865568406790b7282e9427a3508e18d259278"

  url "https://github.com/PriyanshuGeTRekT/hearth-simple-mac-for-seniors/releases/download/v#{version}/Hearth-#{version}.zip"
  name "Hearth"
  desc "Simple big-button home screen for older adults, set up by a caregiver"
  homepage "https://priyanshugetrekt.github.io/hearth-simple-mac-for-seniors/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: ">= :sonoma"

  app "Hearth.app"

  zap trash: [
    "~/Library/Application Support/Hearth",
    "~/Library/Preferences/app.hearth.mac.plist",
  ]

  caveats <<~EOS
    Hearth is not notarized by Apple, so macOS blocks it the first time it opens.
    To allow it, open Hearth once, then go to
      System Settings › Privacy & Security
    scroll down and click "Open Anyway" next to Hearth.

    The first launch opens the caregiver setup. Add people, buttons and reminders,
    set a PIN, then press Finish setup.
  EOS
end
