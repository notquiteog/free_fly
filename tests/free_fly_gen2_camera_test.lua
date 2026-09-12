-- The flight camera on a Gen 2 boot.
--
-- Flight itself always worked on Gold: takeoff is accepted, isFlying goes
-- true, the altitude ramps to cruise. What did not work was the VIEW, and it
-- failed silently in two places that have to be fixed together.
--
-- The mod raises the camera two different ways, and which one it uses is a
-- property of the rung. Rungs 15/35/50 get height indirectly, by moving the
-- engine's ground-plane camera point back by camLift; only the 75-degree
-- orbit needs the scene's placed-camera seam, because there the camera is
-- nearly overhead and moving the ground point buys nothing.
--
-- On Gold the indirect route does not exist. The camera follow is skipped
-- there deliberately -- Gold's World:update drives its own camera every
-- frame and would overwrite anything set here -- so with the placed seam
-- gated to `deg == 75`, NO rung got any lift. A Crystal boot at the default
-- FULL rung showed the rider climbing toward a camera that never backed
-- off: a very large trainer standing on the grass, with the world behind
-- them unchanged.
--
-- And the placed block could not have worked even at 75, because it read the
-- view size from `Game.renderer:worldViewSize()`. Gold has no Renderer
-- singleton. Inside the block's pcall that raised, the pcall swallowed it,
-- and `state.placeWanted` was then set to false for the rest of the flight
-- -- so the failure was not merely silent, it was sticky.
--
-- Measured on a real Crystal boot, mid-flight at the FULL rung:
--   before   Voxel3D.camera = nil
--   after    Voxel3D.camera = table
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local MOD_DIR = os.getenv("MOD_DIR") or "mods/free_fly"
local Sky = assert(loadfile(MOD_DIR .. "/lib/shared/skylib.lua"))()

-- ------- the helper the fix routes through, on both world shapes
--
-- Gold's World carries viewW/viewH (src/world/gen2/World.lua) and `stepBody`
-- is what Sky.goldWorld recognises it by.
local gold = { stepBody = function() end, viewW = 320, viewH = 288 }
local vw, vh = Sky.viewSize({ renderer = nil }, gold)
T.eq(vw, 320, "a Gold world answers its own viewW")
T.eq(vh, 288, "a Gold world answers its own viewH")

-- before the first frame has drawn, viewW/viewH are unset; the GB screen is
-- the answer rather than a nil that propagates into camera arithmetic
local cold = { stepBody = function() end }
local cw, ch = Sky.viewSize({ renderer = nil }, cold)
T.eq(cw, 160, "a Gold world with no frame yet falls back to the GB width")
T.eq(ch, 144, "a Gold world with no frame yet falls back to the GB height")

-- Gen 1 still goes through the renderer, which is the only place that knows
local gen1ow = {}
local renderer = { worldViewSize = function() return 480, 432 end }
local rw, rh = Sky.viewSize({ renderer = renderer }, gen1ow)
T.eq(rw, 480, "a Gen 1 world still reads the renderer's world view size")
T.eq(rh, 432, "and its height")

-- ------- the two call sites
--
-- Anchored inside the placed-camera block rather than matched anywhere in
-- the file: a test that only asked "does main.lua contain Sky.viewSize"
-- would pass on a build where the block still read Game.renderer, because
-- the helper is used elsewhere too.
local source = assert(io.open(MOD_DIR .. "/main.lua")):read("*a")

-- Comments are stripped before any of this is searched, and that is not
-- tidiness: the first run of this case failed on its own explanatory
-- comment, which names Game.renderer in order to say the block no longer
-- reads it. A guard that a comment can satisfy -- or break -- is measuring
-- prose, not code.
local function codeOnly(text)
  return (text:gsub("%-%-[^\n]*", ""))
end

local placed = codeOnly(source):match("if state%.placeWanted.-\n      end")
T.check(placed ~= nil, "the placed-camera block is still recognisable")
if placed then
  T.check(placed:find("Sky.viewSize", 1, true) ~= nil,
    "the placed camera reads the view size through Sky.viewSize")
  T.check(placed:find("Game.renderer", 1, true) == nil,
    "the placed camera does NOT read Game.renderer, which is nil on Gold")
end

local wanted = codeOnly(source):match("state%.placeWanted = .-\n        state%.placeHeight")
T.check(wanted ~= nil, "the placeWanted decision is still recognisable")
if wanted then
  T.check(wanted:find("goldWorld", 1, true) ~= nil,
    "placeWanted asks whether this is a Gold world -- there the placed "
      .. "camera is the only lift there is, at every orbit rung")
  T.check(wanted:find("75", 1, true) ~= nil,
    "and Gen 1 still reserves it for the 75-degree orbit")
end

T.finish("free_fly gen2 camera")
