--!strict
-- Object class
local class = require("src/class")
local exception = require("src/exception")
local types = require("src/types")
local value = require("src/value")

type State = types.State
type Class = types.Class

-- An empty class of BasicObject was already pre-defined in class.luau
local BasicObject = class.define_class(nil, "BasicObject", nil :: any)
class.define_method(BasicObject, "initialize", function(state: State, argc: number) end)

class.define_method(BasicObject, "__id__", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	local self = state.get_register(0)
	local id = tonumber(string.sub(tostring(self.value), 8)) :: number

	state.set_register(0, value.tointeger(id))
end)

class.define_method(BasicObject, "equal?", function(state: State, argc: number)
	if argc ~= 1 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	local self = state.get_register(0)
	local other = state.get_register(1)

	state.set_register(0, value.toboolean(self == other))
end)

class.define_method(BasicObject, "!", function(state: State, argc: number)
	local self = state.get_register(0)

	local ret = value.toboolean(self.type == "nil" or self.type == "false")
	state.set_register(0, ret)
end)

return BasicObject
