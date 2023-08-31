--!strict
local class = require("src/class")
local exception = require("src/exception")
local types = require("src/types")
local value = require("src/value")

type VM = types.VM
type String = types.String
type Value = types.Value
type State = types.State

local String = class.define_class(nil, "String", nil :: any)

class.define_method(String, "initialize", function(state: State, argc: number)
	local val = state.get_register(0)
	if argc == 1 and val.type ~= "string" then
		local value_type = if val.type == "object"
			then class.get_class(val.value).name
			else string.gsub(val.type, "^%l", string.upper)
		exception.raise(state.vm, exception.TypeError, `no implicit conversion of {value_type} into String`)
		return
	end

	if argc > 1 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0..1)`)
		return
	end

	if argc == 0 then
		state.set_register(0, value.tostr(""))

		return
	end

	state.set_register(0, value.tostr(val.value.str))
end)

class.define_method(String, "+", function(state: State, argc: number)
	if argc ~= 1 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	local self = state.get_register(0)
	assert(self.type == "string")

	local val = state.get_register(1)
	if val.type ~= "string" then
		local value_type = if val.type == "object"
			then class.get_class(val.value).name
			else string.gsub(val.type, "^%l", string.upper)
		exception.raise(state.vm, exception.TypeError, `no implicit conversion of {value_type} into String`)
		return
	end

	state.set_register(0, value.tostr(self.value.str .. val.value.str))
end)

class.define_method(String, "*", function(state: State, argc: number)
	if argc ~= 1 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	local self = state.get_register(0)
	assert(self.type == "string")

	local val = state.get_register(1)
	local rep: number
	if val.type ~= "integer" then
		if val.type ~= "float" then
			local value_type = if val.type == "object"
				then class.get_class(val.value).name
				else string.gsub(val.type, "^%l", string.upper)
			exception.raise(state.vm, exception.TypeError, `no implicit conversion of {value_type} into String`)
			return
		end

		rep = math.floor(val.value.number)
	else
		rep = val.value.number
	end

	state.set_register(0, value.tostr(string.rep(self.value.str, rep)))
end)

local str_len = function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	local self = state.get_register(0)
	assert(self.type == "string")

	state.set_register(0, value.tointeger(#self.value.str))
end

class.define_method(String, "size", str_len)
class.define_method(String, "length", str_len)

class.define_method(String, "to_i", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	local self = state.get_register(0)
	assert(self.type == "string")

	local beg, _, strnum = string.find(self.value.str, "(^%d+)")
	if beg == nil then
		state.set_register(0, value.tointeger(0))
		return
	end

	state.set_register(0, value.tointeger(tonumber(strnum) :: number))
end)

class.define_method(String, "to_f", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	local self = state.get_register(0)
	assert(self.type == "string")

	local beg, _, strnum = string.find(self.value.str, "^(%d+%.%d+)")
	if beg == nil then
		state.set_register(0, value.tofloat(0))
		return
	end

	state.set_register(0, value.tofloat(tonumber(strnum) :: number))
end)

class.define_method(String, "to_s", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	local self = state.get_register(0)
	assert(self.type == "string")

	state.set_register(0, self)
end)

class.define_method(String, "<<", function(state: State, argc: number)
	if argc ~= 1 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	local self = state.get_register(0)
	assert(self.type == "string")

	local val = state.get_register(1)
	if val.type == "integer" then
		self.value.str ..= string.char(val.value.number)
	elseif val.type == "string" then
		self.value.str ..= val.value.str
	else
		-- TODO Call to_s of other types
		local value_type = if val.type == "object"
			then class.get_class(val.value).name
			else string.gsub(val.type, "^%l", string.upper)
		exception.raise(
			state.vm,
			exception.TypeError,
			`no implicit conversion of {value_type} into String (calling of to_s isn't implemented yet)`
		)
		return
	end

	state.set_register(0, self)
end)

class.define_method(String, "[]", function(state: State, argc: number)
	if argc ~= 1 or argc ~= 2 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1..2)`)
		return
	end

	local self = state.get_register(0)
	assert(self.type == "string")

	local start_idx: number
	local end_idx: number

	local val1 = state.get_register(1)
	if val1.type == "integer" or val1.type == "float" then
		start_idx = math.floor(val1.value.number) + 1
	else
		-- TODO Call to_s of other types
		local value_type = if val1.type == "object"
			then class.get_class(val1.value).name
			else string.gsub(val1.type, "^%l", string.upper)
		exception.raise(
			state.vm,
			exception.TypeError,
			`no implicit conversion of {value_type} into String (calling of to_s isn't implemented yet)`
		)
		return
	end

	if argc == 2 then
		local val2 = state.get_register(3)
		if val2.type == "integer" or val2.type == "float" then
			end_idx = math.floor(val2.value.number) + 1
		else
			-- TODO Call to_s of other types
			local value_type = if val2.type == "object"
				then class.get_class(val2.value).name
				else string.gsub(val1.type, "^%l", string.upper)
			exception.raise(
				state.vm,
				exception.TypeError,
				`no implicit conversion of {value_type} into String (calling of to_s isn't implemented yet)`
			)
			return
		end
	else
		end_idx = start_idx
	end

	local substr = string.sub(self.value.str, start_idx, end_idx)
	state.set_register(0, value.tostr(substr))
end)

return {}
