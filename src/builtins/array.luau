--!strict
local class = require("class")
local exception = require("exception")
local types = require("types")
local value = require("value")

type VM = types.VM
type Value = types.Value
type Array = types.Array
type State = types.State

local Array = class.define_class(nil, "Array", nil :: any)

class.define_method(Array, "initialize", function(state: State, argc: number)
	local self = state.get_register(0)
	assert(self.type == "array")

	-- Array.new()
	if argc == 0 then
		return
	end

	local arr = self.value

	-- Array.new(number)
	if argc > 1 then
		local val = state.get_register(1)
		if val.type == "integer" and val.value.number > 0 then
			arr.array = table.create(val.value.number, value.nil_value)
		elseif val.type == "array" then
			arr.array = val.value.array
		else
			local value_type = class.get_class(val.value).name
			exception.raise(state.vm, exception.TypeError, `no implicit conversion of {value_type} into Integer`)
		end

		return
	end

	-- Array.new(number, obj)
	if argc == 2 then
		local val1 = state.get_register(1)
		if val1.type == "integer" and val1.value.number > 0 then
			local val2 = state.get_register(2)
			arr.array = table.create(val1.value.number, val2.value)
		else
			local value_type = class.get_class(val1.value).name
			exception.raise(state.vm, exception.TypeError, `no implicit conversion of {value_type} into Integer`)
		end

		return
	end

	exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
end)

class.define_method(Array, "[]", function(state: State, argc: number)
	if argc == 0 or argc > 2 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1..2)`)
		return
	end

	local self = state.get_register(0)
	assert(self.type == "array")

	local idx = state.get_register(1)
	-- TODO Call to_int
	if idx.type ~= "integer" then
		local value_type = if idx.type == "object"
			then class.get_class(idx.value).name
			else idx.type:gsub("^%l", string.upper)
		exception.raise(state.vm, exception.TypeError, `no implicit conversion of {value_type} into Integer`)
		return
	end

	if argc == 1 then
		local val = self.value.array[idx.value.number + 1] or value.nil_value
		state.set_register(0, val)
		return
	end

	local till = state.get_register(3)
	if till.type ~= "integer" then
		local value_type = if till.type == "object"
			then class.get_class(till.value).name
			else till.type:gsub("^%l", string.upper)
		exception.raise(state.vm, exception.TypeError, `no implicit conversion of {value_type} into Integer`)
		return
	end

	local val = class.instance_new(Array)
	local new_arr = val.value :: Array

	table.move(self.value.array, idx.value.number + 1, idx.value.number + till.value.number + 1, 1, new_arr.array)

	state.set_register(0, val)
end)

class.define_method(Array, "[]=", function(state: State, argc: number)
	if argc == 0 or argc > 2 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1..2)`)
		return
	end

	local self = state.get_register(0)
	assert(self.type == "array")

	local idx = state.get_register(1)
	-- TODO Call to_int
	if idx.type ~= "integer" then
		local value_type = class.get_class(idx.value).name
		exception.raise(state.vm, exception.TypeError, `no implicit conversion of {value_type} into Integer`)
		return
	end

	if argc == 1 then
		local val = self.value.array[idx.value.number] or value.nil_value
		state.set_register(0, val)
		return
	end

	local till = state.get_register(3)
	if till.type ~= "integer" then
		local value_type = class.get_class(till.value).name
		exception.raise(state.vm, exception.TypeError, `no implicit conversion of {value_type} into Integer`)
		return
	end

	local val = class.instance_new(Array)
	local new_arr = val.value :: Array

	table.move(self.value.array, idx.value.number + 1, idx.value.number + till.value.number + 1, 1, new_arr.array)

	state.set_register(0, val)
end)

class.define_method(Array, "count", function(state: State, argc: number)
	local self = state.get_register(0)
	assert(self.type == "array")

	state.set_register(0, value.tointeger(#self.value.array))
end)
class.alias_method(Array, "length", "count")
class.alias_method(Array, "size", "count")

return Array
