# Sicherheit & Passwörter

## Was gehasht ist

| Passwort | Wie gespeichert | Warum |
| --- | --- | --- |
| **SSH / root** | nur **SHA-512-crypt-Hash** (mit Salt) in `system.conf` → `/etc/shadow` | Wird nur zur Prüfung gebraucht. Alte Klartext-Passwörter werden beim Booten automatisch umgewandelt. |
| **Weboberfläche** | Webserver bekommt nur einen **SHA-512-Hash** (`/tmp/httpd.conf`) | Basic-Auth wird gegen den Hash geprüft. |
| **Kamera-Login für RTSP/ONVIF** | auf der SD-Karte, nie an den Browser, nie in Logs | RTSP-Digest und ONVIF-WS-Security rechnen mit dem Passwort selbst – Home Assistant, Frigate und UniFi Protect funktionieren nur so. Ein Hash ist hier technisch nicht möglich. |
| **MQTT-, FTP-, WLAN-Passwort** | auf der SD-Karte, nie an den Browser | Das sind Zugangsdaten **zu anderen Geräten** – die Kamera muss sie dort im Klartext vorzeigen. |

## Was zusätzlich abgesichert ist

* Die Weboberfläche zeigt gespeicherte Passwörter nur als `********`; der Browser bekommt sie nie zu sehen. Wer das Feld unverändert lässt, behält das Passwort.
* In der Prozessanzeige der Log-Seite werden Passwörter ausgeblendet.
* **Telnet** und **FTP-Server** sind ab Werk **aus**.
* **SSH ohne Passwort ist gesperrt** (vorher war Login mit leerem Passwort möglich). Entweder SSH-Passwort setzen oder einen Schlüssel in `/tmp/sd/yi-hack/.ssh/authorized_keys` legen.
* Ohne Benutzer/Passwort zeigt die Statusseite eine rote Warnung.
* Firmware-Updates werden nur installiert, wenn `SHA256SUMS.txt` die **Ed25519-Signatur** des Release-Schlüssels trägt, die SHA-256-Prüfsumme des Pakets stimmt und das Paket zum Kameramodell passt. Der öffentliche Schlüssel ist in die Firmware eingebaut (`src/fwverify/fw_sign.pub`, geprüft von `bin/fwverify`). Nötig, weil BusyBox-`wget` keine TLS-Zertifikate prüft.
* Der private Schlüssel liegt nur im GitHub-Secret `FW_SIGN_KEY` (und als Sicherung beim Besitzer). Geht er verloren, neuen Schlüssel erzeugen, `fw_sign.pub` ersetzen und die Kameras einmal von Hand aktualisieren.

## Grenzen (ehrlich)

* Die SD-Karte ist FAT32 – wer die Karte **physisch** in der Hand hat, kann die Konfiguration lesen. Kamera so montieren, dass die Karte nicht leicht entnommen werden kann.
* HTTP und RTSP sind unverschlüsselt (wie bei fast allen günstigen IP-Kameras). Kameras am besten in ein eigenes VLAN/Gäste-Netz ohne Internetzugang legen; mit *Disable cloud* telefoniert die Kamera nicht mehr nach Hause.
* Das Original-Yi-App-Konto/Cloud ist ein eigenes Thema: für maximale Sicherheit *Configuration → Disable cloud* einschalten.

## Empfehlungen

1. Langes Kamera-Passwort (16+ Zeichen) setzen.
2. SSH-Passwort setzen oder SSH ausschalten, wenn du es nicht brauchst.
3. Kamera in ein separates Netz, kein Portforwarding ins Internet – Fernzugriff über VPN, Home Assistant oder UniFi.
