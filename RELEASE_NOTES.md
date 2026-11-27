## YI-Hack-v2

Für jedes Kameramodell gibt es ein eigenes Paket `MODELL_VERSION.tgz` (Modelltabelle: [docs/ANLEITUNG_DE.md](https://github.com/tzureig/YI-Hack-v2/blob/main/docs/ANLEITUNG_DE.md)).

* **Neuinstallation:** SD-Karte FAT32, Paket entpacken, Inhalt auf die Karte, Kamera neu starten.
* **Von 1.0.1, 1.0.2 oder 1.0.3:** siehe „Neu in 1.1.1“ (eine Zeile unter *Crontab*), dann *Maintenance → Upgrade Firmware*.
* **Von yi-hack 0.3.x oder 1.0.0:** Paket als `MODELL_x.x.x.tgz` ins Hauptverzeichnis der SD legen (z. B. `y211ga_x.x.x.tgz`), dann *Maintenance → Upgrade Firmware*.
* **Prüfsummen:** `SHA256SUMS.txt`, Signatur `SHA256SUMS.txt.sig` (Ed25519)

### Neu in 1.1.1
* **Ursache von „No package for this model“:** Die Paketsuche des alten Updaters (`grep | awk | head -n1`) liefert auf der Kamera nichts, vermutlich fehlt `head`. Der Updater bis 1.0.3 brauchte ihn, um das Paket in `SHA256SUMS.txt` zu finden. Ab 1.1 kommt er ohne `head` aus. Auch Statusseite („Last reboot“) und eindeutige MQTT-Namen nutzten `head`, das ist behoben. Der Release-Build prüft das jetzt.
* **Von 1.0.x aktualisieren (getestet auf y211ga):** Der Knopf *Upgrade Firmware* nutzt noch den alten Updater und scheitert. Stattdessen einmal unter *Configuration → Crontab* diese Zeile eintragen, *Save Configuration*, dann *Maintenance → Reboot* und 5 Minuten warten, **ohne** auf Check/Upgrade zu klicken. Die Kamera lädt den neuen Updater (SHA-256 geprüft) und installiert selbst. Danach die Zeile wieder löschen:
  `* * * * * [ -f /tmp/au_once ] || (touch /tmp/au_once; cd /tmp; /tmp/sd/yi-hack/usr/bin/wget -q -T 60 -O /tmp/au.sh https://raw.githubusercontent.com/tzureig/YI-Hack-v2/1.1/src/static/static/yi-hack/script/auto_update.sh && /tmp/sd/yi-hack/usr/bin/sha256sum /tmp/au.sh | grep -q ae1642f9286ca6eb76c8d2dda1ad76c0e8cecb527590b9167cd27ae0aa6b36ed && sh /tmp/au.sh install || echo "Neuer Updater konnte nicht geladen werden" >> /tmp/sd/yi-hack/etc/auto_update.log)`

### Neu in 1.1
* **Update-Problem behoben:** Kameras mit 1.0.1 bis 1.0.3 meldeten beim Online-Update „No package for this model“, weil das `grep` der Kamera den Paketnamen in `SHA256SUMS.txt` nicht fand. Ab 1.1 enthält die signierte `SHA256SUMS.txt` zusätzlich Zeilen, die auch der alte Updater findet. Der neue Updater liest den Paketnamen ohne `grep`.
* **SSH-Passwort wirkt sofort:** In 1.0.x lehnte SSH ein in der Weboberfläche gesetztes Passwort bis zum nächsten Neustart ab.
* **Neue Weboberfläche:** modernes Kartenlayout in Hell und Dunkel, aktive Seite im Menü markiert.
* **Neue Seite „Smart Home“:** Live-Vorschau, Status (Online, Streams, ONVIF, MQTT, Passwort) und fertige Konfiguration zum Kopieren mit den echten Adressen der Kamera für **Home Assistant** (ONVIF, go2rtc, MQTT-Automation, Verfügbarkeits-Sensor, Dashboard-Karte), **Frigate**, **Scrypted** und **UniFi Protect**.
* **Live-Ansicht bleibt nicht mehr schwarz:** Startet das Video nicht innerhalb von 12 s, zeigt sie laufend Standbilder. Die gewählte Auflösung wird gemerkt.
* **Mehrere Kameras in Home Assistant:** eindeutige MQTT-Client-ID, Topic-Präfix und Geräte-ID pro Kamera (aus der MAC-Adresse), Gerätename = Hostname. Wird einmalig gesetzt, solange MQTT noch nicht benutzt wird.
* Haupt- und Substream werden beim Update eingeschaltet (für Frigate-Erkennung und HA-Kacheln).
* Projekt heißt jetzt neutral **YI-Hack-v2**. Eine alte Update-Quelle (`…/YI-Hack-Tiz`) wird beim Update automatisch auf `tzureig/YI-Hack-v2` umgestellt.

### Neu in 1.0.3
* Update-Erkennung liest den Paketnamen aus dem letzten Feld von `SHA256SUMS.txt`.

### Neu in 1.0.1
* Updates nur noch mit Ed25519-Signatur (eigener kleiner Prüfer `fwverify`), nie ein Downgrade, Beta-Kanal für eine Testkamera.
* „Upgrade Firmware“ in der Weboberfläche nutzt dieselbe geprüfte Logik; ein von Hand auf die SD gelegtes Paket wird auf das Modell geprüft.
* **Aufnahme bei Personen:** ab Werk (und einmalig beim Update) nimmt die Kamera auf die SD auf, sobald sie eine Person erkennt (KI-Personenerkennung, Aufnahme ohne Cloud). Bei weniger als 10 % freiem Platz werden die ältesten Aufnahmen gelöscht. Änderbar unter *Camera settings*.
* Snapshot: kein eingefrorenes Bild mehr, wenn der Decoder ausfällt (nach 30 s Ersatzbild).
* Build: Quellarchive werden mit Prüfsumme und Ersatz-Download geladen (zlib.net-Fehler behoben).
* Release prüft jedes Paket (Version, Modell, Upgrade-Marker, fwverify).

Änderungen: siehe [Commits](https://github.com/tzureig/YI-Hack-v2/commits/main).
