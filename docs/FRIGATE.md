# Frigate

Die Kamera liefert gleichzeitig einen Hauptstream (1080p/2K, H.264 + AAC) und einen Substream (640×360). Ideal für Frigate: **Erkennung auf dem Substream, Aufnahme vom Hauptstream**.

Damit die Kamera nur **eine** Verbindung pro Stream bekommt (sie hat wenig RAM), holt Frigates go2rtc die Streams ab und verteilt sie weiter (Restream).

## Kamera-Einstellungen

*Configuration* in der Kamera-Weboberfläche:
* RTSP: an, **RTSP streams: both** (ab Werk), Audio: **AAC** (ab Werk)
* Benutzer/Passwort setzen
* Swap: an (ab Werk)

## frigate.yml

```yaml
go2rtc:
  streams:
    yi_garten:
      - rtsp://USER:PASS@192.168.1.50/ch0_0.h264
    yi_garten_sub:
      - rtsp://USER:PASS@192.168.1.50/ch0_1.h264

cameras:
  yi_garten:
    ffmpeg:
      output_args:
        record: preset-record-generic-audio-copy   # Ton mit aufnehmen
      inputs:
        - path: rtsp://127.0.0.1:8554/yi_garten
          input_args: preset-rtsp-restream
          roles:
            - record
        - path: rtsp://127.0.0.1:8554/yi_garten_sub
          input_args: preset-rtsp-restream
          roles:
            - detect
            - audio          # Geräuscherkennung (optional)
    detect:
      width: 640
      height: 360
      fps: 5
    record:
      enabled: true
    snapshots:
      enabled: true
    live:
      streams:
        Haupt: yi_garten
        Sub: yi_garten_sub
```

Live-Ansicht in Frigate/Home Assistant (Frigate-Integration) läuft über go2rtc per WebRTC/MSE – **mit Ton**.

## Tipps

* **Bildfehler / grüne Blöcke:** In der Kamera unter *Configuration* `RTSP server` auf **go2rtc** oder **alternative** stellen und testen, welcher bei dir am stabilsten läuft.
* **Hohe Last auf der Kamera:** keine zusätzlichen direkten Clients (VLC, Home Assistant) auf die Kamera – alle über Frigates go2rtc (`rtsp://FRIGATE-IP:8554/yi_garten`).
* Die Snapshots von Frigate kommen aus dem Stream, nicht von `snapshot.sh` – das schont die Kamera.
