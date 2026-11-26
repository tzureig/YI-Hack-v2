# Neue Version veröffentlichen

Die Kameras laden Updates aus den **Releases** dieses Repositorys (`AUTO_UPDATE_REPO`, ab Werk `tzureig/YI-Hack-Tiz`).

> **Wichtig:** Die Kameras laden Releases ohne GitHub-Login. Das Repository muss deshalb **öffentlich** sein, sonst schlägt das Auto-Update fehl.

## Release erstellen

Variante A – im Browser: *Actions → Release → Run workflow* → Version eintragen (z. B. `1.0.1`) → *Run*.

Variante B – per Git:

```sh
git tag 1.0.1
git push origin 1.0.1
```

GitHub Actions baut dann die Firmware für **alle** Modelle (ca. 30–40 Minuten), erzeugt `SHA256SUMS.txt` und veröffentlicht alles als Release. In der folgenden Nacht installieren alle Kameras mit `AUTO_UPDATE=yes` die neue Version.

Versionsnamen nur aus Buchstaben, Ziffern, `.` `-` `_` `+`. Jede neue Version braucht einen neuen Namen.

## Änderungen vom Original übernehmen

Der Workflow **Upstream sync** prüft jeden Montag, ob es im Original-Projekt (roleoroleo/yi-hack-Allwinner-v2) Neues gibt, und öffnet dann automatisch einen Pull Request. Der Build-Workflow testet ihn. Zusammenführen → Release erstellen → Kameras aktualisieren sich nachts.

## Lokal bauen

```sh
git clone --recursive https://github.com/tzureig/YI-Hack-Tiz
cd YI-Hack-Tiz
# Toolchain (einmalig)
git clone --depth 1 --filter=blob:none --sparse https://github.com/lindenis-org/lindenis-v536-prebuilt
git -C lindenis-v536-prebuilt sparse-checkout set gcc/linux-x86/arm/toolchain-sunxi-musl/toolchain
sudo mkdir -p /opt/yi/toolchain-sunxi-musl
sudo cp -r lindenis-v536-prebuilt/gcc/linux-x86/arm/toolchain-sunxi-musl/toolchain /opt/yi/toolchain-sunxi-musl/
# Bauen und packen
./scripts/compile.sh
sudo ./scripts/pack_fw.all.sh     # Pakete in out/all/
```

Benötigte Pakete: siehe `.github/workflows/build.yaml` (Debian/Ubuntu).
