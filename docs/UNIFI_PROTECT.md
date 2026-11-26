# UniFi Protect

UniFi Protect (ab Version 5.0) kann Fremdkameras über **ONVIF** einbinden. YI-Hack-Tiz bringt dafür einen ONVIF-Server mit Profile S, zwei Profilen (Haupt- und Substream), Snapshots, PTZ (bei schwenkbaren Modellen) und WS-Discovery mit.

## Kamera vorbereiten

In der Kamera-Weboberfläche:

1. **Configuration → Authentication:** Benutzername und Passwort setzen – **Pflicht**, Protect bindet Kameras ohne Login nicht ein.
2. **Configuration:** `ONVIF` an, `RTSP` an, RTSP streams **both** (ab Werk).
3. **ONVIF-Seite** (*Configuration → ONVIF*):
   * ONVIF profile: **both** (ab Werk)
   * WS-Discovery: an (ab Werk)
   * Netzwerkschnittstelle: `wlan0` (WLAN) bzw. `eth0` (Kabel)
4. Speichern und Kamera neu starten.
5. Am besten eine **feste IP** vergeben ([FESTE_IP.md](FESTE_IP.md)), damit Protect die Kamera nach einem Neustart sicher wiederfindet.

## In Protect einbinden

1. Protect öffnen → *Einstellungen → System → Erweitert* (bzw. *Geräte*) → **Third-Party Cameras / Discovery** aktivieren.
2. *Geräte* → **Adopt** – die Kamera erscheint als ONVIF-Gerät. Falls nicht: *Manuell hinzufügen* mit der IP-Adresse.
3. Benutzername und Passwort der Kamera eingeben.
4. Protect nimmt den Hauptstream für Aufnahme und den Substream für die Vorschau.

## Bekannte Grenzen

* Protect nutzt bei Fremdkameras nur Stream + Ton; Smart Detections (Personen/Fahrzeuge) von Protect gibt es dafür je nach Protect-Version nicht oder eingeschränkt.
* Sprechen (Gegensprechen) über Protect wird bei ONVIF-Fremdkameras nicht unterstützt – dafür die Home-Assistant-Integration nutzen.
* Wird die Kamera nicht gefunden: Kamera und Protect müssen im selben Netz/VLAN sein (WS-Discovery ist Multicast); sonst manuell per IP hinzufügen.
