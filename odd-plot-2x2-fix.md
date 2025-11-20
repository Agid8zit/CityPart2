# City Builder – Odd-Plot Multi‑Tile Placement Fix (2×2 misalignment)

**Purpose:** Fix misaligned building placement on *odd* plots (where grid axes are flipped). The bug shows up on multi‑tile footprints (e.g., 2×2) because world‑space offsets are always added in the +X/+Z directions, ignoring the plot’s axis directions.

This markdown gives Codex/automation a precise set of changes (copy/paste patches) plus a test checklist.

---

## TL;DR: What to change

1) **Server – `BuildingGeneratorModule.generateBuilding`**  
   Make the final world position of Stage 3 **axis‑aware** by multiplying the `(w-1)/2` and `(d-1)/2` cell offsets by the plot’s axis directions.

2) **Client – `GridVisualizer` ghost positioning**  
   Do the same axis‑aware offset so the ghost model lines up with the highlighted footprint on odd plots.

---

## Background (root cause)

- You already convert a *single* grid cell to world with:
  ```lua
  GridUtil.globalGridToWorldPosition(gx, gz, globalBounds, terrains)
  ```
  That function respects the plot’s axis (`GridConfig.getAxisDirections…`).

- For multi‑tile footprints, the code then shifts the model center by always adding a positive offset in world space:
  ```lua
  + ((width - 1) * GRID_SIZE * 0.5) along X
  + ((depth - 1) * GRID_SIZE * 0.5) along Z
  ```

- On **odd plots** (axis dir `-1` on X and/or Z), those offsets should go **negative** in world space. Otherwise the model center lands one cell off (2×2 looks “slid” toward +X/+Z). 1×1 never shows it because the offset is zero.

---

## 1) SERVER PATCH — `BuildingGeneratorModule.generateBuilding(...)`

**File:** `Build/.../BuildingGeneratorModule.lua`  
**Function:** `BuildingGeneratorModule.generateBuilding`  
**Section:** “Compute building's world position”

> **Replace the entire block below** (your current version):
```lua
-- Compute building's world position
local cellCenterX, _, cellCenterZ =
	GridUtils.globalGridToWorldPosition(gridCoord.x, gridCoord.z, gBounds, gTerrains)

local topLeftWorldX = cellCenterX - (GRID_SIZE / 2)
local topLeftWorldZ = cellCenterZ - (GRID_SIZE / 2)

local buildingWidthWorld  = rotatedWidth * GRID_SIZE
local buildingDepthWorld  = rotatedDepth * GRID_SIZE
local halfWidthWorld      = buildingWidthWorld * 0.5
local halfDepthWorld      = buildingDepthWorld * 0.5

local finalPosition = Vector3.new(
	topLeftWorldX + halfWidthWorld,
	terrainPos.Y + (terrainSize.Y / 2) + 0.1 + Y_OFFSET,
	topLeftWorldZ + halfDepthWorld
)
```

> **With this axis‑aware version:**
```lua
-- Compute building's world position (AXIS-AWARE)
local cellCenterX, _, cellCenterZ =
	GridUtils.globalGridToWorldPosition(gridCoord.x, gridCoord.z, gBounds, gTerrains)

-- Respect the per-plot axis so multi-tile footprints expand "forward"
-- in grid space even on odd plots.
local ax, az = 1, 1
if type(gTerrains) == "table" then
	for _, inst in ipairs(gTerrains) do
		if typeof(inst) == "Instance" then
			ax, az = GridConfig.getAxisDirectionsForInstance(inst)
			break
		end
	end
end

local offsetX = ax * ((rotatedWidth  - 1) * GRID_SIZE * 0.5)
local offsetZ = az * ((rotatedDepth - 1) * GRID_SIZE * 0.5)

local finalPosition = Vector3.new(
	cellCenterX + offsetX,
	terrainPos.Y + (terrainSize.Y / 2) + 0.1 + Y_OFFSET,
	cellCenterZ + offsetZ
)
```

**Why this is correct:**  
The model center for a `w×d` footprint is the origin cell center plus `((w-1)/2, (d-1)/2)` **in grid space**. Multiplying by `ax, az` maps those grid deltas to the correct world‑space direction for the plot.

> ✅ No other server changes needed. Stage‑1 previews already call `globalGridToWorldPosition` per cell; occupancy/quadtree use grid coords and were correct.

---

## 2) CLIENT PATCH — Ghost model in `GridVisualizer`

**File:** `Client/.../GridVisualizer.client.lua` (the file containing `startGhostMovement`)  
**Function:** `startGhostMovement()`

> **Find this code:**
```lua
local offX = (w - 1) * GRID_SIZE * 0.5
local offZ = (d - 1) * GRID_SIZE * 0.5
local pivotOffset = CFrame.new(offX, 0, offZ)
```
> **Replace with axis‑aware offset:**
```lua
local ax, az = GridConfig.getAxisDirectionsForPlot(playerPlot) -- same source used when drawing the grid
local offX = ax * (w - 1) * GRID_SIZE * 0.5
local offZ = az * (d - 1) * GRID_SIZE * 0.5
local pivotOffset = CFrame.new(offX, 0, offZ)
```

Everything else (using `GridUtil.globalGridToWorldPosition` for the anchor cell; swapping `w/d` when rotation is 90°/270°) remains unchanged.

---

## Optional (keep for future refactoring)

If you touch this math in other places, consider helper utilities to make intent obvious and avoid regressions:

```lua
local function axisDirsForTerrains(terrains)
	local ax, az = 1, 1
	if type(terrains) == "table" then
		for _, inst in ipairs(terrains) do
			if typeof(inst) == "Instance" then
				return GridConfig.getAxisDirectionsForInstance(inst)
			end
		end
	end
	return ax, az
end

local function worldCenterForFootprint(gx, gz, w, d, bounds, terrains)
	local cx, _, cz = GridUtil.globalGridToWorldPosition(gx, gz, bounds, terrains)
	local ax, az = axisDirsForTerrains(terrains)
	return Vector3.new(
		cx + ax * ((w - 1) * GRID_SIZE * 0.5),
		nil, -- caller fills Y
		cz + az * ((d - 1) * GRID_SIZE * 0.5)
	)
end
```

---

## Test checklist

Use both **even** and **odd** plots (e.g., `GridAxisDirX = 1, GridAxisDirZ = 1` vs `-1, -1`).

1. **2×2, rotation 0°/180°**  
   Ghost squares, ghost model, and final placed model occupy exactly the 4 highlighted cells.

2. **2×2, rotation 90°/270°**  
   Center stays between the same 4 cells; no 1‑cell slide.

3. **1×1**  
   No change (always correct).

4. **Larger footprints (e.g., 3×2)**  
   Ends fall on the correct grid cells on both plot parities.

---

## FAQ

- **Why didn’t 1×1 fail?**  
  Because `(w-1)` and `(d-1)` are zero ⇒ the (incorrect) offset was zero.
  
- **Do I need to change highlighting or reservations?**  
  No. Highlighting uses logical grid indices; reservations/occupancy/quadtree also operate in grid space and were already correct.

- **Any caveats with PrimaryPart pivots?**  
  The fix assumes Stage‑3 `PrimaryPart.Size` matches the grid footprint you computed (as your code already does). If some prefabs have an off‑center pivot, fix the prefab rather than compensating here.

---

## Credits / Context

- Modules involved: `BuildingGeneratorModule.lua`, `GridUtil.lua`, `GridVisualizer.client.lua`
- Root cause: world‑space offset ignored plot axis directions on odd plots.
- Fix: multiply multi‑tile center offset by plot axis (`ax, az`).

