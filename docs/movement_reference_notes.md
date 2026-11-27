# Movement Reference Notes (Riposte-Frontline-Source vs Hood Zombies)

Reference repository studied: `BenDBSS/Riposte-Frontline-Source` (`src/07c-controller.js`, `src/08-player.js`).

## 1. Exact Numeric Comparison

| Parameter | Classic (`Hood Zombies` Phase 1–12) | Riposte (`07c-controller.js` / `08-player.js`) | Feel Impact |
| :--- | :--- | :--- | :--- |
| **Base Walk Speed** | `5.0` m/s | `4.75` m/s (`MOVE_SPEED`) | Slightly more grounded base pace; weapon mobility differences stand out more |
| **Sprint Multiplier** | `1.60x` (`8.0` m/s) | `1.55x` (`SPRINT_MUL`, `~7.36` m/s) | Tighter delta between walk and sprint |
| **Crouch Multiplier** | `0.56x` (`2.8` m/s) | `0.60x` (`~2.85` m/s) | Comparable crouch speed |
| **ADS Speed Multiplier** | `0.72x` (all weapons) | `0.58x` (iron/reflex), `0.40x` (scoped) | Stronger commitment when aiming down sights |
| **Ground Accel / Friction** | `14.0` accel / `16.0` decel (`lerpf`) | `16.5` walk / `13.5` sprint (`1 - exp(-k * dt)`) | Snappier walk start/stop; exponential damping is frame-rate independent |
| **Air Acceleration** | `4.0` | `2.2` | Less mid-air steering; jumps commit to trajectory |
| **Gravity** | `14.0` m/s² | `19.0` m/s² | Snappier, less floaty jump arc |
| **Jump Velocity** | `5.5` m/s (`~1.08 m` apex) | `6.3` m/s (`~1.04 m` apex) | Same jump height, ~26% faster up/down arc |
| **Crouch / Stand Height** | `1.0` / `1.8` m (`eye: 0.85 / 1.60`) | `1.2` / `1.75` m (`eye: 1.10 / 1.62`) | Higher crouch eye level, distinct from `0.85 m` slide |
| **Slide** | Not implemented | `dur=0.75s`, `boost=1.4x`, `floor=6.8`, `max=10.3`, `end=3.1`, `cd=0.26s`, `turn=2.0 rad/s`, `buffer=0.3s` | Adds sprint-to-crouch burst mobility with ADS/fire allowed mid-slide |
| **Camera Bob** | Simple `0.05` sin/cos on camera | Stride-synced (`PI * hs / (sprint ? 2.7 : 2.1)`), `0.012 + 0.008*sw` vert, `0.007` horiz, `0.003 + 0.005*sw` roll, muted `80%` in ADS | Camera stays steady while viewmodel carries most motion |
| **Sprint FOV** | `+8.0°` | `+8.5%` + `+3.0°` sprint-start kick + `+6.5°` slide kick | Punchy sprint/slide entry feedback |
| **Landing Dip & Roll** | None | `lk = clamp(-vy * 0.08, 0.3, 1.3)`, viewmodel dip + camera pitch/roll impulse | Gives weight to falls and jumps |
| **Weapon Sway & Shake** | Basic sway | Mouse/stick sway (`0.0006` scaled), firing shake + scoped ADS breath sway | Tactile weapon weight and ADS tension |

## 2. Implementation in `Hood Zombies`

- All movement constants live in `MovementConfig` (`resources/configuration/movement_config.tres`) with two named profiles: **`riposte`** (default, `"Riposte-style"`) and **`classic`** (`"Classic"`).
- `PlayerController` preserves all existing perk modifiers (`PlayerStats`), weapon speed multipliers (`WeaponData.move_speed_multiplier`), crouch ceiling checks (`CeilingCheck`), and keyboard + Xbox/PS5 controller input.
- Slide is triggered by pressing `crouch` while sprinting (with `0.3s` input buffer), decays with `pow(1 - k, 1.35)`, allows steering (`2.0 rad/s`) and firing/ADS, and stops on jump or wall impact.
- Intensity sliders (`0%–100%`) for **Camera Bob**, **Weapon Bob/Sway**, **Camera Shake**, and **Landing Dip** are persisted via `SaveManager` and `SettingsManager`.
