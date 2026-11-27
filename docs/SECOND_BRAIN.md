---
title: YI-Hack-v2 – Second Brain
tags: [yi-hack, kamera, firmware, home-assistant, frigate, unifi, smarthome]
status: aktiv
erstellt: 2026-11-26
aktualisiert: 2026-11-27
repo: https://github.com/tzureig/YI-Hack-v2
---

# YI-Hack-v2 – Second Brain

> Alles, was man über dieses Projekt wissen muss, an einem Ort: was es ist, wie es aufgebaut ist, welche Entscheidungen warum getroffen wurden, wo welche Datei liegt und wie man weitermacht.

## 1. Worum geht es?

* **Ziel:** Yi-Kameras (Allwinner-Chip) mit einer eigenen Firmware von der SD-Karte betreiben: immer erreichbar, sicher, automatisch aktuell, kompatibel mit **Home Assistant**, **Frigate** und **UniFi Protect**; dazu **Personen-/Tiererkennung mit farbigen Rahmen** (Person blau, Hund grün, auch ohne Bewegung).
* **Basis:** Fork von [roleoroleo/yi-hack-Allwinner-v2](https://github.com/roleoroleo/yi-hack-Allwinner-v2) inklusive der vollen Git-Historie, damit der wöchentliche Abgleich mit dem Original sauber zusammenführen kann.
* **Repo:** `tzureig/YI-Hack-v2`, Branch `main`. Releases = Firmware-Pakete pro Modell.

## 2. Architektur auf einen Blick

```
                 ┌──────────────── Kamera (SD-Karte: /tmp/sd/yi-hack) ────────────────┐
 Yi-Firmware ──► │ system.sh (Boot) ─► rmm/mp4record (Yi)  ─► Ringpuffer /dev/shm      │
                 │                    ├─ rRTSPServer / go2rtc ─► RTSP ch0_0/ch0_1/ch0_2│──► HA / Frigate / UniFi
                 │                    ├─ httpd (Web-UI, CGI, ONVIF) ─► :80             │──► Browser, ONVIF
                 │                    ├─ mqttv4 (Ereignisse) ─► MQTT-Broker            │──► Home Assistant
                 │                    ├─ wd.sh (Watchdog, alle 10 s)                   │
                 │                    └─ crond: auto_update.sh, Neustart, Aufräumen    │
                 └────────────────────────────────────────────────────────────────────┘
                                         │ RTSP-Substream / Snapshot
                                         ▼
                 ┌──────── Server / Home Assistant ────────┐
                 │ yi-detector (Docker / HA-Add-on)         │──► MJPEG + Bild mit Rahmen
                 │ YOLOv8n ONNX, jedes Bild komplett        │──► MQTT: Person/Hund an/aus
                 └──────────────────────────────────────────┘
 GitHub Actions: build.yaml (Test) · release.yaml (Pakete + SHA256SUMS) · upstream-sync.yaml (wöchentl. PR) · detector-image.yaml (ghcr)
```

## 3. Wo liegt was?

| Bereich | Pfad im Repo | Auf der Kamera |
| --- | --- | --- |
| Boot-Ablauf | `src/static/static/yi-hack/script/system.sh` | `/tmp/sd/yi-hack/script/system.sh` |
| Dienste starten/stoppen | `src/static/static/yi-hack/script/service.sh` | `… service.sh rtsp|onvif|httpd|sshd|wd start` |
| Watchdog | `src/static/static/yi-hack/script/wd.sh` | Log: `/tmp/wd.log` (RAM) |
| Auto-Update | `src/static/static/yi-hack/script/auto_update.sh` (check/prepare/install) | Status `etc/auto_update.status`, Log `etc/auto_update.log` |
| Signaturprüfung | `src/fwverify/` (TweetNaCl, Schlüssel `fw_sign.pub`) | `/tmp/sd/yi-hack/bin/fwverify` |
| Sichere Downloads beim Bau | `scripts/fetch.sh` | – |
| Standardwerte / Migration | `src/static/static/yi-hack/etc/system.conf`, `script/check_conf.sh` | `etc/system.conf` |
| Web-Oberfläche | `src/www/httpd/htdocs/` (HTML/JS), `src/www/httpd/cgi-bin/` | `/tmp/sd/yi-hack/www/` |
| Webserver-Passwort-Hash | `src/busybox/auth_hash.patch`, `.config` (`FEATURE_HTTPD_AUTH_MD5`) | `/tmp/httpd.conf` |
| Snapshots | `src/www/httpd/cgi-bin/snapshot.sh` | Cache `/tmp/snapshot_*.jpg` |
| Pakete bauen | `scripts/compile.sh`, `scripts/pack_fw.sh` | – |
| Erkennung | `detector/` (Python, Docker), `ha-addon/yi-detector/` | läuft **nicht** auf der Kamera |
| Doku | `docs/*.md`, `README.md` | – |

## 4. Wichtige Entscheidungen (und warum)

| Entscheidung | Grund |
| --- | --- |
| Watchdog läuft **unabhängig von RTSP** | Vorher endete er, wenn RTSP aus war → keine WLAN-Überwachung mehr. |
| Netzwerk-Check per **Ping zum Router**, reagiert nur, wenn der Router früher schon geantwortet hat | WLAN kann „verbunden“ melden und trotzdem tot sein; manche Router antworten nie auf Ping → so gibt es keine falschen Neustarts. |
| Neustart nach `WD_NET_REBOOT_MIN` (15 min) mit **wachsender Wartezeit** (×1 … ×8) | Ein ausgeschalteter Router darf keine Neustart-Schleife auslösen. |
| WLAN-Energiesparen ab Werk **aus** | Bekannte Ursache für Aussetzer und hohe Latenz. |
| SSH-Passwort **nur als SHA-512-Hash** | Wird nur zur Prüfung gebraucht. |
| Kamera-Login (RTSP/ONVIF) bleibt **im Klartext auf der SD** | RTSP-Digest und ONVIF-WS-Security brauchen das Passwort selbst. Ohne würden HA, Frigate und UniFi nicht funktionieren. Ausgleich: wird nie an den Browser geschickt, nie geloggt, der Webserver bekommt nur einen Hash. |
| `********` als Platzhalter in der Weboberfläche | Passwörter verlassen die Kamera nicht. Wer das Feld unverändert lässt, behält den gespeicherten Wert. |
| Updates nur mit **Ed25519-signierter** `SHA256SUMS.txt` + SHA-256 + Modellprüfung, nie Downgrade | BusyBox-`wget` prüft keine TLS-Zertifikate: Nur die Signatur schützt gegen manipulierte Downloads. Privater Schlüssel nur im Secret `FW_SIGN_KEY`. |
| Beta-Kanal über GitHub-Pre-Releases | Neue Versionen erst auf einer Testkamera, `releases/latest` überspringt Pre-Releases. |
| Updates **nachts**, Check **mittags**, Minute aus der MAC-Adresse | Kein Ausfall tagsüber; mehrere Kameras fragen GitHub nicht gleichzeitig an. |
| Snapshot: **ein** Decoder, Cache 2 s, Ersatzbild | Mehrere gleichzeitige Decoder füllten den RAM → Neustarts. |
| Haupt- + Substream ab Werk an | Frigate (Erkennung auf Sub), UniFi (Vorschau), HA (Kacheln) brauchen beide. |
| Erkennung **auf dem Server**, nicht auf der Kamera | ~64 MB RAM, schwache CPU, kein Zugriff auf den Video-Encoder für Overlays. Die eingebaute Yi-KI reagiert nur auf Bewegung und liefert keine Rahmen. |
| yi-detector prüft **jedes Bild komplett** | Nur so werden stillstehende Personen/Tiere erkannt (Frigate sucht vor allem in bewegten Bereichen). |
| Tags werden vom **Release-Workflow** gesetzt | Die Claude-Code-Sitzung darf keine Tags pushen; ein Release startet man daher per *Actions → Release → Run workflow*. |

## 5. Betrieb – Spickzettel

* **Weboberfläche:** `http://KAMERA-IP` → Status (Dienste, Update, Watchdog), Configuration (Watchdog, Firmware update, Authentication), Maintenance (Logs).
* **Health:** `http://KAMERA-IP/cgi-bin/health.sh` → 200 ok / 503 gestört.
* **Streams:** `rtsp://USER:PASS@IP/ch0_0.h264` (Haupt), `ch0_1` (Sub), `ch0_2` (nur Ton).
* **Erkennung:** `http://SERVER:8090/` (alle Kameras mit Rahmen).
* **Neues Release:** GitHub → *Actions → Release → Run workflow* → Version (z. B. `1.0.1`). Kameras installieren es in der folgenden Nacht.
* **Original-Updates übernehmen:** Montags kommt automatisch ein PR „Upstream: …“ → Build grün → mergen → Release.
* **Update von 1.0.2 bei „No package for this model“:** Der alte 1.0.2-Updater kann 1.0.3 wegen der früheren Manifest-Suche nicht finden; der Fix in 1.0.3 greift erst nach Installation. Release 1.0.3 enthält den Parser-Fix. Falls die alte Firmware das Paket online nicht findet, das Modellpaket aus [Release 1.0.3](https://github.com/tzureig/YI-Hack-v2/releases/tag/1.0.3) laden (z. B. `y211ga_1.0.3.tgz`), in `y211ga_x.x.x.tgz` umbenennen, ins Hauptverzeichnis der SD-Karte legen und unter *Maintenance → Upgrade Firmware* als lokales SD-Update installieren. Die Einstellungen bleiben erhalten.
* **Kamera hängt?** Logs: *Maintenance → Logs → Watchdog*. Letzter Neustart-Grund steht auf der Statusseite.

## 6. Konfigurationsschlüssel (neu in YI-Hack-v2)

| Schlüssel | Standard | Bedeutung |
| --- | --- | --- |
| `WATCHDOG` | yes | Watchdog an/aus |
| `WD_SERVICES` | yes | abgestürzte Dienste neu starten |
| `WD_NET_CHECK` | yes | Router-Ping |
| `WD_PING_HOST` | (leer = Gateway) | Ping-Ziel |
| `WD_NET_REBOOT_MIN` | 15 | Minuten offline bis Neustart (0 = nie) |
| `WD_LOG` | yes | Watchdog-Log im RAM |
| `REBOOT_SCHEDULE` / `REBOOT_HOUR` | no / 4 | geplanter Neustart (daily/weekly) |
| `AUTO_UPDATE` | yes | yes = nachts installieren, check = nur prüfen, no = aus |
| `AUTO_UPDATE_HOUR` | 3 | Installationsstunde |
| `AUTO_UPDATE_REPO` | tzureig/YI-Hack-v2 | Quelle der Releases |
| `AUTO_UPDATE_CHANNEL` | stable | beta = auch Pre-Releases (Testkamera) |
| `SNAPSHOT_CACHE` | 2 | Sekunden Snapshot-Cache |
| `SSH_PASSWORD_HASH` | – | SHA-512-Hash (wird automatisch gesetzt) |
| geändert: `TELNETD`, `FTPD` | no | ab Werk aus |
| geändert: `WIFI_POWERSAVE` | no | ab Werk aus |
| geändert: `RTSP_STREAM`, `ONVIF_PROFILE` | both | beide Streams |

## 7. Getestet

* Kompletter Bau aller 20 Modell-Pakete (Toolchain sunxi-musl gcc 6.4) und Release-Workflow auf GitHub Actions.
* BusyBox-ARM-Binary unter QEMU: `sha256sum`, `mkpasswd -m sha512`, **httpd mit SHA-512-Hash** (falsch → 401, richtig → 200, ONVIF-Pfad bleibt offen).
* Watchdog in nachgebauter Kamera-Umgebung: Dienste-Neustart, Netzwerkausfall → DHCP → Neustart mit Grund, rmm-Ausfall.
* Auto-Update: echtes Paket → Prüfsumme ok → Installation vorbereitet; manipuliertes Paket → abgelehnt.
* Snapshot: 5 gleichzeitige Abrufe → 1 Decoder; Decoder-Fehler → Ersatzbild.
* Passwort-Speicherung: Hash verifiziert, `********` behält den Wert, Browser sieht keine Passwörter.
* yi-detector: Person 92 % (blau), Hund 89–93 % (grün, auch sitzend/still), Pferd (orange); RTSP- und Snapshot-Quelle, MJPEG, JSON, MQTT-Discovery.
* Fertig gebaute Weboberfläche (gzip/minifiziert aus dem 1.0.0-Paket) im Browser (Playwright) gegen simulierte Kamera: Statusseite (Dienste, Swap, dBm, Update-Status), Einstellungen (alle Felder laden, Syslog bleibt erhalten, Passwort geht nur als `********` zurück, Speichern ok), Log-Ansicht – **keine JavaScript-Fehler**.
* Release 1.0.0 von GitHub geladen und wie die Kamera geprüft: SHA-256 ok, 20 Modelle, Version/Modell im Paket korrekt.
* GitHub Actions: Build ✅, Release ✅ (nach Fix der Dateirechte), Detector-Image ✅ (nach Fix fehlender GL-Bibliotheken im Export-Schritt).
* **Noch nicht** auf echter Kamera-Hardware getestet → erst mit einer Kamera ausprobieren.

## 8. Offene Ideen / nächste Schritte

* [ ] **Second Brain auf dem MacBook:** Diese Datei ist die Quelle. Für die Übernahme in die lokale Notiz-Sammlung (z. B. Obsidian) muss der Ordner in der Claude-Desktop-App freigegeben werden (*Einstellungen → Claude Code → Remote Control*), dann kann Claude den Eintrag dort anlegen – oder die Datei einfach in den Vault kopieren (das Frontmatter ist Obsidian-kompatibel).
* [ ] **Repo ist privat** → Kameras (ohne GitHub-Login) können Releases nicht laden; Auto-Update und „Upgrade Firmware“ funktionieren erst, wenn das Repo öffentlich ist (*Settings → General → Danger Zone → Change visibility*). Alternativ `AUTO_UPDATE_REPO` auf ein öffentliches Repo stellen.
* [ ] Erste echte Kamera mit 1.0.0 flashen und 24 h beobachten (Watchdog-Log, Update-Status).
* [ ] GHCR-Paket `yi-detector` in GitHub auf **public** stellen (für das HA-Add-on nötig).
* [ ] Optional: Zonen/Masken im yi-detector (nur Garten, nicht Straße).
* [ ] Optional: Rollback-Paket für Updates auf der SD aufbewahren.
* [ ] GitHub-Secret `FW_SIGN_KEY` setzen (privater Schlüssel), sonst bricht der Release-Workflow ab.
* [ ] Optional: Gesichter / Paketerkennung (anderes Modell).

## 9. Verlauf

* **2026-11-27 (5)** – 1.1 und 1.1.1: neue Weboberfläche und Seite „Smart Home“ (HA, Frigate, Scrypted, UniFi Protect), neutraler Name, SSH-Passwort sofort wirksam. Update-Problem gelöst: Der alte Updater findet auf der Kamera kein Paket, der neue sucht nur mit `awk`. 1.0.x-Kameras aktualisieren über eine einmalige Crontab-Zeile (siehe Release-Notes 1.1.1). Ausgang Keller (y211ga) läuft mit 1.1.1.

* **2026-11-27 (4)** – Release 1.0.3 stabil veröffentlicht; Build, Paketprüfungen und Ed25519-Signatur erfolgreich. `y211ga_1.0.3.tgz` vorhanden; entpacktes Paket bestätigt Parser-Fix und `AUTO_UPDATE_REPO=tzureig/YI-Hack-v2`. Fix: Modellpaket aus dem letzten Feld von `SHA256SUMS.txt` per `awk` lesen (unabhängig von `grep`-RegEx-Unterschieden). Kompletten aktuellen Repo-Checkout auf alte Markenbezeichnung in Inhalten und Pfaden geprüft: keine Treffer; frühere Commits behalten historische Texte.

* **2026-11-27 (3)** – Repo-Namen auf `YI-Hack-v2` vereinheitlicht. Update-Fehler behoben: Paketname wird direkt aus dem Dateinamen-Feld in `SHA256SUMS.txt` gelesen.

* **2026-11-27 (2)** – Version 1.0.1 vorbereitet: signierte Updates (fwverify), Beta-Kanal, kein Downgrade, Web-Upgrade nutzt denselben geprüften Weg, Modellprüfung für SD-Pakete, Snapshot ohne eingefrorenes Bild, Build-Fix (zlib.net, `fetch.sh` mit Prüfsummen), Release prüft und signiert Pakete, Upstream-PR startet Build, Detector-Härtung.
* **2026-11-27** – Komplett-Durchsicht: Web-UI im Browser getestet (fehlerfrei), Release 1.0.0 verifiziert. Korrigiert: „GitHub project“-Link auf der Statusseite zeigt jetzt auf YI-Hack-v2, README-Links absolut, überflüssiger `stale.yml`-Workflow entfernt (spart Actions-Minuten im privaten Repo). Hinweis: Wirksam auf der Kamera ab dem nächsten Release (z. B. 1.0.1).
* **2026-11-26** – Projekt gestartet: Analyse von yi-hack-Allwinner-v2, Watchdog-Ausbau, Statusseite/Logs/Health, Fehlerbehebungen (Syslog-Feld, Ethernet-Static-IP, Watchdog-Ende bei RTSP-Stopp). Sicherheit (SHA-512), Auto-Update mit Prüfsumme, Snapshot-Cache, HA/Frigate/UniFi-Doku, GitHub-Workflows, Repo `tzureig/YI-Hack-v2` mit voller Historie, Release 1.0.0, yi-detector (Person blau, Hund grün).
