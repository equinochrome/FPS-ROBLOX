-- The match map is built by ProceduralMapGenerator (a sibling Script), which also
-- populates the courtyard dummies. MapBuilder (the static Neo-Tokyo Plaza) is kept
-- in the repo but no longer loaded.
local RewindService = require(script.RewindService)
local StasisService = require(script.StasisService)
local WeaponService = require(script.WeaponService)

StasisService.Init()
RewindService.Init()
WeaponService.Init()
