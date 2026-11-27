## YI-Hack-Tiz

Für jedes Kameramodell gibt es ein eigenes Paket `MODELL_VERSION.tgz` (Modelltabelle: [docs/ANLEITUNG_DE.md](https://github.com/tzureig/YI-Hack-Tiz/blob/main/docs/ANLEITUNG_DE.md)).

* **Neuinstallation:** SD-Karte FAT32, Paket entpacken, Inhalt auf die Karte, Kamera neu starten.
* **Von yi-hack 0.3.x oder YI-Hack-Tiz 1.0.0:** Paket als `MODELL_x.x.x.tgz` ins Hauptverzeichnis der SD legen (z. B. `y28ga_x.x.x.tgz`), dann *Maintenance → Upgrade Firmware*.
* **Ab 1.0.1:** Updates kommen automatisch nachts, nur signiert.
* **Prüfsummen:** `SHA256SUMS.txt`, Signatur `SHA256SUMS.txt.sig` (Ed25519)

### Neu in 1.0.2
* **Neue Weboberfläche:** modernes Kartenlayout in Hell und Dunkel, aktive Seite im Menü markiert.
* **Neue Seite „Home Assistant“:** Live-Vorschau, Status (Online, Streams, ONVIF, MQTT, Passwort) und fertige Konfiguration zum Kopieren mit den echten Adressen der Kamera: ONVIF, go2rtc, MQTT-Automation, Verfügbarkeits-Sensor, Frigate, Dashboard-Karte.
* **Live-Ansicht bleibt nicht mehr schwarz:** Startet das Video nicht innerhalb von 12 s (Browser oder WLAN zu langsam), zeigt sie automatisch laufend Standbilder. Die gewählte Auflösung wird gemerkt.
* **Mehrere Kameras in Home Assistant:** eindeutige MQTT-Client-ID, eindeutiges Topic-Präfix und eindeutige Geräte-ID pro Kamera (aus der MAC-Adresse), Gerätename = Hostname. Wird einmalig gesetzt, solange MQTT noch nicht benutzt wird.
* Haupt- und Substream werden beim Update eingeschaltet (für Frigate-Erkennung und HA-Kacheln).

### Neu in 1.0.1
* Updates nur noch mit Ed25519-Signatur (eigener kleiner Prüfer `fwverify`), nie ein Downgrade, Beta-Kanal für eine Testkamera.
* „Upgrade Firmware“ in der Weboberfläche nutzt dieselbe geprüfte Logik; ein von Hand auf die SD gelegtes Paket wird auf das Modell geprüft.
* **Aufnahme bei Personen:** ab Werk (und einmalig beim Update) nimmt die Kamera auf die SD auf, sobald sie eine Person erkennt (KI-Personenerkennung, Aufnahme ohne Cloud). Bei weniger als 10 % freiem Platz werden die ältesten Aufnahmen gelöscht. Änderbar unter *Camera settings*.
* Snapshot: kein eingefrorenes Bild mehr, wenn der Decoder ausfällt (nach 30 s Ersatzbild).
* Build: Quellarchive werden mit Prüfsumme und Ersatz-Download geladen (zlib.net-Fehler behoben).
* Release prüft jedes Paket (Version, Modell, Upgrade-Marker, fwverify).

Änderungen: siehe [Commits](https://github.com/tzureig/YI-Hack-Tiz/commits/main).
