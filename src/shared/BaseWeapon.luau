--!nonstrict
-- BaseWeapon: ammo, reload timing, fire-rate throttling and state for any weapon.
-- Used identically on the client (prediction) and the server (authority).
--
-- States:  Idle (holstered)  ->  Equipped (ready)  <->  Reloading

export type Config = {
	Name: string,
	MagSize: number,
	ReserveAmmo: number,
	FireRate: number, -- rounds per second
	ReloadTime: number, -- seconds
	Damage: number,
	HeadshotMultiplier: number,
	Range: number,
	Automatic: boolean,
	TracerColor: Color3?,
}

export type Options = {
	-- Fraction (0..1) shaved off fire interval / reload time. The server uses this
	-- so network jitter never makes it stricter than the predicting client.
	FireTolerance: number?,
	ReloadTolerance: number?,
}

local BaseWeapon = {}
BaseWeapon.__index = BaseWeapon

BaseWeapon.States = {
	Idle = "Idle",
	Equipped = "Equipped",
	Reloading = "Reloading",
}

function BaseWeapon.new(config: Config, options: Options?)
	local self = setmetatable({}, BaseWeapon)

	self.Config = config
	self.State = "Idle"
	self.Mag = config.MagSize
	self.Reserve = config.ReserveAmmo
	self.FireTolerance = options and options.FireTolerance or 0
	self.ReloadTolerance = options and options.ReloadTolerance or 0

	self._lastFire = -math.huge
	self._reloadToken = 0
	self._destroyed = false

	self._stateChanged = Instance.new("BindableEvent")
	self._ammoChanged = Instance.new("BindableEvent")
	self.StateChanged = self._stateChanged.Event -- (newState, oldState)
	self.AmmoChanged = self._ammoChanged.Event -- (mag, reserve)

	return self
end

function BaseWeapon:_setState(newState: string)
	local old = self.State
	if old == newState then
		return
	end
	self.State = newState
	self._stateChanged:Fire(newState, old)
end

function BaseWeapon:_fireAmmoChanged()
	self._ammoChanged:Fire(self.Mag, self.Reserve)
end

function BaseWeapon:IsEquipped(): boolean
	return self.State ~= "Idle"
end

function BaseWeapon:Equip()
	if self._destroyed or self.State ~= "Idle" then
		return
	end
	self:_setState("Equipped")
	-- A reload cancelled by holstering on an empty mag would otherwise leave the
	-- weapon equipped, empty and never auto-reloading.
	if self.Mag == 0 then
		self:Reload()
	end
end

function BaseWeapon:Unequip()
	if self.State == "Idle" then
		return
	end
	self._reloadToken += 1 -- cancels any reload in flight
	self:_setState("Idle")
end

-- Returns ok, reason ("NotEquipped" | "Reloading" | "Empty" | "Throttled").
function BaseWeapon:CanFire(): (boolean, string?)
	if self.State == "Idle" then
		return false, "NotEquipped"
	end
	if self.State == "Reloading" then
		return false, "Reloading"
	end
	if self.Mag <= 0 then
		return false, "Empty"
	end
	local interval = 1 / self.Config.FireRate
	if os.clock() - self._lastFire < interval * (1 - self.FireTolerance) then
		return false, "Throttled"
	end
	return true
end

-- Consumes one round if allowed. Auto-reloads when the magazine runs dry.
function BaseWeapon:Fire(): (boolean, string?)
	local ok, reason = self:CanFire()
	if not ok then
		return false, reason
	end

	self._lastFire = os.clock()
	self.Mag -= 1
	self:_fireAmmoChanged()

	if self.Mag == 0 then
		self:Reload()
	end
	return true
end

function BaseWeapon:CanReload(): boolean
	return self.State == "Equipped" and self.Mag < self.Config.MagSize and self.Reserve > 0
end

function BaseWeapon:Reload(): boolean
	if not self:CanReload() then
		return false
	end

	self._reloadToken += 1
	local token = self._reloadToken
	self:_setState("Reloading")

	task.delay(self.Config.ReloadTime * (1 - self.ReloadTolerance), function()
		if self._destroyed or self._reloadToken ~= token or self.State ~= "Reloading" then
			return
		end
		local taken = math.min(self.Config.MagSize - self.Mag, self.Reserve)
		self.Mag += taken
		self.Reserve -= taken
		self:_fireAmmoChanged()
		self:_setState("Equipped")
	end)

	return true
end

-- Authoritative correction from the server.
function BaseWeapon:SetAmmo(mag: number, reserve: number)
	self.Mag = math.clamp(mag, 0, self.Config.MagSize)
	self.Reserve = math.max(reserve, 0)
	self:_fireAmmoChanged()
end

function BaseWeapon:Destroy()
	self._destroyed = true
	self._reloadToken += 1
	self._stateChanged:Destroy()
	self._ammoChanged:Destroy()
end

return BaseWeapon
