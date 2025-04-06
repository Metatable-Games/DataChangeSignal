-- (c) 2025 Meta Games, all rights reserved.

local HttpService = game:GetService("HttpService")

local Signal = src..
local Janitor = src..

local hookedTables = {}
local DataChangeSignal = {}
DataChangeSignal.__index = DataChangeSignal

-- Hook a table and register a callback
local function hook(tbl, callback): string
	local mt = getmetatable(tbl)
	if not mt then
		mt = {}
		setmetatable(tbl, mt)
	end

	local guid = HttpService:GenerateGUID(false)

	if not hookedTables[tbl] then
		-- First hook for this table
		local originalNewIndex = mt.__newindex
		local originalIndex = mt.__index

		hookedTables[tbl] = {
			originalNewIndex = originalNewIndex,
			originalIndex = originalIndex,
			callbacks = {},
			guids = {},
		}

		-- Inject a new __newindex handler
		mt.__newindex = function(t, key, value)
			local oldValue
			local index = hookedTables[tbl].originalIndex

			if rawget(t, key) ~= nil then
				oldValue = rawget(t, key)
			elseif type(index) == "function" then
				oldValue = index(t, key)
			elseif type(index) == "table" then
				oldValue = index[key]
			end

			-- Fire all callbacks
			for _, cb in ipairs(hookedTables[tbl].callbacks) do
				task.spawn(cb, key, value, oldValue)
			end

			local newIndex = hookedTables[tbl].originalNewIndex
			if newIndex then
				if type(newIndex) == "function" then
					newIndex(t, key, value)
				else
					rawset(newIndex, key, value)
				end
			else
				rawset(t, key, value)
			end
		end
	end

	table.insert(hookedTables[tbl].callbacks, callback)
	hookedTables[tbl].guids[guid] = callback

	return guid
end

-- Unhook a specific callback by its GUID
local function unhook(tbl, guid)
	local info = hookedTables[tbl]
	if not info then
		return
	end

	local callback = info.guids[guid]
	if not callback then
		return
	end

	-- Remove from callbacks list
	for i, cb in ipairs(info.callbacks) do
		if cb == callback then
			table.remove(info.callbacks, i)
			break
		end
	end

	info.guids[guid] = nil

	-- If no more callbacks, restore original metamethods & cleanup.
	if #info.callbacks == 0 then
		local mt = getmetatable(tbl)
		mt.__newindex = info.originalNewIndex
		mt.__index = info.originalIndex
		hookedTables[tbl] = nil
	end
end

-- Signal wrapper for a hooked table
function DataChangeSignal.new(metatable: table)
	local self = setmetatable({}, DataChangeSignal)

	self.Janitor = Janitor.new()
	self.OnValueChanged = Signal.new()
	self.Janitor:Add(self.OnValueChanged, "Destroy")

	self.metatable = metatable
	self.guid = hook(metatable, function(key, newValue, oldValue)
		self.OnValueChanged:Fire(key, newValue, oldValue)
	end)

	return self
end

function DataChangeSignal:Destroy()
	unhook(self.metatable, self.guid)
	self.Janitor:Cleanup()
	self = nil;
end

return DataChangeSignal
