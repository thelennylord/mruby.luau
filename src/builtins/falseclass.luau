--!strict
local class = require("src/class")
local exception = require("src/exception")
local types = require("src/types")
local value = require("src/value")

type VM = types.VM
type Value = types.Value
type FalseClass = types.FalseClass
type State = types.State
type String = types.String
type Class = types.Class

local FalseClass = class.define_class("FalseClass", nil :: any)

class.define_method(FalseClass, "&", function(state: State, argc: number)
	if argc > 1 or argc == 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end
end)

class.define_method(FalseClass, "^", function(state: State, argc: number)
	if argc > 1 or argc == 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	local val = state.get_register(1)
	if val.type == "nil" or val.type == "false" then
		state.set_register(0, value.false_value)
	end
end)

class.alias_method(FalseClass, "|", "^")

class.define_method(FalseClass, "to_s", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	state.set_register(0, value.tostr("false"))
end)
class.alias_method(FalseClass, "inspect", "to_s")

return FalseClass
