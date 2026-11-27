## YI-Hack-Tiz

Für jedes Kameramodell gibt es ein eigenes Paket `MODELL_VERSION.tgz` (Modelltabelle: [docs/ANLEITUNG_DE.md](https://github.com/tzureig/YI-Hack-Tiz/blob/main/docs/ANLEITUNG_DE.md)).

* **Neuinstallation:** SD-Karte FAT32, Paket entpacken, Inhalt auf die Karte, Kamera neu starten.
* **Von yi-hack 0.3.x oder YI-Hack-Tiz 1.0.0:** Paket als `MODELL_x.x.x.tgz` ins Hauptverzeichnis der SD legen (z. B. `y28ga_x.x.x.tgz`), dann *Maintenance → Upgrade Firmware*.
* **Ab 1.0.1:** Updates kommen automatisch nachts, nur signiert.
* **Prüfsummen:** `SHA256SUMS.txt`, Signatur `SHA256SUMS.txt.sig` (Ed25519)

### Neu in 1.0.1
* Updates nur noch mit Ed25519-Signatur (eigener kleiner Prüfer `fwverify`), nie ein Downgrade, Beta-Kanal für eine Testkamera.
* „Upgrade Firmware“ in der Weboberfläche nutzt dieselbe geprüfte Logik; ein von Hand auf die SD gelegtes Paket wird auf das Modell geprüft.
* Snapshot: kein eingefrorenes Bild mehr, wenn der Decoder ausfällt (nach 30 s Ersatzbild).
* Build: Quellarchive werden mit Prüfsumme und Ersatz-Download geladen (zlib.net-Fehler behoben).
* Release prüft jedes Paket (Version, Modell, Upgrade-Marker, fwverify).

Änderungen: siehe [Commits](https://github.com/tzureig/YI-Hack-Tiz/commits/main).
