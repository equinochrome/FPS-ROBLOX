# Chrono-Ops: Lead Programmer Implementation Specification (Claude)

## 1. Launch Weapon Roster Math & Mechanics

All weapons inherit from `BaseWeapon` (`ReplicatedStorage.Modules.BaseWeapon`). Implement client-side prediction with server-authoritative validation, raycast projectile tracing, and spring-based viewmodel recoil curves.

### Weapon 1: Pulse-AR (Energy Rifle)
* **Archetype:** Full-Auto Kinetic/Energy Hybrid Rifle.
* **Damage Profile:** Base `18` (Body/Limbs), `1.5x` Headshot Multiplier (`27`), linear falloff to `12` beyond `150` studs.
* **Firing & Reload:** `10` rounds/sec (`0.10s` interval), `30` round mag, `120` reserve, `2.0s` reload duration.
* **Ballistics & Recoil:** Hitscan raycast. Base spread `0.5°` expanding to `2.2°`. Camera kickback Pitch `+0.45°`, Yaw `±0.15°` (lerp recovery speed = 18). Viewmodel recoil Z-axis `-0.15` studs, pitch `+2.5°`.
* **VFX/SFX Parameters:** Cyan/Neon-Blue muzzle burst (`Color3.fromRGB(0, 220, 255)`), dynamic point light (Radius = 12, Brightness = 4, Duration = 0.05s). Fading neon tracer (`0.08s`). Punchy metallic crack audio.

### Weapon 2: Aegis-Rail (Charge-up Railgun)
* **Archetype:** Hold-to-Charge Heavy Hitscan DMR.
* **Damage Profile:** Uncharged tap = `25` damage. Fully charged (`1.2s` hold) = `85` body / `2.0x` Headshot (`170` damage). Penetrates up to 2 light cover walls with `30%` damage reduction per wall.
* **Firing & Reload:** `1.2s` charge time. Auto-releases at 100% charge. `5` round mag, `20` reserve, `2.8s` reload duration.
* **Ballistics & Recoil:** Hitscan. Spread `0.0°` grounded, `3.5°` airborne. Camera kickback Pitch `+2.2°`, Yaw `±0.5°`. Viewmodel recoil Z-axis `-0.4` studs, pitch `+6.0°`.
* **VFX/SFX Parameters:** Viewmodel optics glow low-purple to bright white over `1.2s`. Discharge beam thickness = `0.6` studs with white inner core and magenta shell (`0.25s` decay). Rising charge pitch and thunderclap discharge sound.

### Weapon 3: Chrono-Sticky (Delayed Launcher)
* **Archetype:** Arced Physical Projectile Sticky Launcher.
* **Damage Profile:** Direct impact = `10` damage. Blast radius = `75` max damage (`0–4` studs), falling off linearly to `15` (`14` studs). Direct enemy latch = `1.25x` blast multiplier (`93.75` max damage).
* **Firing & Reload:** Fire rate `1.8` rounds/sec (`0.55s` interval). `2.5s` detonation fuse or manual detonation via `Mouse2`. Max `3` active sticky projectiles per player. `4` round mag, `16` reserve, `2.4s` reload.
* **Ballistics & Recoil:** Physical shape-cast projectile with gravity (`Vector3.new(0, -35, 0)`). Velocity = `140` studs/sec forward. Camera kickback Pitch `+0.8°`, Yaw `+0.3°`.
* **VFX/SFX Parameters:** Canister model with pulsating LED ring (Red = Hostile, Blue = Friendly). Ticking audio accelerates (`1 Hz -> 4 Hz -> 12 Hz -> Explosion`). Shockwave sphere expanding to 14 studs before snapping inward with glass-shatter distortion particles.

### Weapon 4: Temporal-SMG (High-Burst Firearm)
* **Archetype:** Ultra-Fast Cycling Compact SMG.
* **Damage Profile:** Base `11` damage, Headshot `1.4x` (`15.4`), heavy falloff starting at `35` studs down to `5` at `80` studs.
* **Firing & Reload:** `18` rounds/sec (`0.055s` interval), `40` round mag, `160` reserve, `1.5s` reload.
* **Ballistics & Recoil:** Hitscan. Initial 3-round burst spread `0.8°`, expanding to `4.2°` during sustained fire. Continuous camera vibration (Pitch `+0.18°`, Yaw `±0.35°`).
* **VFX/SFX Parameters:** Strobe muzzle flash. High-velocity casing ejection out right port. Rapid metallic rattle audio.

---

## 2. Tactical Time Systems Logic

### A. 3-Second Time-Rewind Engine (`src/client/TimeRewindClient.luau`)
* Maintain a 60 Hz rolling ring-buffer logging 180 snapshots:
  ```luau
  type RewindSnapshot = {
      Timestamp: number,
      CFrame: CFrame,
      Health: number,
      Velocity: Vector3
  }