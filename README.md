# Nexora

iPhone app for the ESP32 sensor station and light controller: readings, lighting, IR finder, remote translator and live log, in one place.

## Get the app

Every push to `main` builds an **unsigned** `Nexora.ipa` with GitHub Actions.

- Latest build: [Releases → latest → Nexora.ipa](https://github.com/aminmigo88/Nexora/releases/latest/download/Nexora.ipa)
- Also attached to each run under **Actions → Build unsigned IPA → Artifacts** (as a zip).

Sign it in KravaSigner with your distribution certificate, then install. Bundle ID: `com.aminmigo88.nexora`.

No passwords or keys are in this repo or in the build. You type them in the app (**More → Connection**) and they stay in the iPhone Keychain.

## How it connects

| Where you are | Path | Needs |
|---|---|---|
| Home Wi-Fi | iPhone → light controller (`light-controller.local`) | The light controller firmware |
| Away | iPhone → EMQX → hub ESP32 → light controller | The hub sketch |
| Anywhere | iPhone → Adafruit IO (readings, group `room-temperature`, every 20 s) | Adafruit IO username and AIO key |
| Anywhere | iPhone → ThingSpeak (history chart, and readings as a last resort) | ThingSpeak channel ID and Read API Key |

Overview takes its readings in this order: the ESP32's `/api/info` (every 2 s at home, 3 s away; eCO₂ and TVOC change every second, the rest every 20 s), then Adafruit IO, then ThingSpeak.

## API the app uses

Existing firmware routes: `/api/state`, `/api/ir/state`, `/api/ir/cmd`, `/api/ir/send`, `/api/remotes`, `POST /api/remotes/save`, `/log?since=` (with the `X-Log-Total` header).

### `/api/info` (firmware 2026-11-23-api-info and later)

Read-only JSON. A reading is `null` while its sensor is offline or warming up.

```json
{
  "version": "2026-11-23-api-info",
  "uptime": 12345,
  "indoor": 23.4,
  "outdoor": 14.8,
  "bmeTemp": 23.9,
  "humidity": 48.0,
  "pressure": 1013.2,
  "eco2": 612,
  "tvoc": 34,
  "scenes": ["Warm White", "Cool White", "…"]
}
```

Older firmware answers 404; the app then uses Adafruit IO, then ThingSpeak, and asks again after a minute.

### Hub relay over MQTT (EMQX)

The app connects with secure WebSocket (port 8084, path `/mqtt`). All topics start with `nexora/`.

| Topic | Who publishes | Payload |
|---|---|---|
| `nexora/req` | app | `{"id":"a1b2c3d4","r":"nexora/res/<client>","m":"GET","p":"/api/state?on=1","b":""}` — `b` is the form body for `POST` |
| `nexora/res/<client>` | hub | `{"id":"a1b2c3d4","s":200,"t":1234,"b":"<response body>"}` — `t` is `X-Log-Total` (only for `/log`) |
| `nexora/status` | hub, retained | `online`, with `offline` as its last will |

Away, the app asks for `/api/info` through the hub like any other request.

The hub only forwards paths that start with `/api/` or `/log`. Answers can reach about 9 KB (the log); the hub streams them, so its MQTT buffer only needs to fit the requests.

## Build

GitHub Actions on `macos-15`: XcodeGen makes the project from `project.yml`, then `xcodebuild` builds without signing and the app is zipped into `Nexora.ipa`. See `.github/workflows/build.yml`.

## What's new

### 1.4.1
- Widget: reads the app's settings in more ways, so it works with more kinds of signing (the app saves the widget's copy in its own Keychain group and in a team-wide one; the widget looks in every group it may open).
- Widget: if the signing still keeps it apart from the app, it asks for a setup code: Nexora → More → Widget → Copy setup code, then hold the widget → Edit Widget → paste. The code is copied only on this iPhone and clears from the clipboard after 2 minutes.
- More → Widget shows what the last hand-over to the widget did.

### 1.4
- Home screen widget (small): outdoor temperature and humidity with ↑/↓ and the change since the same time yesterday, eCO₂ and TVOC colored green / orange / red by air quality, on the sky with the sun by day or the moon in its real phase at night.
- The widget's readings follow the app's order: the ESP32 itself (through EMQX), then Adafruit IO, then ThingSpeak. Yesterday's values come from ThingSpeak. Closing the app hands its own readings to the widget.
- Sunrise, sunset and moon phase come from MET Norway's Sunrise 3.0 service once a day, for the spot set in More → Widget → Use my current location (worked out on the phone if the service can't be reached).
- Air quality colors: eCO₂ good up to 1000 ppm, moderate up to 1500 ppm, bad above; TVOC good up to 220 ppb, moderate up to 660 ppb, bad above.

### 1.3
- Lighting: the live light preview no longer cuts off its title at the top and the brightness / "5 PWM channels" line at the bottom.
- Overview: the last digit of the big temperatures (like the 0 in 23.0 or the 8 in 21.8) is no longer cut on its right side.

### 1.2
- Overview reads the ESP32's own `/api/info` every 2 s at home and every 3 s away (through the hub), shown as "Live". Then Adafruit IO, then ThingSpeak.
- Replies from the hub with a broken UTF-8 byte no longer get lost.

### 1.1
- Overview gets its readings from Adafruit IO (the 7 feeds in `room-temperature`, refreshed every 20 s). A sensor that stopped updating shows "—".
- New Adafruit IO settings in More → Connection: username, AIO key, group. Saved in the Keychain.
- The temperature chart still comes from ThingSpeak.

### 1.0
- First version: Overview, Lighting, IR Finder, Remotes, More and Live log, in the light design.
- At home it talks to the light controller directly; away access through EMQX is ready for the hub.
- Temperature history from ThingSpeak, saved on the phone (31 days).
