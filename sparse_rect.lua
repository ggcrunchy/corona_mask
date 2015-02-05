--- Generators for masks based on marching squares.
 
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--
-- [ MIT license: http://www.opensource.org/licenses/mit-license.php ]
--

-- Standard library imports --
local ipairs = ipairs

-- Modules --
local require_ex = require("tektite_core.require_ex")
local gray = require_ex.Lazy("number_sequences.gray")
local log2 = require_ex.Lazy("bitwise_ops.log2")

-- Cached module references --
local _NewReel_

-- Exports --
local M = {}

--- DOCME
function M.NewGrid (get_object, dim, w, h, ncols, nrows, opts)
	local reel, clear, full = _NewReel_(dim, w / ncols, h / nrows, opts)--, Clear, Full

	--
end

--[=[
-- TILES, GENERATED BY BUILD TILES --
local Tiles = FROM

-- Tile count --
local NumTiles = #Tiles

-- Largest tile mask; count of mask bits; index of "full" tile --
local Mask, NumBits, FullIndex = 1, 1

-- Find the "full" tile, invert the array, and compute the mask.
do
	local full = -1

	for i = NumTiles, 1, -1 do
		local tile = Tiles[i]

		if tile > full then
			FullIndex, full = i, tile
		end

		Tiles[tile], Tiles[i] = i
	end

	repeat
		Mask, NumBits = Mask + Mask, NumBits + 1
	until Mask + Mask > full
end

-- --
local CellCache = {}

-- --
local Dirty = setmetatable({}, {
	__index = function(t, k)
		local new = remove(CellCache) or {}

		rawset(t, k, new)

		return new
	end
})

-- --
local DirtyN

--- DOCME
function M.GetCell ()
	DirtyN = DirtyN + 1

	return Dirty[DirtyN]
end

--- DOCME
function M.GetNumTiles ()
	return NumTiles
end

-- --
local Bx

--- DOCME
function M.Init (bx, by)
	Bx = bx
end

-- --
local Blocks = {}

--- DOCME
function M.NewImage (image, x, y, w, h, col, row)
	image:setFrame(FullIndex)

	image.x, image.y = x + 8, y + 8
	image.width, image.height = w, h

	if row > 0 then
		Blocks[#Blocks + 1] = { col = (col - 1) * 4 + 1, row = (row - 1) * 4 + 1, flags = (Mask + Mask) - 1, image = image }
	end
end

-- --
local BlocksProcessed = {}

-- --
local Workspace = {}

--
local function PrepWorkspace (flags)
	local mask = Mask

	for i = NumBits, 1, -1 do
		if flags >= mask then
			Workspace[i], flags = true, flags - mask
		else
			Workspace[i] = false
		end

		mask = .5 * mask
	end

	return true
end

--- DOCME
function M.UpdateBlocks ()
	-- Order the list, for easy detection of duplicates.
	sort(BlocksProcessed)

	-- Update the images belonging to each affected block.
	local prev_block

	for i = #BlocksProcessed, 1, -1 do
		local block_index = BlocksProcessed[i]

		if block_index ~= prev_block then
			local block = Blocks[block_index]
			local flags, image, prepped = block.flags, block.image

			-- Decompose the block until it matches a tile.
			while not Tiles[flags] and flags ~= 0 do
				local flag, index = 1, 1

				-- On the first iteration, prep the workspace. Reset the flags, which will be
				-- built up over this iteration.
				flags, prepped = 0, prepped or PrepWorkspace(flags)

				-- Remove any thin strips.
				for row = 1, 4 do
					for col = 1, 4 do
						if Workspace[index] then
							local passed, lcheck, rcheck = Workspace[index - 4] or Workspace[index + 4]

							if passed then
								lcheck = col > 1 and Workspace[index - 1]
								rcheck = col < 4 and Workspace[index + 1]
							end

							if passed and (lcheck or rcheck) then
								flags = flags + flag
							else
								Workspace[index] = false
							end
						end

						flag, index = flag + flag, index + 1
					end
				end
			end

			-- Update the tile acoording to the new block flags.
			block.flags = flags

			if flags > 0 then
				image.isVisible = true

				image:setFrame(Tiles[flags])
				image.width = 16
				image.height = 16
			else
				image.isVisible = false
			end

			prev_block = block_index
		end

		BlocksProcessed[i] = nil
	end
end

-- Cache any excess cells left over from previous processing
local function CacheExcess ()
	for i = #Dirty, DirtyN + 1, -1 do
		CellCache[#CellCache + 1], Dirty[i] = Dirty[i]
	end
end

--
local function IndexComp (a, b)
	return a.index < b.index
end

--
local function OnAcquireBlock_Func (block_index, func)
	func("block", block_index)
end

--
local function OnAcquireBlock_Process (block_index)
	BlocksProcessed[#BlocksProcessed + 1] = block_index
end

--
local function GetFlagsAndCheck (block, NON)
	local flags = block.flags

	if NON then
		return flags, block.NON_flags or 0
	else
		return flags, flags
	end
end

--
local function IsFilled (flags, fmask)
	return flags % (fmask + fmask) >= fmask
end

--
local function OnCell_Fill (block, col, row, fmask, NON)
	local flags, check = GetFlagsAndCheck(block, NON)

	if not IsFilled(check, fmask) then
		block.flags = flags + fmask

		if NON then
			block.NON_flags = check + fmask
		end
	end
end

--
local function OnCell_Func (block, col, row, fmask, func)
	func("cell", col, row, IsFilled(block.flags, fmask))
end

--
local function OnCell_Wipe (block, col, row, fmask, NON)
	local flags, check = GetFlagsAndCheck(block, NON)

	--
	if IsFilled(check, fmask) then
		block.flags = flags - fmask

		if NON then
			block.NON_flags = check - fmask
		else
			poof.DoPoof(col, row)
		end
	end
end

--- DOCME
function M.VisitCells (how, arg)
	CacheExcess()

	-- Order the list, for easy detection of duplicates.
	sort(Dirty, IndexComp)

	-- Choose the appropriate operations and argument.
	local on_acquire_block, on_cell

	if how == "fill" or how == "wipe" then
		on_acquire_block = OnAcquireBlock_Process
		on_cell = how == "fill" and OnCell_Fill or OnCell_Wipe
	else
		on_acquire_block, on_cell, arg = OnAcquireBlock_Func, OnCell_Func, how
	end

	-- Visit each unique index and compact the list.
	local clo, rlo, chi, rhi, block, prev = 0, 0, -1, -1

	for _, cell in ipairs(Dirty) do
		local index = cell.index

		if index ~= prev then
			local col, row = cell.col, cell.row

			--
			if col < clo or col > chi or row < rlo or row > rhi then
				local bcol, brow = floor(.25 * col - .25), floor(.25 * row - .25)

				clo, rlo = bcol * 4 + 1, brow * 4 + 1
				chi, rhi = clo + 3, rlo + 3

				local block_index = brow * Bx + bcol + 1

				block = Blocks[block_index]

				on_acquire_block(block_index, arg)
			end

			--
			on_cell(block, col, row, ldexp(1, (row - rlo) * 4 + (col - clo)), arg)

			prev = index
		end
	end
end

]=]

--- DOCME
function M.NewReel (dim, ncols, nrows)
    -- Start with an unmarked board. For fast lookup, store the neighbor indices; account
    -- for the borders by pointing to a dummy unmarked tile.
	local in_use, neighbors, index = { [false] = false }, {}, 1

    for row = 1, nrows do
        local above, below = row > 1, row < nrows

        for col = 1, ncols do
            in_use[index], neighbors[index] = false, {
                up = above and index - ncols,
                left = col > 1 and index - 1,
                right = col < ncols and index + 1,
                down = below and index + ncols
            }

            index = index + 1
        end
	end

    -- Checks if a neighbor suddenly broke off from a larger mass, i.e. became a thin strip
    local function CheckBroken (from, dir)
		local next = from[dir]

        return in_use[next] and not in_use[neighbors[next][dir]]
    end

    -- Checks if two neighbors are in use
    local function Check2 (index, dir1, dir2)
        local from = neighbors[index]

        return in_use[from[dir1]] or in_use[from[dir2]]
    end

    -- Try all the possible patterns defined by a bit stream (where each bit represents an
	-- "on" or "off" element), accepting all patterns without "thin strips", i.e. elements
	-- without a neighbor in the horizontal and / or vertical direction. Iterating these
	-- values in Gray code order maintains pattern coherency, simplifying the updates.
    local prev_gray, ok = 0

	for gval, i in gray.FirstN(2 ^ (ncols * nrows), 0) do -- skip 0
--	for i = 1, 2 ^ (ncols * nrows) do -- skip 0
        local diff, skip_test = gval - prev_gray

		-- A bit was added:
		-- If the pattern was intact on the last step, it either remains so (i.e. the new
		-- element coaelesces with a larger region) or, at worst, a one-element thin strip
		-- will be introduced. In either case, no integrity check is needed. If the pattern
		-- is broken, on the other hand, the check proceeds.
        if diff > 0 then
			local added_at = log2.Lg_PowerOf2(diff) + 1

			in_use[added_at] = true

            if ok then
                skip_test = true

                ok = Check2(added_at, "up", "down") and Check2(added_at, "left", "right")
            end

		-- A bit was removed:
		-- Check whether the result left behind a thin strip. If so, the pattern is known to
		-- be broken; we can fail early, forgoing the integrity check.
        else
			local removed_at = log2.Lg_PowerOf2(-diff) + 1

            in_use[removed_at] = false

			local from = neighbors[removed_at]

			if CheckBroken(from, "left") or CheckBroken(from, "right") or CheckBroken(from, "up") or CheckBroken(from, "down") then
				skip_test, ok = true, false
			end
        end

        -- Integrity check: ensure that no thin strips exist. If this is satisfied, the
		-- pattern is considered to be intact.
        if not skip_test then
			ok = true

			for i, used in ipairs(in_use) do
				if used and not (Check2(i, "up", "down") and Check2(i, "left", "right")) then
					ok = false

					break
				end
			end
		end

		-- if ok then
			--

		-- Update Gray code state.
		prev_gray = gval
	end
end

--[=[
--- Functionality used to pregenerate the tile map.

-- Standard library imports --
local format = string.format
local ipairs = ipairs
local popen = io.popen

-- Modules --
local log2 = require("bitwise_ops.log2")

-- Exports --
local M = {}

--
local Dim = 4

--- DOCME
function M.Build (ncols, nrows)
	local xinc, yinc = Dim * ncols + 2, Dim * nrows + 2

    -- Start with an unmarked board. For fast lookup, store the neighbor indices; account
    -- for the borders by pointing to a dummy unmarked tile.
	local in_use, neighbors, index = { [false] = false }, {}, 1

    for row = 1, nrows do
        local above, below = row > 1, row < nrows

        for col = 1, ncols do
            in_use[index], neighbors[index] = false, {
                up = above and index - ncols,
                left = col > 1 and index - 1,
                right = col < ncols and index + 1,
                down = below and index + ncols
            }

            index = index + 1
        end
	end

    --
    local function CheckBroken (from, dir)
		local next = from[dir]

        return in_use[next] and not in_use[neighbors[next][dir]]
    end

    --
    local function Check2 (index, dir1, dir2)
        local from = neighbors[index]

        return in_use[from[dir1]] or in_use[from[dir2]]
    end

	--
	local clipboard = popen("clip", "w")
	local to_save = display.newGroup()

	if clipboard then
		clipboard:write("{")
	end

	--
	local penx, peny, cw, nadded = 0, 0, display.contentWidth, 0
	local ny, nx = 1

    --
    local half, inc, prev_gray, ok = 0, 1, 0

	for i = 1, 2 ^ (ncols * nrows) do -- skip 0
        local gray = 0

	    -- Compute the Gray code.
	    local a, b, arem, flag = i, half, inc, 1

        repeat
	        local brem = b % 2

	        if arem ~= brem then
	            gray = gray + flag
            end	            

	        a, b = .5 * (a - arem), .5 * (b - brem)
	        arem = a % 2
	        flag = flag + flag
	    until a == b

        -- Compare to previous code. If a bit was added, an intact pattern will remain so
		-- if the result does not leave behind a thin strip. In any event, when following
		-- up on an intact pattern, we can forgo the integrity check.
        local diff, skip_test = gray - prev_gray

        if diff > 0 then
			local added_at = log2.Lg_PowerOf2(diff) + 1

			in_use[added_at] = true

            if ok then
                skip_test = true

                ok = Check2(added_at, "up", "down") and Check2(added_at, "left", "right")
            end

		-- If a bit was removed, check whether the result left behind a thin strip. If so, we
		-- can fail early, forgoing the integrity check.
        else
			local removed_at = log2.Lg_PowerOf2(-diff) + 1

            in_use[removed_at] = false

			local from = neighbors[removed_at]

			if CheckBroken(from, "left") or CheckBroken(from, "right") or CheckBroken(from, "up") or CheckBroken(from, "down") then
				skip_test, ok = true, false
			end
        end

        -- Integrity check: ensure that no thin strips exist. (TODO: efficient incremental solutoin? Trouble is there can be MULTIPLE strips...)
        if not skip_test then
			ok = true

			for i, used in ipairs(in_use) do
				if used and not (Check2(i, "up", "down") and Check2(i, "left", "right")) then
					ok = false

					break
				end
			end
		end

        --
        if ok then
			local index, y = 1, 0

			if penx + xinc > cw then
				penx, peny = 0, peny + yinc
				nx, ny = nx or nadded, ny + 1
			end

			for row = 1, nrows do
				local inner_row, x = row > 1 and row < nrows, 0

				for col = 1, ncols do
					if in_use[index] then
						local clod = display.newRect(to_save, penx + x + 1, peny + y + 1, Dim, Dim)
						local around, inner_col, r, g, b = neighbors[index], col > 1 and col < ncols

						if (inner_row and not (in_use[around.up] and in_use[around.down]))
						or (inner_col and not (in_use[around.left] and in_use[around.right])) then
							r, g, b = 0x4A, 0x30, 0x00
						else
							r, g, b = 0x7B, 0x3F, 0x00
						end

						r, g, b = r / 255, g / 255, b / 255

						clod:setFillColor(r, g, b)

						--
						if row == 1 then
							display.newRect(to_save, penx + x + 1, peny + y, Dim, 1):setFillColor(r, g, b)
						elseif row == nrows then
							display.newRect(to_save, penx + x + 1, peny + y + Dim + 1, Dim, 1):setFillColor(r, g, b)
						end

						--
						if col == 1 then
							display.newRect(to_save, penx + x, peny + y + 1, 1, Dim):setFillColor(r, g, b)
						elseif col == ncols then
							display.newRect(to_save, penx + x + Dim + 1, peny + y + 1, 1, Dim):setFillColor(r, g, b)
						end
					end

					index, x = index + 1, x + Dim
				end

				y = y + Dim
			end

			penx = penx + xinc

			if clipboard then
				clipboard:write(nadded % 10 == 0 and "\n\t" or " ", format("0x%04x", gray), ",")
			end

			nadded = nadded + 1
        end

		-- Update Gray code state.
		half, inc, prev_gray = half + inc, 1 - inc, gray
	end

	--
	if clipboard then
		clipboard:write("\n}")
		clipboard:close()
	end

	local dark = display.newRect(to_save, 0, 0, to_save.width, to_save.height)

	dark:setFillColor(0)
	dark:toBack()

	display.save(to_save, "NAME")
--local merp = display.captureBounds(to_save.contentBounds, true)
--merp:removeSelf()
--print(nx, ny)
	to_save:removeSelf()
end

-- Export the module.
return M
]=]

-- Cache module members.
_NewReel_ = M.NewReel

-- Export the module.
return M