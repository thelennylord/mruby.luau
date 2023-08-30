--!strict
local class = require("class")
local exception = require("exception")
local types = require("types")
local value = require("value")

type VM = types.VM
type Value = types.Value
type NilClass = types.NilClass
type State = types.State
type String = types.String
type Class = types.Class
type Array = types.Array
type Hash = types.Hash

local NilClass = class.define_class(nil, "NilClass", nil :: any)

class.define_method(NilClass, "&", function(state: State, argc: number)
	if argc > 1 or argc == 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	state.set_register(0, value.false_value)
end)

class.define_method(NilClass, "=~", function(state: State, argc: number)
	if argc > 1 or argc == 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	state.set_register(0, value.nil_value)
end)

class.define_method(NilClass, "^", function(state: State, argc: number)
	if argc > 1 or argc == 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	local val1 = state.get_register(1)
	if val1.type == "nil" or val1.type == "false" then
		state.set_register(0, value.false_value)
		return
	end

	state.set_register(0, value.true_value)
end)

class.alias_method(NilClass, "|", "^")

class.define_method(NilClass, "inspect", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	state.set_register(0, value.tostr("nil"))
end)

class.alias_method(NilClass, "to_s", "inspect")

class.define_method(NilClass, "nil?", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	state.set_register(0, value.true_value)
end)

class.define_method(NilClass, "to_a", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	local ret = class.instance_new(class.builtins.Array);
	(ret.value :: Array).array = {}

	state.set_register(0, ret)
end)

class.define_method(NilClass, "to_h", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	local ret = class.instance_new(class.builtins.Hash);
	(ret.value :: Hash).hash = {}

	state.set_register(0, ret)
end)

class.define_method(NilClass, "to_i", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	state.set_register(0, value.tointeger(0))
end)

class.define_method(NilClass, "to_f", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	state.set_register(0, value.tofloat(0))
end)

return {}
