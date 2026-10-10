# Chrono-Ops — Build Status

Last updated: 2026-10-10

> **Nothing below has been run in Roblox Studio yet.** The project builds with
> `rojo build` and the instance tree resolves correctly, but all gameplay behaviour
> is untested. "Written" means the code exists; it does not mean it works.

## Written (needs in-Studio verification)

### Procedural map — `src/server/ProceduralMapGenerator.server.luau` (active map)
- [x] 5x5 grid of 64-stud tiles from `ReplicatedStorage.Assets.MapTiles`, centred on the origin
- [x] Seeded: Workspace attribute `MapSeed` reproduces a layout; otherwise `floor(tick())`. Seed is printed and stored on `GeneratedMap`
- [x] Spawn A (1,3), Spawn B (5,3); 4-way junctions at (2,3) and (4,3); courtyard at (3,3)
- [x] Three lanes: Center (row 3), Alpha (rows 1-2), Beta (rows 4-5); side lanes pick a random row per column
- [x] Tiles rotated in 90° steps to match each cell's openings; placed so `Socket_*` attachments land on shared cell edges at Y = 0
- [x] BFS from Spawn A to Spawn B plus a per-lane continuity check over socket-to-socket joins before the map is parented; up to 25 attempts
- [x] Adds a neutral `SpawnLocation` to spawn tiles that don't have one; respawns anyone who loaded before the map existed
- [x] `WeaponService.PopulateDummies` spawns 4 dummies in a ring on the courtyard floor

#### Tile contract the generator assumes
- Socket direction is read from the attachment's **position** relative to the tile pivot (−Z = N, +X = E); a mismatching `Socket_*` name only warns.
- Sockets are **alignment anchors**; a tile may have all four. Which sides are doorways is detected by raycasting across each socketed edge 1.5 and 3.5 studs above the socket. Override per prefab with a string attribute `Openings` (e.g. `"NE"`, in the prefab's own axes). Startup prints `Tile_X: sockets NESW | open ES (probed)` for every tile.
- (Fixed 2026-10-10: generation failed on every corner because all tiles carry all four sockets and were read as 4-way.)
- Sockets sit on the tile edge, 32 studs from the pivot horizontally, all at the same height on every tile.
- A tile's opening set must **exactly** match the cell: Straight = 2 opposite, Corner = 2 adjacent, Intersection = 4, Spawn A / B = 1, Courtyard = 2 opposite (if it has 4 sockets the centre falls back to a Straight with a warning).
- Footprint ≤ 64x64 (warns otherwise).

#### Known gaps
- [ ] **Spawning into the void (reported).** *Hardened in code, root cause not yet confirmed.* Spawning is now held (`CharacterAutoLoads = false`) until a map exists. If generation fails for any reason the plaza loads instead, with a `GENERATION FAILED` warning carrying the reason. Tile parts are force-anchored, and missing floors/SpawnLocations are warned about.
- [ ] BFS checks socket connectivity, not physical walkability; props blocking a corridor inside a tile aren't detected.
- [ ] Cells off the lanes are left empty (void); no filler tile exists.
- [ ] No `BombSite` volumes or cover tags on the generated map (the plaza had them).
- [ ] No T-junction tile, so lanes can't branch beyond the two 4-way junctions.

### Map blockout — `src/server/MapBuilder.luau` (no longer loaded; kept for reference)
- [x] Neo-Tokyo Plaza: 200x200 floor, 24-stud perimeter wall
- [x] GDD dimensions: 6x10 doorways, 4-stud half cover, 8-stud full cover, 16-stud outer corridors
- [x] Beta Lobby (west): roofed shell, 2 east doors + 1 north + 1 south, desk/sofa half cover, 4 pillars
- [x] Alpha Rooftop (east): 20-stud tower, 12-wide south ramp, gapped west parapet, roof cover
- [x] Plaza cover, neutral spawn pad, neon accents
- [x] `Map.Sites` volumes (`Alpha`, `Beta`) tagged `BombSite`; cover tagged `HalfCover` / `FullCover`
- [x] Baseplate removed from `default.project.json`

### Weapon framework
- [x] `src/shared/BaseWeapon.luau` — states (Idle / Equipped / Reloading), ammo, reload timer, fire-rate throttle, auto-reload, events
- [x] `src/shared/WeaponConfigs.luau` — Pulse-AR stats
- [x] `src/server/WeaponService.luau` — per-player server weapon, fire validation, raycast, damage, tracer broadcast
- [x] `src/server/TargetDummy.luau` — hitbox dummies (Head / Torso / Legs), health label, hit flash, reset
- [x] `src/client/PulseARClient.client.luau` — Mouse1 / R / 1 input, prediction, HUD (ammo + crosshair), replication
- [x] `src/client/Viewmodel.luau` — camera-attached rig, mouse sway, walk bob, recoil, reload dip, muzzle flash
- [x] `src/client/Tracer.luau` — fading neon tracers

### Implementation spec (INSTRUCTIONS.md) — written 2026-10-10
- [x] `src/shared/WeaponConfigs.luau` — full stat tables for Pulse-AR, Aegis-Rail, Chrono-Sticky, Temporal-SMG
- [x] `src/shared/Ballistics.luau` — shared damage falloff, spread cone, ray-vs-sphere
- [x] `src/client/CameraRecoil.luau` — spring (Stiffness 220, Damping 18); kicks are peak angles from config
- [x] `src/client/HitmarkerHUD.luau` — crosshair gap = 6 + Spread×14 + Velocity×0.8; body / headshot X flashes + ticks on `HitConfirmed`
- [x] `src/server/StasisService.luau` — F deploys 8-stud / 4 s field; shots stop at the boundary with a frozen glow; all re-fire on expiry
- [x] `src/client/TimeRewindClient.client.luau` — 60 Hz × 180 ring buffer; E rewinds over 0.45 s with ghost trail
- [x] `src/server/RewindService.luau` — server history, 12-stud validation, commits position + server-recorded health
- [x] `src/client/StasisClient.client.luau` — F input
- [x] Pulse-AR wired to all of the above: spread 0.5°→2.2°, falloff, camera + viewmodel recoil at spec values, 0.08 s tracers, spec muzzle light
- [x] `WeaponRemotes.HitConfirmed`, `TimeRemotes.StasisDeploy` / `RewindTriggered` / `RewindResult`

#### Spec assumptions (not in INSTRUCTIONS.md — correct any that are wrong)
- **Pulse-AR falloff:** "linear falloff to 12 beyond 150" read as full damage to 150, then linear to 12 at 400 (max range).
- **Ranges:** Pulse-AR 400, Aegis-Rail 600, Temporal-SMG 200, Chrono-Sticky 300.
- **Spread growth:** per-shot growth and recovery rates (Pulse-AR 0.17°/shot, 6°/s recovery; SMG 0.25°/shot, 8°/s).
- **Aegis-Rail:** 1.5 rounds/s cap on uncharged taps; low-purple glow shade.
- **Chrono-Sticky:** 0.4-stud shape-cast radius.
- **Cooldowns:** Rewind 8 s, Stasis 12 s.
- **Stasis placement:** where you aim, up to 30 studs (1 stud short of any wall).
- **Stasis inside-out:** shots fired from *inside* a field are not trapped.
- **Re-fired shots:** resume from the frozen point with the remaining range; falloff uses total distance from the original muzzle; shooter is still excluded.
- **Crosshair base offset:** 6 px.
- **Headshot "Cyan/Red double X-flash":** cyan for the first 0.10 s, then red for 0.10 s, at 1.4× size.
- **Viewmodel recoil Z = −0.15:** treated as kickback toward the shooter.
- **Rewind health:** restored from the *server's* record at that time; the client's recorded health is not trusted. Velocity at t−180 is restored on release.
- **Ghost trail:** local-only (other players see you teleport, not the trail).

## Needs testing / likely bug-fix candidates

These are risks spotted while writing, not confirmed bugs.

### Replication & netcode
- [ ] **Ammo desync.** *Fixed in code, needs verifying.* Was: the server only synced on `Empty`, so a jitter-induced `Throttled` rejection left the client a round short, and client auto-reloads were never sent to the server, so the client could fire a full mag while the server sat in `Reloading` rejecting everything. Now the client sends `Reload` on every reload (manual or auto), the server syncs on any rejected shot (rate-limited to 4/s) and after every completed reload.
- [ ] **Server tolerance.** `OPTIONS` in `WeaponService.luau` (`FireTolerance` 0.25, `ReloadTolerance` 0.3) may be too loose or too tight under real latency.
- [ ] **Origin check.** `MAX_ORIGIN_DRIFT = 15` could reject legitimate shots while sprinting/jumping at high ping, or be too permissive.
- [ ] **No lag compensation.** Server raycasts against current positions, so moving player targets will feel unfair at ping. Dummies are stationary so they are unaffected.
- [ ] **Remote tracers.** Start point for other players' tracers is approximated from the claimed origin, not a real muzzle position. (Fixed: a zero-length remote tracer produced a NaN `.Unit`.)

### Viewmodel
- [ ] Placeholder rifle/arm positions are unverified visually (offset, scale, arm rotation). (Fixed: muzzle attachment sat 0.45 studs in front of the barrel and 0.05 too high.)
- [ ] Mouse sway relies on `GetMouseDelta()`; confirm it behaves under `LockFirstPerson`.
- [ ] Walk-bob reads `HumanoidRootPart.AssemblyLinearVelocity`; confirm it's smooth and not jittery on slopes/ramp.
- [ ] Custom rig path (`ReplicatedStorage.Viewmodel`, `Muzzle`, `Animations` folder) is untested because no rig exists yet. (Fixed: reload track played at speed 0 if the animation hadn't loaded yet.)
- [ ] Viewmodel may clip into walls at close range (no push-back).

### Gameplay / lifecycle
- [ ] Death and respawn: client `teardown` on `Died`, new weapon on `CharacterAdded`. Check no duplicate viewmodels or stuck `BindToRenderStep`.
- [ ] Holster (key `1`) then reload/fire: confirm server and client agree on state.
- [ ] Reload cancelled by holstering: confirm ammo isn't lost or duplicated. (Fixed: holstering an empty gun mid auto-reload left it equipped at 0 rounds and never reloading. `Equip()` now reloads an empty mag.)
- [ ] Damage to other players (`Humanoid:TakeDamage`) untested with 2+ players.
- [ ] Headshot detection relies on a part named exactly `Head`, so it's fine for dummies and R6/R15 but unverified. (Fixed: hats/hair blocked headshots. Accessory hits now resolve to the body part they're welded to.)

### Map
- [x] Ramp (`AlphaRooftop.Ramp`): center now offset along the slope normal so the top surface runs exactly from the roof edge to the ground (was ~0.05 below the roof and 0.2 past the tower face). Still walk it.
- [x] Lighting: `Ambient` raised from 0 to (0.27, 0.27, 0.31) so the lobby interior isn't pitch black. Tune to taste.
- [x] Overlapping wall corners (perimeter and lobby) could z-fight. X-axis walls now own the corners and Z-axis walls stop short.
- [x] Dummy at (0, 0, 15) was hidden from spawn behind `FullWallS` and the pillar. Moved to (-24, 0, 40).
- [ ] Doorway clearances (6x10) should be verified against actual character size and jump.

### Time systems & feedback
- [ ] **Camera recoil persistence.** Pitch/yaw are written as per-frame deltas because the default camera rebuilds from its own look vector. Verify recoil returns to the original aim and doesn't drift. (Fixed: near straight-up aim the camera's 80° clamp threw away part of the kick but the recovery still pulled the aim down, so it drifted. Kicks are now clamped to what the camera keeps. `Reset()` no longer leaves the camera permanently kicked, and it's called on death.)
- [ ] **Rewind anchoring.** The root is anchored client-side, so other players don't see the 0.45 s playback, only the final jump. (Fixed: the server also teleported the root 0.45 s after accepting. That write reached the client ~RTT after it had resumed moving and yanked it back. The server now commits health only, and the client, which owns its character's physics, applies the position.)
- [ ] **Rewind rejection.** If the server rejects (or doesn't answer within 1.5 s), the client snaps back to where it started. Test at high ping. (Fixed: validation compared the claim to the server's sample at the same timestamp, but the server sees the character one-way-latency late, which used up most of the 12-stud tolerance when sprinting. It now checks the closest server sample within 0.6 s after the claim.)
- [ ] **Rewind + movement script.** `MovementClient` keeps setting WalkSpeed while controls are disabled. Reviewed: crouch and sprint are re-read from key state every frame, so nothing gets stuck. Still worth a quick check.
- [ ] **Hit sound.** The spec's `rbxassetid://9114223179` failed with "Asset type does not match requested type" (not an audio asset). Temporarily using built-in `rbxasset://sounds/volume_slider.ogg` at the spec's pitches; replace with a real hit-tick upload.
- [ ] **PlayerModule missing.** `PlayerScripts.PlayerModule` never appears in play tests, so default movement controls may not exist. Rewind no longer hangs on it, but the cause is uninvestigated.
- [ ] **Stasis tracer prediction.** The shooter's client cuts its tracer at fields it can see; a field deployed in the same instant may not have replicated yet. Cosmetic only (damage is server-side); left as is.
- [x] Crosshair stayed visible while holstered or dead. It now hides with the weapon.

## Not yet implemented from INSTRUCTIONS.md
- [ ] Aegis-Rail, Chrono-Sticky and Temporal-SMG **gameplay** (stats exist in `WeaponConfigs`; no client/server weapon code yet, so charge-up, penetration, sticky projectiles, blast damage and SMG burst spread aren't playable)
- [ ] Weapon switching (only the Pulse-AR is equipped)
- [ ] Audio for weapon fire/charge/tick (sound IDs are empty placeholders)
- [ ] Ghost trail replication to other players

## Not started (from the GDD)
- [ ] Aegis-Rail (charge-up railgun)
- [ ] Chrono-Sticky (delayed-detonation launcher)
- [ ] Temporal-SMG
- [ ] Weapon audio profiles (all four weapons; no sounds exist yet)
- [ ] Stasis traps interacting with `BombSite` volumes
- [ ] Teams / team spawns, round and objective logic
- [ ] Damage numbers, kill feed (hit-confirm marker is done)
- [ ] ADS

## Housekeeping
- [x] `src/shared/Hello.luau` deleted.
- [ ] `README.md` is still the Rojo default; update it with run instructions and controls.

## How to test
1. Keep the existing `rojo serve` running (port 34872) and connect the Studio plugin.
2. Confirm the Explorer shows `ReplicatedStorage.Modules.BaseWeapon`, `StarterPlayerScripts.PulseARClient`, `ServerScriptService.Server.WeaponService`.
3. Press Play. Controls: Mouse1 fire (hold), R reload, 1 holster/equip, Shift sprint, C / Left Ctrl crouch, **E rewind**, **F stasis field**.
4. Output should print `Generated map with seed N`. Set Workspace attribute `MapSeed` to N and replay to confirm the same layout. Head through any lane to the courtyard (centre tile) and shoot the four dummies there; confirm health drops, headshots deal 1.5x, they reset after ~2.5 s. White X = body hit, cyan→red larger X = headshot.
5. Hold fire and watch the crosshair widen; run and watch it widen further.
6. Press F aiming at a dummy, shoot into the field: shots freeze at the sphere surface and all fire together after 4 s.
7. Walk around for 3 s, take damage, press E: you slide back along a cyan ghost trail and health returns to the earlier value.
8. Use a 2-player local server to verify tracers, damage and rewind teleports replicate.
