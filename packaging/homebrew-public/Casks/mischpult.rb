cask "mischpult" do
  version "1.2.3"
  sha256 "8fc7f3bef88b9e4d7979a6e7a3c8477f6370f73f6c474439ab2f1773848f28ea"

  url "https://github.com/Cramleo234/mischpult/releases/download/v#{version}/Mischpult-#{version}.dmg"
  name "Mischpult"
  desc "Lautstärke, Ausgabegerät und Equalizer pro App – ein Hobbyprojekt"
  homepage "https://github.com/Cramleo234/mischpult"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Mischpult.app"

  uninstall quit: "local.private.mischpult"

  zap trash: [
    "~/Library/Preferences/local.private.mischpult.plist",
  ]

  caveats <<~EOS
    Mischpult sitzt in der Menüleiste (Symbol mit drei Schiebereglern) und
    braucht macOS 14.2 oder neuer.

    Mischpult ist nicht von Apple notarisiert. Beim ersten Start unter
    Systemeinstellungen → Datenschutz & Sicherheit auf „Trotzdem öffnen“ klicken.

    Beim ersten Verstellen eines Reglers fragt macOS nach der Erlaubnis
    „Systemaudio aufnehmen“ – bitte erlauben.
  EOS
end
