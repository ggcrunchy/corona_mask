--- Functionality for mask sheets.

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
local assert = assert
local ceil = math.ceil
local format = string.format
local floor = math.floor
local remove = os.remove
local tostring = tostring
local type = type
local unpack = unpack

-- Modules --
local capture = require("corona_utils.capture")
local data_utils = require("corona_utils.data")
local file = require("corona_utils.file")
local grid_funcs = require("tektite_core.array.grid")
local mask_utils = require("corona_mask.utils")
local schema = require("tektite_core.table.schema")
local var_preds = require("tektite_core.var.predicates")

-- Corona globals --
local display = display
local graphics = graphics
local system = system

-- Cached module references --
local _NewReader_

-- Exports --
local M = {}

-- Content dimensions available to build up mask --
local MaskContentW, MaskContentH = display.contentWidth - 6, display.contentHeight - 6

-- Default yield function: no-op
local function DefYieldFunc () end

-- Rounds up to next multiple of 4 (mask dimensions requirement)
local function NextMult4 (x)
	local over = x % 4

	return x + (over > 0 and 4 - over or 0)
end

-- Converts an ordered collection of positions into an easier-to-use map
local function ToFrameMap (arr)
	local frames = {}

	for i = 1, #arr, 3 do
		frames[arr[i]] = { arr[i + 1], arr[i + 2] }
	end

	return frames
end

-- --
local MaskDataName = "corona_mask_data"

-- --
local DataOpts = { table_name = MaskDataName, keyword = MaskDataName }

--
local function SetData (MS, data)
	MS.m_data = data
end

-- Tries to read file-related data from some source
local function ReadData (MS, opts, filename)
	DataOpts.data, DataOpts.key = opts.data, filename

	local data = data_utils.ReadData(opts.method, DataOpts)

	if type(data) == "table" and #data > 0 then
		SetData(MS, data)
	end

	DataOpts.data, DataOpts.key = nil
end

--
local function WriteData (MS, method, source, frames, fdimx, fdimy, xdim, ydim, filename)
	-- Correct the mask coordinates to refer to frame centers, relative to the mask center.
	local xcorr = floor((xdim - fdimx + 1) / 2)
	local ycorr = floor((ydim - fdimy + 1) / 2)

	for i = 2, #frames, 3 do
		frames[i], frames[i + 1] = xcorr - frames[i], ycorr - frames[i + 1]
	end

	--
	DataOpts.data, DataOpts.key, DataOpts.payload = source, filename, frames

	data_utils.WriteData(method, DataOpts)

	DataOpts.data, DataOpts.key, DataOpts.payload = nil

	-- Register the data.
	SetData(MS, frames)
end

--
local function CountFromDim (grid_dim, sprite_dim)
	return ceil(grid_dim / sprite_dim)
end

-- --
-- grid_ncols, grid_nrows, grid_count: counts used by the grid itself, def = ceil(grid_? / sprite_?) | ? = w or h
-- cell_ncols, cell_nrows, cell_count: per cell counts
-- frame_unit_w, frame_unit_h, frame_unit_dim: sheet frame dimensions
-- sprite_w, sprite_h, sprite_dim: in-use sprite dimensions
local Schema = schema.NewSchema{
	-- --
	alt_groups = {
		count = { "ncols", "nrows", prefixed = { "grid_", "cell_" } },
		dim = { "w", "h", prefixed = { "frame_unit_", "sprite_" } },
	},

	-- --
	def_val_funcs = {
		grid_ncols = { CountFromDim, "grid_w", "sprite_w" },
		grid_nrows = { CountFromDim, "grid_h", "sprite_h" }
	},

	-- --
	def_predicate = function(var)
		return var_preds.IsInteger(var) and var > 0, "Not a positive integer"
	end,

	-- --
	def_required = true
}

--- DOCME
-- @ptable opts
-- @treturn function X
function M.NewReader (opts)
	return schema.NewReader(opts, Schema)
end

--
local function GetDim (reader, fdim, unit_dim_name, cell_count_name)
	if fdim then -- TODO: what is this for?
		return fdim, format("%i", fdim)
	else
		local nunits, count = reader(unit_dim_name), reader(cell_count_name)

		return nunits * count, format("%ip%i", nunits, count)
	end
end

--
local function AuxNewSheet (opts)
	local reader = _NewReader_(opts)
	local fdimx, xstr = GetDim(reader, opts.dimx or opts.dim, "frame_unit_w", "cell_ncols")
	local fdimy, ystr = GetDim(reader, opts.dimy or opts.dim, "frame_unit_h", "cell_nrows")
	local name, id = assert(opts.name, "Missing filename"), opts.id and ("_id_" .. tostring(opts.id)) or ""

	return reader, fdimx, fdimy, format("__%s_%sx%s%s__.png", name, xstr, ystr, id), opts.method, opts.data
end

--
local function BindPatterns (MS, clear, full)
	MS.m_clear, MS.m_full = clear, full
end

--
local function GetCounts (fdimx, fdimy)
	local dx, dy = fdimx + 3, fdimy + 3

	return floor((MaskContentW + 3) / dx), floor((MaskContentH + 3) / dy), dx, dy
end

--
local function GetData (MS)
	return MS.m_data
end

--
local function GetDims (x, y, endx, ncols, dy)
	return NextMult4(endx or x), NextMult4(y + (ncols > 0 and dy or 0))
end

--
local function GetIndexType (MS, index)
	if index == MS.m_clear then
		return "clear"
	elseif index == MS.m_full then
		return "full"
	else
		return "normal"
	end
end

--
local function GetScales (fdimx, fdimy, w, h)
	return w / fdimx, h / fdimy
end

--
local function SetMask (mask, frames, object, index, xscale, yscale, itype)
	assert(mask, "Mask not ready")

	local not_clear, frame = itype ~= "clear", frames[index]

	object.isVisible = not_clear

	if not_clear then -- non-visible cells are fine as is
		-- If a cell is full, there is nothing to mask.
		if itype == "full" then
			object:setMask(nil)

		-- Otherwise, apply the mask at the given frame.
		elseif frame then
			object:setMask(mask)

			local x, y = unpack(frame)

			object.maskX, object.maskScaleX = ceil(x * xscale), xscale
			object.maskY, object.maskScaleY = ceil(y * yscale), yscale
		end
	end
end

--
local function NewSheetBody (opts, use_grid)
	local reader, fdimx, fdimy, filename, method, data = AuxNewSheet(opts)
	local base_dir = opts.dir or system.CachesDirectory
	local exists = file.Exists(filename, base_dir)
	local MaskSheet, frames, mask, xscale, yscale = {}, {}

	--
	local cells, layout, bcols, brows = opts.cells, opts.layout

	if use_grid then
		bcols = reader("grid_ncols", "cache")
		brows = reader("grid_nrows", "cache")

		assert(type(cells) == "table", "Missing grid cells")
	end

	--
	if exists and not opts.recreate then
		ReadData(MaskSheet, opts, filename)
	end

	--
	local ms_data, sprw, sprh = GetData(MaskSheet), reader("sprite_w"), reader("sprite_h")

	if ms_data then
		mask, frames = graphics.newMask(filename, base_dir), ToFrameMap(ms_data)
		xscale, yscale = GetScales(fdimx, fdimy, sprw, sprh)

		-- Add dummy and non-closure methods.
		local function Fail ()
			assert(false, "Mask already created")
		end

		MaskSheet.AddFrame, MaskSheet.Commit, MaskSheet.GetRect, MaskSheet.StashRect = Fail, Fail, Fail, Fail
		MaskSheet.BindPatterns, MaskSheet.GetData = BindPatterns, GetData

	--
	else
		-- If a mask file with the same name exists, remove it.
		if exists then
			assert(base_dir ~= system.ResourceDirectory, "Mask sheet is missing data")

			remove(system.pathForFile(filename, base_dir))
		end

		-- Compute the offset as the 3 pixels of black border plus any padding needed to satisfy
		-- the height requirement. Bounded captures will be used to grab each frame, since using
		-- several containers and capturing all in one go seems to be flaky on the simulator.
		local back, into = mask_utils.NewRect(display.getCurrentStage(), nil, 0, 0, fdimx, fdimy), opts.into
		local mgroup, stash = display.newGroup(), display.newGroup()

		stash.isVisible = false

		if into then
			into:insert(back)
			into:insert(mgroup)
			into:insert(stash)
		end

		local bounds, yfunc, hidden = back.contentBounds, opts.yfunc or DefYieldFunc, not not opts.hidden
		local cols_done, rows_done, x, y, endx = 0, 0, 3, 3
		local ncols, nrows, dx, dy = GetCounts(fdimx, fdimy)

		--- DOCME
		-- @callable func
		-- @param index
		-- @bool is_white
		-- @callable[opt] after
		function MaskSheet:AddFrame (func, index, is_white, after)
			assert(not mask, "Mask already created")
			assert(rows_done < nrows, "No space for new frames")

			--
			local cgroup, bg = display.newGroup(), is_white and 1 or 0

			if into then
				into:insert(cgroup)
			end

			-- Add the background color, i.e. the component of the frame not defined by the shapes.
			back:setFillColor(bg)

			-- Save the frame's left-hand coordinate.
			frames[#frames + 1] = index
			frames[#frames + 1] = x
			frames[#frames + 1] = y

			--
			func(cgroup, 1 - bg, fdimx, fdimy, index)

			cgroup:insert(back)
			back:toBack()

			-- Capture the frame and incorporate it into the built-up mask.
			local fcap = capture.CaptureBounds(cgroup, bounds, {
				w = MaskContentW, h = MaskContentH,
				base_dir = system.TemporaryDirectory,
				hidden = hidden, yfunc = yfunc
			})

			mgroup:insert(fcap)
			cgroup.parent:insert(back)

			yfunc()

			--
			if after then
				after(cgroup, index)
			end

			cgroup:removeSelf()

			fcap.anchorX, fcap.x = 0, x
			fcap.anchorY, fcap.y = 0, y

			-- Advance past the frame.
			if cols_done == ncols then
				cols_done, endx = 0, endx or x + dx
				rows_done, x, y = rows_done + 1, 3, y + dy
			else
				cols_done, x = cols_done + 1, x + dx
			end
		end

		--- DOCME
		-- @function MaskSheet:BindPatterns
		-- @uint[opt] clear
		-- @uint[opt] full
		MaskSheet.BindPatterns = BindPatterns

		--- DOCME
		function MaskSheet:Commit ()
			assert(not mask, "Mask already created")

			--
			local xdim, ydim = GetDims(x, y, endx, ncols, dy)
			local background = mask_utils.BlackRect(mgroup, stash, 0, 0, xdim, ydim)

			background:toBack()

			-- Save the image and mask data.
			capture.Save(mgroup, filename, base_dir)

			WriteData(self, method, data, frames, fdimx, fdimy, xdim, ydim, filename)

			-- Clean up temporary resources.
			back:removeSelf()
			mgroup:removeSelf()
			stash:removeSelf()

			back, bounds, into, mgroup, stash, yfunc = nil

			-- Create a mask with final frames.
			mask, frames = graphics.newMask(filename, base_dir), ToFrameMap(frames)
			xscale, yscale = GetScales(fdimx, fdimy, sprw, sprh)
		end

		--- Getter.
		-- @function MaskSheet:GetData
		-- @return X
		MaskSheet.GetData = GetData

		--- DOCME
		-- @pgroup group
		-- @number x
		-- @number y
		-- @number w
		-- @number h
		-- @number[opt] fill
		-- @treturn DisplayObject X
		function MaskSheet:GetRect (group, x, y, w, h, fill)
			assert(not mask, "Mask already created")

			return mask_utils.NewRect(group, stash, x, y, w, h, fill)
		end

		--- DOCME
		-- @pobject rect X
		function MaskSheet:StashRect (rect)
			if stash then
				stash:insert(rect)
			else
				rect:removeSelf()
			end
		end
	end

	--- Predicate.
	-- @treturn boolean S###
	function MaskSheet:IsLoaded ()
		return mask ~= nil
	end

	--- DOCME
	-- @pobject object
	-- @param index
	function MaskSheet:Set (object, index)
		SetMask(mask, frames, object, index, xscale, yscale, GetIndexType(self, index))
	end

	if use_grid then
		local on_get_object = opts.on_get_object

		--- DOCME
		-- @uint col
		-- @uint row
		-- @param index
		function MaskSheet:Set_Cell (col, row, index)
			local gindex = grid_funcs.CellToIndex_Layout(col, row, bcols, brows, layout)
			local object = cells[gindex]

			if object then
				local itype = GetIndexType(self, index)

				if on_get_object then
					on_get_object(object, itype, col, row, bcols, brows)
				end

				SetMask(mask, frames, object, index, xscale, yscale, itype)
			end
		end
	end

	return MaskSheet, reader
end

--- DOCME
-- @ptable opts
-- @treturn MaskSheet MS
-- @treturn function READER
function M.NewSheet (opts)
	return NewSheetBody(opts, false)
end

--- DOCME
-- @ptable opts
-- @treturn MaskSheet MS
-- @treturn function READER
function M.NewSheet_Data (opts)
	local reader, fdimx, fdimy, filename, method, data = AuxNewSheet(opts)
	local MaskSheet_Data, frames = {}, {}

	--
	local cols_done, rows_done, x, y, endx = 0, 0, 3, 3
	local ncols, nrows, dx, dy = GetCounts(fdimx, fdimy)

	--- DOCME
	-- @param index
	function MaskSheet_Data:AddFrame (index)
		assert(frames, "Data already created")
		assert(rows_done < nrows, "No space for new frames")

		-- Save the frame's left-hand coordinate.
		frames[#frames + 1] = index
		frames[#frames + 1] = x
		frames[#frames + 1] = y

		--
		if cols_done == ncols then
			cols_done, endx = 0, endx or x + dx
			rows_done, x, y = rows_done + 1, 3, y + dy
		else
			cols_done, x = cols_done + 1, x + dx
		end
	end

	--- DOCME
	function MaskSheet_Data:Commit ()
		assert(frames, "Data already created")

		local xdim, ydim = GetDims(x, y, endx, ncols, dy)

		WriteData(self, method, data, frames, fdimx, fdimy, xdim, ydim, filename)

		frames = nil
	end

	--- Getter.
	-- @function MaskSheet_Data:GetData
	-- @return X
	MaskSheet_Data.GetData = GetData

	--- Predicate.
	-- @treturn boolean S###
	function MaskSheet_Data:IsLoaded ()
		return frames == nil
	end

	return MaskSheet_Data, reader
end

--- DOCME
-- @ptable opts
-- @treturn MaskSheet MS
-- @treturn function READER
function M.NewSheet_Grid (opts)
	return NewSheetBody(opts, true)
end

-- Cache module members.
_NewReader_ = M.NewReader

-- Export the module.
return M