# Chrono-Ops (FPS-ROBLOX)

A Roblox first-person shooter built around time abilities: rewind your position, freeze
bullets in a stasis field, and fight across a procedurally generated map.

> **Status:** early development. The code builds with Rojo, but gameplay has not been
> verified end to end in Studio yet. See [STATUS.md](STATUS.md) for what's written and
> what's still open.

## Getting Started
Built with [Rojo](https://github.com/rojo-rbx/rojo) 7.7.1.

To build the place from scratch, use:

```bash
rojo build -o "FPS-ROBLOX.rbxlx"
```

Next, open `FPS-ROBLOX.rbxlx` in Roblox Studio and start the Rojo server:

```bash
rojo serve
```

For more help, check out [the Rojo documentation](https://rojo.space/docs).

## Controls

| Input | Action |
| --- | --- |
| Mouse1 | Fire (Pulse-AR) |
| R | Reload |
| 1 | Equip Pulse-AR |
| Left Shift | Sprint |
| C / Left Ctrl | Crouch |
| E | Time Rewind |
| F | Deploy Stasis Field |

## Project Layout

| Path | Synced to | Contents |
| --- | --- | --- |
| `src/shared` | `ReplicatedStorage.Modules` | Weapon base class, weapon stats, ballistics |
| `src/server` | `ServerScriptService.Server` | Map generation, weapon / rewind / stasis services, target dummies |
| `src/client` | `StarterPlayer.StarterPlayerScripts` | Input, viewmodel, recoil, HUD, tracers, movement |

## Docs

- [INSTRUCTIONS.md](INSTRUCTIONS.md): implementation spec (weapon roster, abilities, tuning values)
- [STATUS.md](STATUS.md): build status, known gaps, and spec assumptions
- [REPORT.md](REPORT.md): latest progress report
