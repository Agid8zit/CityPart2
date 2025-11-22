
# TASK DOCUMENT — Normalize Grid Coordinates Across Odd/Even Plots (Roblox Luau)

## Objective
Make the **same world position** produce the **same logical grid coordinates `(x, z)`** on both Odd (180°) and Even (0°/360°) plots.  
Use a **per‑plot axis** (`GridAxisDirX`, `GridAxisDirZ`) so:
- **Odd** plots are canonical: `( +1, +1 )`
- **Even** plots flip both axes: `( −1, −1 )`

Expose **logical** (axis‑normalized) coords on every `GridSquare` via `GridX`/`GridZ`, and ensure all grid→world conversions apply the axis internally.

---

## Files To Modify
1. `ServerScriptService/PlotAssigner.server.lua`
2. `ReplicatedStorage/Scripts/Grid/GridUtil.lua`
3. `StarterPlayerScripts/GridVisualizer.client.lua`

> Do **not** change other files unless a direct grid→world computation is found (see “Server builders audit”).

---

## 1) Server — `ServerScriptService/PlotAssigner.server.lua`

### 1A) Set per‑plot axis (Odd = +1,+1; Even = −1,−1)
**Find this anchor block near plot creation/positioning (text will be similar):**
```lua
-- Determine mirrored orientation: odd-numbered placeholders flip the grid axes
local placeholderNumber = tonumber(placeholder.Name:match("Plot(%d+)")) or 0
local axisDirX = placeholder:GetAttribute("GridAxisDirX")
if axisDirX ~= 1 and axisDirX ~= -1 then
	axisDirX = 1
end

local axisDirZ = placeholder:GetAttribute("GridAxisDirZ")
if axisDirZ ~= 1 and axisDirZ ~= -1 then
	local isOddPlot = (placeholderNumber % 2 == 1)
	axisDirZ = isOddPlot and -1 or 1
end

playerPlot:SetAttribute("GridAxisDirX", axisDirX)
playerPlot:SetAttribute("GridAxisDirZ", axisDirZ)
GridConfig.setAxisDirectionsForPlot(playerPlot, axisDirX, axisDirZ)
```

**Replace that whole block with:**
```lua
-- Determine axis directions so Odd is canonical (+1,+1) and Even flips to align logically (-1,-1)
local placeholderNumber = tonumber(placeholder.Name:match("Plot(%d+)")) or 0
local isOddPlot = (placeholderNumber % 2 == 1)

local axisDirX = placeholder:GetAttribute("GridAxisDirX")
if axisDirX ~= 1 and axisDirX ~= -1 then
	axisDirX = isOddPlot and 1 or -1
end

local axisDirZ = placeholder:GetAttribute("GridAxisDirZ")
if axisDirZ ~= 1 and axisDirZ ~= -1 then
	axisDirZ = isOddPlot and 1 or -1
end

playerPlot:SetAttribute("GridAxisDirX", axisDirX)
playerPlot:SetAttribute("GridAxisDirZ", axisDirZ)
GridConfig.setAxisDirectionsForPlot(playerPlot, axisDirX, axisDirZ)
```

### 1B) (If present) Ensure Odd/Even attributes match orientation
**Find function `setPlotOddEvenAttributes(plotModel)` and replace its body with:**
```lua
local function setPlotOddEvenAttributes(plotModel: Model?)
	if not plotModel then return end
	local primaryPart = plotModel.PrimaryPart
	if not primaryPart then return end

	local orientationY = primaryPart.Orientation.Y % 360
	if orientationY < 0 then orientationY += 360 end

	local tolerance = 1e-3
	-- 180° => Odd, 0°/360° => Even
	local isOddOrientation  = math.abs(orientationY - 180) <= tolerance
	local isEvenOrientation = (orientationY <= tolerance) or (orientationY >= (360 - tolerance))

	plotModel:SetAttribute("Odd",  isOddOrientation)
	plotModel:SetAttribute("Even", isEvenOrientation)
end
```

*(Parity labels don’t affect math, but keep them correct.)*

---

## 2) Shared — `ReplicatedStorage/Scripts/Grid/GridUtil.lua`

**Replace the entire function `GridUtil.globalGridToWorldPosition` with:**
```lua
function GridUtil.globalGridToWorldPosition(gridX, gridZ, globalBounds, terrains)
	-- Get per-plot axis from any terrain instance; fallback to (1,1)
	local axisDirX, axisDirZ = 1, 1
	if type(terrains) == "table" then
		for _, inst in ipairs(terrains) do
			if typeof(inst) == "Instance" then
				axisDirX, axisDirZ = GridConfig.getAxisDirectionsForInstance(inst)
				break
			end
		end
	end

	-- Interpret incoming (gridX, gridZ) as LOGICAL indices.
	-- Convert to effective raw indices by applying the per-plot axis.
	local effGX = (axisDirX or 1) * (gridX or 0)
	local effGZ = (axisDirZ or 1) * (gridZ or 0)

	local worldX = globalBounds.minX + (effGX + 0.5) * GridConfig.GRID_SIZE
	local worldZ = globalBounds.minZ + (effGZ + 0.5) * GridConfig.GRID_SIZE
	local worldY

	for _, terrain in ipairs(terrains) do
		local tMinX, tMinZ = GridConfig.calculateCoords(terrain)
		local tMaxX = tMinX + terrain.Size.X
		local tMaxZ = tMinZ + terrain.Size.Z
		if worldX >= tMinX and worldX <= tMaxX and worldZ >= tMinZ and worldZ <= tMaxZ then
			worldY = terrain.Position.Y + (terrain.Size.Y / 2) + GridConfig.Y_OFFSET
			break
		end
	end

	if not worldY then
		worldY = GridConfig.Y_OFFSET
	end
	return worldX, worldY, worldZ
end
```

*(Optional mirror if needed later):*
```lua
function GridUtil.worldToGlobalGridPosition(worldPosition, globalBounds, terrains)
	local axisDirX, axisDirZ = 1, 1
	if type(terrains) == "table" then
		for _, inst in ipairs(terrains) do
			if typeof(inst) == "Instance" then
				axisDirX, axisDirZ = GridConfig.getAxisDirectionsForInstance(inst)
				break
			end
		end
	end
	local rawGX = math.floor((worldPosition.X - globalBounds.minX) / GridConfig.GRID_SIZE)
	local rawGZ = math.floor((worldPosition.Z - globalBounds.minZ) / GridConfig.GRID_SIZE)
	return rawGX * (axisDirX or 1), rawGZ * (axisDirZ or 1)
end
```

---

## 3) Client — `StarterPlayerScripts/GridVisualizer.client.lua`

### 3A) Seed axis on plot assignment
**Find inside `plotAssignedEvent.OnClientEvent`:**
```lua
playerPlot = plot
print("GridVisualizer: Found plot", playerPlot.Name)
findMetroEntrances()
```
**Immediately after `findMetroEntrances()`, insert:**
```lua
-- Seed per-plot axis (Odd = +1,+1, Even = -1,-1)
local ax = playerPlot:GetAttribute("GridAxisDirX") or 1
local az = playerPlot:GetAttribute("GridAxisDirZ") or 1
GridConfig.setAxisDirectionsForPlot(playerPlot, ax, az)
```

### 3B) Emit **logical** indices in `createGrid(mode)`
**After this line near the top of `createGrid`:**
```lua
local gridFolder = workspace.PlayerPlots.GridParts
```
**Add:**
```lua
-- Logical axis for this plot
local ax, az = GridConfig.getAxisDirectionsForPlot(playerPlot)
```

**Inside the nested `for i` / `for j` loops, replace the block that computes indices and sets attributes with:**
```lua
-- Raw indices relative to the stable anchor
local rawGX = math.floor((worldX - anchorMinX) / step)
local rawGZ = math.floor((worldZ - anchorMinZ) / step)

-- Logical, parity-aligned indices exposed to UI/placement
local gridX = rawGX * (ax or 1)
local gridZ = rawGZ * (az or 1)

-- Place using logical indices; GridUtil handles axis internally
local finalWorldX, finalWorldY, finalWorldZ =
	GridUtil.globalGridToWorldPosition(gridX, gridZ, globalBounds, terrains)

gridPart:SetAttribute("GridX", gridX) -- logical
gridPart:SetAttribute("GridZ", gridZ) -- logical
gridLookup[gridX .. "," .. gridZ] = gridPart
```

### 3C) Cardinal preview: bound check in raw while stepping in logical
**In `showCardinalGrids(startCoord)` after you compute:**
```lua
local minGridX = math.floor((globalBounds.absMinX - globalBounds.minX) / step)
local maxGridX = math.floor((globalBounds.maxX - globalBounds.minX) / step)
local minGridZ = math.floor((globalBounds.absMinZ - globalBounds.minZ) / step)
local maxGridZ = math.floor((globalBounds.maxZ - globalBounds.minZ) / step)
```
**Insert:**
```lua
local ax, az = GridConfig.getAxisDirectionsForPlot(playerPlot)
```
**Inside the stepping `while true do`, replace the bounds check with:**
```lua
-- Compare against RAW bounds by un-orienting the logical indices
local rx = x * (ax or 1)
local rz = z * (az or 1)
if rx < minGridX or rx > maxGridX or rz < minGridZ or rz > maxGridZ then
	break
end
```
*(Continue to call `GridUtil.globalGridToWorldPosition(x, z, globalBounds, terrains)` with logical `x,z`.)*

---

## 4) (Audit) Server builders/command handlers
**Search** server‑side code for **direct grid→world math** like:
```lua
local worldX = minX + (gridX + 0.5) * GRID_SIZE
local worldZ = minZ + (gridZ + 0.5) * GRID_SIZE
```
**Replace** such computations with:
```lua
local worldX, worldY, worldZ = GridUtil.globalGridToWorldPosition(gridX, gridZ, globalBounds, terrainsForThisPlot)
```
> Ensure `globalBounds` and `terrainsForThisPlot` refer to the **player’s plot**.

---

## Acceptance Checks
- Clicking the **same world spot** on an Odd and an Even plot returns the **same** `GridX, GridZ` from the `GridSquare` clicked.
- Building a short road along +Z on Odd and on Even extends in the **same world direction** and uses the same budget.
- Server‑spawned parts land at the correct world positions (i.e., server uses `GridUtil.globalGridToWorldPosition`).

---

## Commit Message (suggested)
```
Normalize grid coords across Odd/Even plots

- Server: set per-plot axis (Odd=(+1,+1), Even=(-1,-1))
- Client: seed axis on plot assignment
- GridUtil: treat (gridX,gridZ) as logical; apply axis in grid->world
- GridVisualizer: emit logical GridX/GridZ; axis-aware placement; cardinal bounds in raw
- Builders audit: route grid->world through GridUtil
- Parity tags: 180°=Odd, 0°/360°=Even
```
