# YI-Hack-v2 – Anleitung

YI-Hack-v2 basiert auf dem aktuellen Stand von yi-hack-Allwinner-v2 und bringt zusätzlich mehr Zuverlässigkeit, automatische Updates, bessere Sicherheit und fertige Anleitungen für Home Assistant, Frigate und UniFi Protect mit. Die Pakete gibt es unter [Releases](https://github.com/tzureig/YI-Hack-v2/releases).

## 1. Das richtige Paket wählen

Jedes Kameramodell braucht **sein eigenes Paket**. Maßgeblich sind die ersten 4 Buchstaben der Seriennummer (Aufkleber an der Kamera) und die Firmware-Version (in der Yi-App).

| Kamera | Seriennummer | Firmware | Paket |
| --- | --- | --- | --- |
| Yi 1080p Home | BFUS / IFUS / RFUS | 9.0.19* / 12.1.19* | `y21ga_…tgz` |
| Yi 1080p Home | IFUS / QFUS / RFUS | 9.0.36* / 12.0.37* / 12.1.37* | `y211ga_…tgz` |
| Yi 1080p Home | QFUS / RFUS | 9.0.35* / 12.0.35* | `y291ga_…tgz` |
| Yi Outdoor 1080p | IFUS / RFUS | 9.0.26* / 11.1.26* | `h30ga_…tgz` |
| Yi Outdoor 1080p | QFUS | 9.0.45* | `r40ga_…tgz` |
| Yi 1080p Dome / Dome Guard | *FUS / YRS | 9.0.05* / 12.1.05* | `r30gb_…tgz` (Beta) |
| Yi Dome Guard | QFUS / YRS | 9.0.46* / 12.1.47* | `r35gb_…tgz` |
| Yi Dome Guard | YRS / RFUS | 12.1.47* | `r35gb` oder `r37gb` |
| Yi Dome U (Full HD) | BFUS / SFUS | 9.0.22* | `h52ga_…tgz` |
| Yi Dome U (2K) | BFUS / SFUS | 9.0.21* | `h51ga_…tgz` |
| Yi Dome U Pro 2K | LFUS | 9.0.27* | `h60ga_…tgz` |
| Yi Home Y4 | IFCN | 9.0.09* | `y29ga_…tgz` |
| Yi Pro 2K Home | RFUS / YFUS / ZFUS | 12.0.51* | `y623_…tgz` |
| Kami mini home | IFUS | 9.0.20* | `y28ga_…tgz` |
| MIBAO G1 1296p Dome | – | 9.0.04* | `qg311r_…tgz` |
| Blitzwolf BW-YIC1, ESCAM PT202, YS-QC-02, L850Y-US, Tovendor | – | 9.0.41* | `b091qp_…tgz` |

**Niemals ein Paket für ein anderes Modell verwenden oder Dateien umbenennen.**

## 2. Erstinstallation auf die SD-Karte

1. SD-Karte als **FAT32** formatieren (am besten in der Kamera selbst). Alle Dateien entfernen.
2. Das passende `.tgz` entpacken (z. B. mit 7-Zip unter Windows, Doppelklick unter macOS, `tar xzf` unter Linux).
3. Den **Inhalt** in das Hauptverzeichnis der SD-Karte kopieren, so dass es so aussieht:
   ```
   Factory/
   yi-hack/
   lower_half_init.sh   (bzw. die Dateien, die im Paket liegen)
   ```
4. Optional WLAN vorgeben: `Factory/configure_wifi.cfg.ori` in `Factory/configure_wifi.cfg` umbenennen und SSID/Passwort eintragen.
5. Karte einstecken, Kamera neu starten, ca. 1–2 Minuten warten.
6. Im Browser `http://IP-DER-KAMERA` öffnen (IP steht im Router).
7. Die SD-Karte **in der Kamera lassen** – der Hack läuft von der Karte.

## 3. Update von einer bereits gehackten Kamera

Variante A – am einfachsten, Einstellungen bleiben erhalten:
1. Zur Sicherheit unter *Maintenance* → *Save Config* eine Sicherung herunterladen.
2. Das passende Paket **ohne es zu entpacken** in `MODELL_x.x.x.tgz` umbenennen, also z. B. `y21ga_1.0.0.tgz` → `y21ga_x.x.x.tgz`.
3. Die Datei ins Hauptverzeichnis der SD-Karte legen (Karte kurz in den PC stecken oder per FTP/SCP nach `/tmp/sd/`).
4. *Maintenance* öffnen – dort steht „Available: local SD“ – und **Upgrade Firmware** klicken. Die Kamera installiert und startet neu.

Variante B: Karte entnehmen, Ordner `yi-hack` sichern, Paket wie bei der Erstinstallation aufspielen, Kamera starten, danach unter *Maintenance* → *Load Config* die Sicherung wieder einspielen.

Variante C – automatisch: Ist YI-Hack-v2 einmal installiert, sucht die Kamera **jeden Mittag** nach einer neuen Version und installiert sie **nachts** (ab Werk um 03:xx Uhr). Installiert werden nur signierte Releases (Ed25519-Signatur + SHA-256) und nur neuere Versionen, die Einstellungen bleiben erhalten. Mit *Update channel → Beta* bekommt eine Testkamera Pre-Releases zuerst. Einstellbar unter *Configuration → Firmware update*. Der Knopf „Upgrade Firmware“ unter *Maintenance* holt ebenfalls die neueste Version aus diesem Repository.

## 4. Was ist neu?

### Immer erreichbar
* **Watchdog läuft immer** – auch wenn RTSP abgeschaltet ist (vorher lief er nur mit RTSP).
* **Netzwerk-Check:** Alle 30 s wird der Router angepingt. Antwortet er nicht mehr, wird die IP-Konfiguration (DHCP) erneuert; bleibt die Kamera offline, startet sie nach 15 Minuten (einstellbar, 0 = nie) neu. Bei wiederholten Neustarts wird die Wartezeit automatisch länger, damit ein ausgeschalteter Router keine Neustart-Schleife auslöst. Antwortet der Router grundsätzlich nicht auf Ping, passiert nichts.
* **Dienste-Neustart:** Weboberfläche, SSH, ONVIF-Erkennung, mDNS und cron werden bei einem Absturz automatisch neu gestartet.
* **Ethernet-Kameras** werden erkannt: kein unnötiger WLAN-Failsafe-Neustart mehr.
* **WLAN-Energiesparmodus standardmäßig aus** → stabilere Verbindung, niedrigere Latenz.
* **Geplanter Neustart** täglich oder wöchentlich zur gewünschten Uhrzeit.
* Grund des letzten Watchdog-Neustarts wird gespeichert und auf der Statusseite angezeigt.

### Automatische Updates
* Täglicher Check, Installation nachts, Signatur + SHA-256 geprüft, falsches Modell wird abgelehnt, kein Downgrade.
* `AUTO_UPDATE_CHANNEL=stable|beta`: Beta installiert auch Pre-Releases (für eine Testkamera).
* Status auf der Statusseite, Protokoll unter *Maintenance → Logs → Firmware update*.

### Sicherheit
* SSH-Passwort nur noch als SHA-512-Hash gespeichert (alte Klartext-Passwörter werden automatisch umgewandelt), Weboberfläche prüft gegen einen SHA-512-Hash.
* Gespeicherte Passwörter werden nie an den Browser geschickt (Anzeige `********`) und in Logs ausgeblendet.
* Telnet und FTP-Server ab Werk aus, SSH ohne Passwort gesperrt.
* Details: [SICHERHEIT.md](SICHERHEIT.md).

### Snapshots
* Nur noch ein Bild-Decoder gleichzeitig, kurzer Cache (2 s, `SNAPSHOT_CACHE`) und Ersatzbild – keine Abstürze mehr, wenn Home Assistant, Frigate und UniFi gleichzeitig Bilder abholen.

### Kompatibilität
* Haupt- und Substream (RTSP + ONVIF) ab Werk gleichzeitig an, Ton (AAC) an.
* Home Assistant MQTT-Discovery ab Werk aktiv (sobald MQTT eingerichtet ist).
* ONVIF-Erkennung schaltet bei Kabelbetrieb automatisch auf `eth0`.
* Anleitungen: [HOME_ASSISTANT.md](HOME_ASSISTANT.md), [FRIGATE.md](FRIGATE.md), [UNIFI_PROTECT.md](UNIFI_PROTECT.md), [FESTE_IP.md](FESTE_IP.md).

### Neue Funktionen in der Weboberfläche
* *Configuration* → neuer Abschnitt **„Watchdog & Reachability“** mit allen Optionen.
* *Status* → neue Abschnitte: Dienste (läuft/gestoppt), Swap, SD-Belegung, Temperatur (wenn verfügbar), Verbindungsart, WLAN-Signal in dBm, letztes Watchdog-Ereignis.
* *Maintenance* → **Log-Anzeige** (Watchdog, WLAN-Failsafe, Boot-Log, Kernel, Prozesse/Speicher).
* **Health-Check** für Uptime Kuma / Home Assistant: `http://IP-DER-KAMERA/cgi-bin/health.sh` (HTTP 200 = ok, 503 = gestört).

### Fehlerbehebungen
* Das Feld „Syslog server“ wurde beim Öffnen der Einstellungen nicht geladen und beim Speichern gelöscht – behoben (alle Felder werden jetzt generisch geladen/gespeichert).
* Statische IP bei Ethernet wurde fälschlich auf `wlan0` gesetzt – jetzt `eth0`.
* Das Stoppen von RTSP beendete den kompletten Watchdog (inkl. WLAN-Überwachung) – jetzt wird nur die RTSP-Prüfung pausiert.

## 5. Empfohlene Einstellungen

* *Configuration → Authentication*: Benutzername und Passwort setzen.
* *Configuration → Watchdog & Reachability*: alles an lassen; „Scheduled reboot“ auf *Every day* / 04:00, wenn die Kamera nach einigen Tagen träge wird.
* *Swap File* an lassen (die Kameras haben sehr wenig RAM).
* SSH-Passwort setzen (sonst ist SSH nur mit Schlüssel möglich).
* Feste IP vergeben: [FESTE_IP.md](FESTE_IP.md).
