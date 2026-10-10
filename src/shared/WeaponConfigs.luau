--!strict
-- Launch weapon roster (INSTRUCTIONS.md section 1). Shared so client prediction and
-- server validation never drift apart.
--
-- Units: angles in degrees, distances in studs, times in seconds, FireRate in rounds/sec.
-- BaseWeapon reads: Name, MagSize, ReserveAmmo, FireRate, ReloadTime, Damage,
-- HeadshotMultiplier, Range, Automatic. Everything else is per-system data.
--
-- Values marked ASSUMPTION are not in the spec and were chosen to make the system work.
-- Sound IDs are empty placeholders until audio assets exist.

local WeaponConfigs = {}

WeaponConfigs.PulseAR = {
	Id = "PulseAR",
	Name = "Pulse-AR",
	Archetype = "Full-Auto Kinetic/Energy Hybrid Rifle",
	FireMode = "Hitscan",
	Automatic = true,

	-- Damage
	Damage = 18,
	HeadshotMultiplier = 1.5, -- 27
	-- Full damage to 150 studs, then linear down to 12 at max range, flat beyond.
	Falloff = { Start = 150, End = 400, MinDamage = 12 }, -- End = ASSUMPTION
	Range = 400, -- ASSUMPTION

	-- Firing & reload
	FireRate = 10, -- 0.10s interval
	MagSize = 30,
	ReserveAmmo = 120,
	ReloadTime = 2.0,

	-- Ballistics & recoil
	Spread = {
		Base = 0.5,
		Max = 2.2,
		PerShot = 0.17, -- ASSUMPTION: reaches Max after ~10 rounds
		Recovery = 6, -- ASSUMPTION: degrees/sec back toward Base
	},
	CameraRecoil = { Pitch = 0.45, YawMin = -0.15, YawMax = 0.15, Roll = 0, RecoverySpeed = 18 },
	ViewmodelRecoil = { Z = -0.15, Pitch = 2.5 },

	-- VFX / SFX
	TracerColor = Color3.fromRGB(0, 220, 255),
	TracerLifetime = 0.08,
	MuzzleLight = { Color = Color3.fromRGB(0, 220, 255), Range = 12, Brightness = 4, Duration = 0.05 },
	Sounds = { Fire = "" }, -- punchy metallic crack
}

WeaponConfigs.AegisRail = {
	Id = "AegisRail",
	Name = "Aegis-Rail",
	Archetype = "Hold-to-Charge Heavy Hitscan DMR",
	FireMode = "Charge",
	Automatic = false,

	-- Damage
	Damage = 85, -- fully charged, body
	TapDamage = 25, -- uncharged tap
	HeadshotMultiplier = 2.0, -- 170 charged
	Penetration = { MaxWalls = 2, DamageReductionPerWall = 0.30 }, -- light cover only
	Range = 600, -- ASSUMPTION

	-- Firing & reload
	ChargeTime = 1.2,
	AutoRelease = true, -- fires automatically at 100% charge
	FireRate = 1.5, -- ASSUMPTION: minimum gap between uncharged taps
	MagSize = 5,
	ReserveAmmo = 20,
	ReloadTime = 2.8,

	-- Ballistics & recoil
	Spread = { Grounded = 0.0, Airborne = 3.5 },
	CameraRecoil = { Pitch = 2.2, YawMin = -0.5, YawMax = 0.5, Roll = 0 },
	ViewmodelRecoil = { Z = -0.4, Pitch = 6.0 },

	-- VFX / SFX
	OpticsGlow = {
		From = Color3.fromRGB(90, 40, 160), -- low purple (ASSUMPTION: exact shade)
		To = Color3.fromRGB(255, 255, 255),
		Duration = 1.2,
	},
	DischargeBeam = {
		Thickness = 0.6,
		CoreColor = Color3.fromRGB(255, 255, 255),
		ShellColor = Color3.fromRGB(255, 0, 200), -- magenta
		Decay = 0.25,
	},
	TracerColor = Color3.fromRGB(255, 0, 200),
	Sounds = { Charge = "", Discharge = "" }, -- rising charge pitch, thunderclap discharge
}

WeaponConfigs.ChronoSticky = {
	Id = "ChronoSticky",
	Name = "Chrono-Sticky",
	Archetype = "Arced Physical Projectile Sticky Launcher",
	FireMode = "Projectile",
	Automatic = false,

	-- Damage
	Damage = 10, -- direct impact
	HeadshotMultiplier = 1.0,
	Blast = {
		MaxDamage = 75,
		FullDamageRadius = 4, -- 75 within 0-4 studs
		Radius = 14, -- falls linearly to MinDamage at 14
		MinDamage = 15,
		LatchMultiplier = 1.25, -- stuck to an enemy: 93.75 max
	},
	Range = 300, -- ASSUMPTION: projectile despawn distance

	-- Firing & reload
	FireRate = 1.8, -- 0.55s interval
	MagSize = 4,
	ReserveAmmo = 16,
	ReloadTime = 2.4,
	Fuse = 2.5,
	ManualDetonateInput = Enum.UserInputType.MouseButton2,
	MaxActive = 3, -- per player

	-- Ballistics & recoil
	Projectile = {
		Speed = 140,
		Gravity = Vector3.new(0, -35, 0),
		CastRadius = 0.4, -- ASSUMPTION: shape-cast sphere radius
	},
	CameraRecoil = { Pitch = 0.8, YawMin = 0.3, YawMax = 0.3, Roll = 0 },

	-- VFX / SFX
	LedColors = {
		Hostile = Color3.fromRGB(255, 40, 40),
		Friendly = Color3.fromRGB(40, 120, 255),
	},
	TickRatesHz = { 1, 4, 12 }, -- accelerating, then explosion
	Shockwave = { Radius = 14 }, -- expands to 14, snaps inward with glass-shatter particles
	TracerColor = Color3.fromRGB(255, 120, 40),
	Sounds = { Tick = "", Explosion = "" },
}

WeaponConfigs.TemporalSMG = {
	Id = "TemporalSMG",
	Name = "Temporal-SMG",
	Archetype = "Ultra-Fast Cycling Compact SMG",
	FireMode = "Hitscan",
	Automatic = true,

	-- Damage
	Damage = 11,
	HeadshotMultiplier = 1.4, -- 15.4
	Falloff = { Start = 35, End = 80, MinDamage = 5 },
	Range = 200, -- ASSUMPTION

	-- Firing & reload
	FireRate = 18, -- 0.055s interval
	MagSize = 40,
	ReserveAmmo = 160,
	ReloadTime = 1.5,

	-- Ballistics & recoil
	Spread = {
		Base = 0.8,
		Max = 4.2,
		BurstShots = 3, -- first 3 rounds stay at Base
		PerShot = 0.25, -- ASSUMPTION
		Recovery = 8, -- ASSUMPTION
	},
	CameraRecoil = { Pitch = 0.18, YawMin = -0.35, YawMax = 0.35, Roll = 0, Continuous = true },

	-- VFX / SFX
	StrobeMuzzleFlash = true,
	CasingEjection = "Right",
	TracerColor = Color3.fromRGB(255, 220, 120),
	Sounds = { Fire = "" }, -- rapid metallic rattle
}

return WeaponConfigs
