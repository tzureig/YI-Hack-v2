# Feste IP-Adresse

## Variante 1 (empfohlen): im Router reservieren

Im Router (FRITZ!Box: *Heimnetz → Netzwerk → Gerät bearbeiten → „Diesem Netzwerkgerät immer die gleiche IPv4-Adresse zuweisen“*, UniFi: *Client → Settings → Fixed IP*) die IP der Kamera festhalten.
Vorteil: Die Kamera bleibt auf DHCP, Gateway und DNS stimmen immer, und der Watchdog kann bei Problemen einfach die Adresse neu anfordern.

## Variante 2: fest in der Kamera

Weboberfläche → *Status* → bei „Address“ auf **Edit** (Seite *Static IP*):

| Feld | Beispiel |
| --- | --- |
| IP | 192.168.1.50 |
| Netmask | 255.255.255.0 |
| Gateway | 192.168.1.1 |
| DNS 1 / DNS 2 | 192.168.1.1 / 1.1.1.1 |

Speichern, Kamera neu starten. Funktioniert für WLAN (`wlan0`) und Kabel (`eth0`). Zum Zurück auf DHCP alle Felder leeren.

Wichtig: Die Adresse muss **außerhalb** des DHCP-Bereichs deines Routers liegen, sonst kann es zu doppelt vergebenen Adressen kommen.
