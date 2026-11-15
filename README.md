# Ookla Speedtest app voor Home Assistant

Een kleine Home Assistant-app (add-on) die de **officiële Ookla Speedtest CLI** gebruikt.
Die meet veel betrouwbaarder dan de standaard Speedtest-integratie van Home Assistant,
vooral op snelle glasvezelverbindingen en op zuinige hardware zoals de Home Assistant Green.

## Installeren

1. Ga in Home Assistant naar **Instellingen → Apps → App-winkel → ⋮ → Repositories**.
2. Voeg de URL van deze repository toe.
3. Installeer **Ookla Speedtest**.
4. Zet in de configuratie van de app `accept_ookla_license` op `true`. Daarmee accepteer je de
   licentie- en privacyvoorwaarden van Ookla (gratis voor persoonlijk gebruik):
   - https://www.speedtest.net/about/eula
   - https://www.speedtest.net/about/privacy
5. Start de app.

## Configuratie

| Optie | Standaard | Uitleg |
|---|---|---|
| `accept_ookla_license` | `false` | Moet `true` zijn, anders draait er geen test. |
| `schedule` | `04:00`, `14:00` | Tijden (UU:MM) waarop een test draait. |
| `server_id` | leeg | Vaste Ookla-server-ID. Leeg = Ookla kiest zelf de beste server dichtbij. |
| `run_on_start` | `false` | Direct een test bij het starten van de app. |

## Sensoren

- `sensor.ookla_speedtest_download` (Mbit/s)
- `sensor.ookla_speedtest_upload` (Mbit/s)
- `sensor.ookla_speedtest_ping` (ms)
- `sensor.ookla_speedtest_jitter` (ms)
- `sensor.ookla_speedtest_status` (`ok` of `fout`, met server, provider, resultaatlink en eventuele foutmelding als attributen)

Bij een mislukte test blijven de laatste meetwaarden staan en gaat alleen de status op `fout`.

## Test op verzoek

Roep de actie `hassio.addon_stdin` aan met `addon: <slug>_ookla_speedtest` en `input: run`.
