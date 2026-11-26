# YI-Hack-Tiz

Custom-Firmware für Yi-Kameras mit Allwinner-Chip (Yi Home 1080p, Yi Outdoor, Yi Dome, Yi Pro 2K, Kami, MIBAO, Blitzwolf …).
Basiert auf [roleoroleo/yi-hack-Allwinner-v2](https://github.com/roleoroleo/yi-hack-Allwinner-v2) (aktueller Stand, wöchentlich abgeglichen) und ergänzt:

* **Immer erreichbar:** Watchdog für Stream, Weboberfläche, SSH, ONVIF, mDNS, cron, WLAN und Netzwerk (Router-Ping → DHCP neu → Neustart mit Back-off), Ethernet-Erkennung, geplanter Neustart.
* **Automatische Updates:** täglicher Check, Installation nachts, SHA-256-geprüft, Einstellungen bleiben erhalten. Updates kommen aus den [Releases dieses Repos](../../releases).
* **Sicherheit:** SSH-Passwort nur als SHA-512-Hash, Weboberfläche mit SHA-512-Hash, Passwörter werden nie an den Browser geschickt oder in Logs gezeigt, Telnet/FTP standardmäßig aus, kein SSH-Login mit leerem Passwort.
* **Snapshots, die nicht abstürzen:** Ein einziger Decoder, auch wenn Home Assistant, Frigate und UniFi gleichzeitig abfragen. Dazu ein kurzer Cache und ein Ersatzbild, falls etwas schiefgeht.
* **Bild + Ton live:** Haupt- und Substream (H.264 + AAC) gleichzeitig per RTSP und ONVIF, ab Werk eingeschaltet.
* **Personen- & Tiererkennung mit Rahmen** ([detector/](detector/README.md)): Person blau, Hund grün, auch ohne Bewegung – als Home-Assistant-Add-on oder Docker, mit MQTT-Sensoren und Live-Stream.
* **Home Assistant, Frigate, UniFi Protect:** fertige Anleitungen und Beispielkonfigurationen.
* **Weboberfläche:** Statusseite mit Diensten, Speicher, SD, Temperatur, WLAN-dBm, Update-Status; Log-Ansicht; Health-Endpoint für Monitoring.

## Schnellstart

1. Unter [Releases](../../releases) das Paket für dein Modell laden (Tabelle: [docs/ANLEITUNG_DE.md](docs/ANLEITUNG_DE.md)).
2. SD-Karte FAT32 formatieren, Paket entpacken, Inhalt auf die Karte kopieren, Karte in die Kamera, Kamera neu starten.
3. `http://IP-DER-KAMERA` öffnen → **Configuration → Authentication**: Benutzer + Passwort setzen.
4. Fertig – Updates kommen ab jetzt automatisch nachts.

## Anleitungen

| Thema | Datei |
| --- | --- |
| Installation, Update, Modelltabelle | [docs/ANLEITUNG_DE.md](docs/ANLEITUNG_DE.md) |
| Home Assistant | [docs/HOME_ASSISTANT.md](docs/HOME_ASSISTANT.md) |
| Frigate | [docs/FRIGATE.md](docs/FRIGATE.md) |
| UniFi Protect | [docs/UNIFI_PROTECT.md](docs/UNIFI_PROTECT.md) |
| Feste IP-Adresse | [docs/FESTE_IP.md](docs/FESTE_IP.md) |
| Personen-/Tiererkennung (yi-detector) | [detector/README.md](detector/README.md) |
| Sicherheit & Passwörter | [docs/SICHERHEIT.md](docs/SICHERHEIT.md) |
| Projektwissen (Second Brain) | [docs/SECOND_BRAIN.md](docs/SECOND_BRAIN.md) |
| Neue Version veröffentlichen | [docs/RELEASE.md](docs/RELEASE.md) |
| Original-README (englisch) | [docs/README_upstream.md](docs/README_upstream.md) |

## Adressen auf der Kamera

| Was | URL |
| --- | --- |
| Hauptstream (Bild + Ton) | `rtsp://USER:PASS@IP/ch0_0.h264` |
| Substream 640×360 | `rtsp://USER:PASS@IP/ch0_1.h264` |
| Nur Ton | `rtsp://USER:PASS@IP/ch0_2.h264` |
| Snapshot | `http://USER:PASS@IP/cgi-bin/snapshot.sh?res=high` (oder `res=low`) |
| ONVIF | `http://IP/onvif/device_service` |
| Health-Check | `http://USER:PASS@IP/cgi-bin/health.sh` (200 = ok, 503 = gestört) |
| Status (JSON) | `http://USER:PASS@IP/cgi-bin/status.json` |

## Selbst bauen

Siehe [docs/RELEASE.md](docs/RELEASE.md) – GitHub Actions baut alle Modelle automatisch.

## Lizenz

GPL-3.0 wie das Original-Projekt. Nutzung auf eigene Gefahr.
