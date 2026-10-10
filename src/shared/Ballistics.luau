--!strict
-- Shared hitscan math used by both client prediction and server validation.

local Ballistics = {}

-- Damage after distance falloff: full damage up to Falloff.Start, linear down to
-- Falloff.MinDamage at Falloff.End, flat beyond. Weapons without Falloff are unaffected.
function Ballistics.Falloff(config: any, baseDamage: number, distance: number): number
	local f = config.Falloff
	if not f or distance <= f.Start then
		return baseDamage
	end
	if distance >= f.End then
		return f.MinDamage
	end
	local alpha = (distance - f.Start) / (f.End - f.Start)
	return baseDamage + (f.MinDamage - baseDamage) * alpha
end

-- Random direction inside a cone of `degrees` half-angle around `direction`,
-- uniformly distributed over the cone's cross-section.
function Ballistics.ApplySpread(direction: Vector3, degrees: number): Vector3
	if degrees <= 0 then
		return direction.Unit
	end
	local angle = math.rad(degrees) * math.sqrt(math.random())
	local roll = math.random() * 2 * math.pi
	local cf = CFrame.lookAt(Vector3.zero, direction) * CFrame.Angles(0, 0, roll) * CFrame.Angles(angle, 0, 0)
	return cf.LookVector
end

-- Distance along a unit-direction ray to where it enters a sphere, or nil if it misses
-- within maxDistance. Rays that start inside the sphere return nil (they're leaving it).
function Ballistics.RaySphere(origin: Vector3, direction: Vector3, center: Vector3, radius: number, maxDistance: number): number?
	local oc = origin - center
	local c = oc:Dot(oc) - radius * radius
	if c <= 0 then
		return nil
	end
	local b = oc:Dot(direction)
	if b > 0 then
		return nil -- outside and pointing away
	end
	local disc = b * b - c
	if disc < 0 then
		return nil
	end
	local t = -b - math.sqrt(disc)
	if t > maxDistance then
		return nil
	end
	return t
end

return Ballistics
