cask "mischpult" do
  version "1.2.2"
  sha256 "c64909214e47aa436e7f772196725c2ed32e9a8e12ed6a123839113969059672"

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
