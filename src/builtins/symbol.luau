--!strict
local class = require("src/class")
local exception = require("src/exception")
local types = require("src/types")
local value = require("src/value")

type VM = types.VM
type Value = types.Value
type Symbol = types.Symbol
type State = types.State
type String = types.String
type Class = types.Class
type SymbolValue = types.SymbolValue

-- TODO Symbol class
local Symbol = class.define_class("Symbol", nil :: any)

class.define_method(Symbol, "inspect", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	local self = state.get_register(0) :: SymbolValue

	state.set_register(0, value.tostr(":" .. self.value.symbol))
end)

class.define_method(Symbol, "to_s", function(state: State, argc: number)
	if argc > 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
		return
	end

	local self = state.get_register(0) :: SymbolValue

	state.set_register(0, value.tostr(self.value.symbol))
end)

return {}
