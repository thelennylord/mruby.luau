--!strict
local class = require("src/class")
local exception = require("src/exception")
local types = require("src/types")

type VM = types.VM
type Value = types.Value
type Hash = types.Hash
type State = types.State

local Hash = class.define_class("Hash", nil :: any)

class.define_method(Hash, "initialize", function(state: State, argc: number)
	if argc ~= 0 then
		exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
	end
end)

return {}
