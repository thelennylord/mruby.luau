--!strict
local class = require("src/class")
local exception = require("src/exception")
local types = require("src/types")
local value = require("src/value")

type State = types.State
type String = types.String
type FloatValue = types.FloatValue
type StringValue = types.StringValue

local Float = class.define_class("Float", nil :: any)

class.define_method(Float, "zero?", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	local val = state.get_register(0) :: FloatValue
	state.set_register(0, value.toboolean(val.value.number == 0))
end)

class.define_method(Float, "nonzero?", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	local val = state.get_register(0) :: FloatValue
	state.set_register(0, value.toboolean(val.value.number ~= 0))
end)

class.define_method(Float, "positive?", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	local val = state.get_register(0) :: FloatValue
	state.set_register(0, value.toboolean(val.value.number > 0))
end)

class.define_method(Float, "negative?", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	local val = state.get_register(0) :: FloatValue
	state.set_register(0, value.toboolean(val.value.number < 0))
end)

class.define_method(Float, "abs", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	local val = state.get_register(0) :: FloatValue
	state.set_register(0, value.tofloat(math.abs(val.value.number)))
end)
class.alias_method(Float, "magnitude", "abs")

class.define_method(Float, "abs2", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	local val = state.get_register(0) :: FloatValue
	state.set_register(0, value.tofloat(math.abs(val.value.number) ^ 2))
end)

class.define_method(Float, "integer?", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	state.set_register(0, value.false_value)
end)

class.define_method(Float, "to_i", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	local self = state.get_register(0) :: FloatValue
	state.set_register(0, value.tointeger(math.floor(self.value.number)))
end)
class.alias_method(Float, "to_int", "to_i")

class.define_method(Float, "to_f", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	-- Do nothing as it returns self
end)

class.define_method(Float, "inspect", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	local val = state.get_register(0) :: FloatValue

	state.set_register(0, value.tostr(tostring(val.value.number)))
end)
class.alias_method(Float, "to_s", "inspect")

class.define_method(Float, "div", function(state: State, argc: number)
	if argc > 1 or argc == 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	local self = state.get_register(0) :: FloatValue
	local val = state.get_register(1)
	if val.type ~= "integer" and val.type ~= "float" then
		exception.raise(state.vm, exception.TypeError, `{class.get_class(val.value).name} can't be coerced into Float`)
		return
	end

	state.set_register(0, value.tointeger(math.floor(self.value.number / val.value.number)))
end)

class.define_method(Float, "fdiv", function(state: State, argc: number)
	if argc > 1 or argc == 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	local self = state.get_register(0) :: FloatValue
	local val = state.get_register(1)
	if val.type ~= "integer" and val.type ~= "float" then
		exception.raise(state.vm, exception.TypeError, `{class.get_class(val.value).name} can't be coerced into Float`)
		return
	end

	state.set_register(0, value.tofloat(self.value.number / val.value.number))
end)
class.alias_method(Float, "quo", "fdiv")

class.define_method(Float, "ceil", function(state: State, argc: number)
	if argc > 1 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	local self = state.get_register(0) :: FloatValue

	local ndigits = 0
	if argc > 0 then
		local val = state.get_register(1)
		if val.type ~= "integer" and val.type ~= "float" then
			exception.raise(
				state.vm,
				exception.TypeError,
				`{class.get_class(val.value).name} can't be coerced into Float`
			)
			return
		end

		ndigits = val.value.number
	end

	local ret: number
	if ndigits >= 0 then
		ret = self.value.number
	else
		ret = self.value.number - (self.value.number % -10 ^ ndigits)
	end

	state.set_register(0, value.tofloat(ret))
end)

class.define_method(Float, "floor", function(state: State, argc: number)
	if argc > 1 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
		return
	end

	local self = state.get_register(0) :: FloatValue

	local ndigits = 0
	if argc > 0 then
		local val = state.get_register(1)
		if val.type ~= "integer" and val.type ~= "float" then
			exception.raise(
				state.vm,
				exception.TypeError,
				`{class.get_class(val.value).name} can't be coerced into Float`
			)
			return
		end

		ndigits = val.value.number
	end

	local ret: number
	if ndigits >= 0 then
		ret = self.value.number
	else
		ret = self.value.number - (self.value.number % -10 ^ ndigits)
	end

	state.set_register(0, value.tofloat(ret))
end)

return {}
