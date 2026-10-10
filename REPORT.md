# Chrono-Ops — Progress Report

**Date:** 2026-10-10
**From:** Claude (Lead Programmer)
**Scope:** Gameplay code in the Rojo project (`src/`). Map tile art and Studio-side assets are out of scope.

## Summary

- **The core systems are written:** map generation, the weapon framework, the Pulse-AR, Time-Rewind, Stasis Field, recoil, hit feedback, and sprint/crouch. The project builds cleanly with Rojo.
- **None of it has been confirmed working end to end in a play-test yet.** The play-tests so far hit blocking bugs before gameplay could be exercised.
- **Four problems surfaced in play-test Output. All are fixed in code, except a missing default control module, which is still open.** The procedural map has never generated successfully. The fix for that is in and waiting on the next play-test.
- **Three of the four launch weapons are stats only.** Only the Pulse-AR is playable.

> **Note on testing:** I can't run Roblox Studio myself. The play-test findings below come from the team's Studio Output and the Studio log files, not from me playing the game.

## 1. Completed (code written, builds, awaiting play-test)

| Area | What exists |
|---|---|
| **Procedural map** | 5×5 grid of 64-stud tiles from `Assets.MapTiles`. Three guaranteed lanes (Alpha / Center / Beta), seeded and reproducible, tiles aligned by socket attachments, BFS path check before the map goes live, dummies in the central courtyard. Falls back to the static plaza if generation fails. |
| **Weapon framework** | Shared `BaseWeapon` class (ammo, reload, fire-rate, Idle/Equipped/Reloading states). Client prediction with server authority: the server validates every shot, applies damage, and broadcasts tracers. |
| **Pulse-AR** | Fully playable to spec: 10 rounds/s, 30/120, 2.0 s reload, 18 dmg / 1.5× headshot, distance falloff, spread 0.5°→2.2°, camera and viewmodel recoil at spec values, tracer and muzzle-light VFX. |
| **Weapon roster data** | Complete stat tables for all four launch weapons (Pulse-AR, Aegis-Rail, Chrono-Sticky, Temporal-SMG). |
| **Time-Rewind (E)** | 3-second, 60 Hz position/health recorder; 0.45 s backward playback with ghost trail. Server validates within 12 studs and restores health from its own record (cheat-resistant). |
| **Stasis Field (F)** | 8-stud, 4 s sphere that freezes incoming shots at its surface and re-fires them all on expiry. |
| **Feedback** | Spring-based camera recoil (stiffness 220 / damping 18), dynamic crosshair (spread + movement), body vs. headshot hitmarkers with audio. |
| **Movement** | Sprint (Shift) and crouch (C / Left Ctrl), with low-ceiling protection. |
| **Test range** | Target dummies with health display, hit flash and auto-reset. |

## 2. Play-test findings

| # | Symptom | Cause | Status |
|---|---|---|---|
| 1 | Shots dealt no damage; error at `WeaponService:35` | Helper function called before it was defined | **Fixed** |
| 2 | Players spawned into empty space and died | Map generation failed (see #3), so there was no floor or spawn point. Players could also load in before the map existed. | **Fixed in code:** spawning now waits for the map, and the plaza loads if generation fails. Needs re-test. |
| 3 | `No valid layout after 25 attempts … openings "ES"` | Every tile carries all four sockets, so every tile was read as a 4-way intersection and no corner could be placed | **Fixed in code:** doorways are now detected by raycasting each tile edge, with a per-tile manual override. Needs re-test. |
| 4 | `Failed to load sound rbxassetid://9114223179` | The ID in the spec is not an audio asset | **Worked around** with a built-in tick sound; needs a real asset (see Decisions) |
| 5 | `PlayerModule` never appears for the player | Not yet investigated. May mean Roblox's default movement controls aren't loading. | **Open** |
| 6 | Sprint/crouch "not working" | Had never been implemented | **Built** |

## 3. Needs fixing or verifying next

In priority order:

1. **Re-run the play-test for map generation.** Confirm the per-tile `open …` lines in Output are correct and the map builds. If any tile is misread, set its `Openings` attribute.
2. **PlayerModule / default controls (#5).** If WASD doesn't work, nothing else can be tested properly.
3. **Core loop check:** shoot dummies in the courtyard (damage, headshots, hitmarkers, falloff), reload, holster, die and respawn.
4. **Time abilities:** rewind at sprint speed and under latency (risk of false rejections), and stasis capture/re-fire.
5. **2-player test:** damage between players, tracer replication, rewind teleports as seen by others.
6. **Known design gaps on the generated map:**
   - empty grid cells are open void, since no filler tile exists
   - no bomb-site volumes or cover tags yet
   - the BFS path check doesn't detect props blocking a corridor

## 4. Still to build

- **Aegis-Rail** gameplay: charge-up, auto-release, wall penetration, beam VFX
- **Chrono-Sticky** gameplay: arced projectiles, latching, fuse/manual detonation, blast falloff, 3-active limit
- **Temporal-SMG** gameplay: burst-then-bloom spread, continuous camera shake
- **Weapon switching** (currently Pulse-AR only)
- **All weapon audio** (no sound assets exist yet)
- **Match structure:** teams and team spawns, rounds, objectives / bomb sites, Stasis interaction with sites
- **UI:** kill feed, damage numbers, ability cooldown indicators
- **ADS**
- **Ghost-trail visibility for other players** (currently only the rewinding player sees it)

## 5. Decisions needed from you

1. **Hit sound:** please supply a valid audio asset ID for the hit tick (spec ID `9114223179` is not audio).
2. **Values missing from the spec:** I chose these; please confirm or replace.
   - Rewind cooldown **8 s**, Stasis cooldown **12 s**
   - Pulse-AR falloff read as: full damage to 150 studs, then down to 12 at 400 studs
   - Max ranges: Pulse-AR 400, Aegis-Rail 600, SMG 200
   - Headshot "Cyan/Red double flash" played as cyan then red, 0.10 s each
3. **Empty map cells:** add a filler/blocker tile to the tile set, or should the generator wall off the map edge itself?
4. **Next priority after play-test fixes:** the remaining three weapons, or match structure (teams/rounds)?

Full technical detail, per-file notes and test steps are in `STATUS.md`.
