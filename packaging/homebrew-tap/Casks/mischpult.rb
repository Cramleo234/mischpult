# Kopie der aktuellen Cask im privaten Tap.
cask "mischpult" do
  version "1.0.0"
  sha256 "2c88a6621efb12822f53d6b1466091b437dae2334765950cc3642fed4caba6db"

  # Privates Release: Token nur aus der Umgebung, niemals im Repository.
  url "https://api.github.com/repos/Cramleo234/mischpult/releases/assets/643773802",
      header: [
        "Authorization: Bearer #{ENV.fetch("HOMEBREW_GITHUB_API_TOKEN", "")}",
        "Accept: application/octet-stream",
      ]
  name "Mischpult"
  desc "Lautstärke, Ausgabegerät und Equalizer pro App – private SoundSource-Alternative"
  homepage "https://github.com/Cramleo234/mischpult"

  depends_on macos: :sonoma

  app "Mischpult.app"

  uninstall quit: "local.private.mischpult"

  zap trash: [
    "~/Library/Preferences/local.private.mischpult.plist",
  ]

  caveats <<~EOS
    Mischpult liegt in einem privaten Repo. Einmalig pro Mac im Terminal einrichten:
      brew install gh
      gh auth login
      gh auth setup-git
      echo 'export HOMEBREW_GITHUB_API_TOKEN="$(gh auth token 2>/dev/null)"' >> ~/.zshrc
      source ~/.zshrc

    Installation (Homebrew 6 oder neuer: privaten Tap freigeben):
      brew tap Cramleo234/tap
      brew trust Cramleo234/tap
      brew install --cask cramleo234/tap/mischpult

    Mischpult sitzt in der Menüleiste (Symbol mit drei Schiebereglern) und
    braucht macOS 14.2 oder neuer. Beim ersten Verstellen eines Reglers fragt
    macOS nach der Erlaubnis „Systemaudio aufnehmen“ – bitte erlauben.

    Mischpult ist nicht notarisiert. Beim ersten Start gegebenenfalls:
    Rechtsklick auf Mischpult → „Öffnen“.

    Aktualisieren:
      brew update && brew upgrade --cask cramleo234/tap/mischpult
  EOS
end
