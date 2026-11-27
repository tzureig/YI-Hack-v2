# Home Assistant

Es gibt drei Wege, die sich gut kombinieren lassen.

## 1. Integration „yi-hack“ (empfohlen)

Liefert Kamera, Bewegung, PTZ, Schalter (LED, IR, Nachtmodus, …) und Mediaplayer zum Sprechen.

1. In HACS das Repository `roleoroleo/yi-hack_ha_integration` hinzufügen und **Yi Hack** installieren, Home Assistant neu starten.
2. *Einstellungen → Geräte & Dienste → Integration hinzufügen → Yi Hack*.
3. IP, Port 80, Benutzer und Passwort der Kamera eintragen.

Für Bewegungsmelder braucht die Integration MQTT (siehe 2).

## 2. MQTT mit automatischer Erkennung

1. In Home Assistant den **Mosquitto-Broker** (Add-on) und die **MQTT-Integration** einrichten.
2. Auf der Kamera: *MQTT*-Seite → Broker-IP, Port 1883, Benutzer/Passwort des Brokers.
3. *Configuration → MQTT* einschalten, speichern, neu starten.

Die Kamera meldet sich dann **automatisch** in Home Assistant an (MQTT Discovery ist in YI-Hack-v2 ab Werk aktiv), mit Bewegung, Personen-/Fahrzeug-/Tiererkennung, Babyweinen, Geräuscherkennung und Telemetrie (WLAN, Speicher, Laufzeit).

## 3. Live-Bild mit Ton (WebRTC, sehr geringe Verzögerung)

Home Assistant hat go2rtc eingebaut. In `configuration.yaml`:

```yaml
go2rtc:
  streams:
    yi_wohnzimmer:
      - rtsp://USER:PASS@192.168.1.50/ch0_0.h264
    yi_wohnzimmer_sub:
      - rtsp://USER:PASS@192.168.1.50/ch0_1.h264
```

Dann eine Karte *Picture Entity* / *WebRTC Camera* auf `yi_wohnzimmer` – Bild **und Ton** live.

Alternativ ohne YAML: *Integration hinzufügen → Generic Camera*
* Standbild-URL: `http://192.168.1.50/cgi-bin/snapshot.sh?res=low`
* Stream: `rtsp://192.168.1.50/ch0_0.h264`, Authentifizierung *Digest*, Benutzer/Passwort.

## Überwachung, ob die Kamera lebt

```yaml
binary_sensor:
  - platform: rest
    name: Yi Wohnzimmer gesund
    resource: http://192.168.1.50/cgi-bin/health.sh
    username: USER
    password: PASS
    value_template: "{{ value_json.status == 'ok' }}"
    device_class: connectivity
    scan_interval: 60
```

## Durchsagen über den Kameralautsprecher

Mit dem optionalen Paket `nanotts` aus [yi-hack-utils](https://github.com/roleoroleo/yi-hack-utils):

```yaml
rest_command:
  yi_durchsage:
    url: http://192.168.1.50/cgi-bin/speak.sh?lang=de-DE&voldb=0
    method: POST
    username: USER
    password: PASS
    payload: "{{ text }}"
```
