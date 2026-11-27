# Neue Version veröffentlichen

Die Kameras laden Updates aus den **Releases** dieses Repositorys (`AUTO_UPDATE_REPO`, ab Werk `tzureig/YI-Hack-v2`).

> **Wichtig:** Die Kameras laden Releases ohne GitHub-Login. Das Repository muss deshalb **öffentlich** sein, sonst schlägt das Auto-Update fehl.

## Release erstellen

Variante A – im Browser: *Actions → Release → Run workflow* → Version eintragen (z. B. `1.0.1`) → *Run*.

Variante B – per Git:

```sh
git tag 1.0.1
git push origin 1.0.1
```

GitHub Actions baut dann die Firmware für **alle** Modelle (ca. 10–15 Minuten), erzeugt `SHA256SUMS.txt`, **signiert** sie (`SHA256SUMS.txt.sig`, Secret `FW_SIGN_KEY`), prüft jedes Paket und veröffentlicht alles als Release. In der folgenden Nacht installieren alle Kameras mit `AUTO_UPDATE=yes` die neue Version.

**Erst testen:** Bei *Run workflow* „Pre-release“ anhaken (oder eine Version mit Bindestrich wie `1.0.2-beta1`). Dann installieren nur Kameras mit *Update channel = Beta*. Läuft die Testkamera einen Tag stabil, das Release auf GitHub als „Latest“ markieren (oder neu ohne Pre-release veröffentlichen) – dann folgen alle anderen.

### Signaturschlüssel

* Öffentlich: `src/fwverify/fw_sign.pub` (32 Byte Ed25519, hex) – wird in `bin/fwverify` einkompiliert.
* Privat: GitHub-Secret `FW_SIGN_KEY` (PEM). Ohne Secret bricht der Release-Workflow ab.
* Neuer Schlüssel: `openssl genpkey -algorithm ed25519 -out key.pem`, öffentlichen Teil mit `openssl pkey -in key.pem -pubout -outform DER | tail -c 32 | xxd -p -c 64 > src/fwverify/fw_sign.pub`, Secret neu setzen. Kameras mit dem alten Schlüssel einmal von Hand aktualisieren.

Versionsnamen nur aus Buchstaben, Ziffern, `.` `-` `_` `+`. Jede neue Version braucht einen neuen Namen.

## Änderungen vom Original übernehmen

Der Workflow **Upstream sync** prüft jeden Montag, ob es im Original-Projekt (roleoroleo/yi-hack-Allwinner-v2) Neues gibt, und öffnet dann automatisch einen Pull Request und startet den Build für diesen Branch (*Actions → Build*, Branch `upstream-sync`). Zusammenführen → Release erstellen → Kameras aktualisieren sich nachts.

## Lokal bauen

```sh
git clone --recursive https://github.com/tzureig/YI-Hack-v2
cd YI-Hack-v2
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
