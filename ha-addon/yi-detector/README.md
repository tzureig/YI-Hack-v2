# YI Detector (Home Assistant Add-on)

Erkennt Personen (blauer Rahmen) und Hunde (grüner Rahmen) sowie Katzen im Bild deiner YI-Hack-v2-Kameras – auch wenn sie sich nicht bewegen.

Installation: *Einstellungen → Add-ons → Add-on Store → ⋮ → Repositories* → `https://github.com/tzureig/YI-Hack-v2` hinzufügen → **YI Detector** installieren.

In der Konfiguration die Kameras eintragen (am besten den Substream `ch0_1.h264`). Mit dem Mosquitto-Add-on erscheinen pro Kamera automatisch die Sensoren *Person*, *Hund*, *Katze* (+ Anzahl) und eine Kamera *Erkennung* mit den Rahmen.

Details: [detector/README.md](../../detector/README.md)
