cask "mischpult" do
  version "1.4.0"
  sha256 "b57437529cc51ac01e07e912f8ac1466d5cc427c9423c6808e5d1d304e839b44"

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
