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
| Home Wi-Fi | iPhone → light controller (`light-controller.local`) | Today's firmware |
| Away | iPhone → EMQX → hub ESP32 → light controller | The hub sketch |
| Anywhere | iPhone → ThingSpeak (history chart, and readings until `/api/info` exists) | ThingSpeak channel ID and Read API Key |

## API the app uses

Existing firmware routes: `/api/state`, `/api/ir/state`, `/api/ir/cmd`, `/api/ir/send`, `/api/remotes`, `POST /api/remotes/save`, `/log?since=` (with the `X-Log-Total` header).

### `/api/info` (next firmware update)

Read-only JSON. A reading is `null` when its sensor is offline.

```json
{
  "version": "2026-10-23-encoder-speed",
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

Until a controller answers this route, Overview shows ThingSpeak's latest values.

### Hub relay over MQTT (EMQX)

The app connects with secure WebSocket (port 8084, path `/mqtt`). All topics start with `nexora/`.

| Topic | Who publishes | Payload |
|---|---|---|
| `nexora/req` | app | `{"id":"a1b2c3d4","r":"nexora/res/<client>","m":"GET","p":"/api/state?on=1","b":""}` — `b` is the form body for `POST` |
| `nexora/res/<client>` | hub | `{"id":"a1b2c3d4","s":200,"t":1234,"b":"<response body>"}` — `t` is `X-Log-Total` (only for `/log`) |
| `nexora/status` | hub, retained | `online`, with `offline` as its last will |
| `nexora/info` | hub, retained, every 20 s | the `/api/info` JSON |

The hub only forwards paths that start with `/api/` or `/log`. Responses can reach about 9 KB (the log), so the hub's MQTT buffer must be larger than that.

## Build

GitHub Actions on `macos-15`: XcodeGen makes the project from `project.yml`, then `xcodebuild` builds without signing and the app is zipped into `Nexora.ipa`. See `.github/workflows/build.yml`.

## What's new

### 1.0
- First version: Overview, Lighting, IR Finder, Remotes, More and Live log, in the light design.
- At home it talks to the light controller directly; away access through EMQX is ready for the hub.
- Temperature history from ThingSpeak, saved on the phone (31 days).
