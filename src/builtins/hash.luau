--!strict
local types = require("types")
local class = require("class")
local exception = require("exception")

type VM = types.VM
type Value = types.Value
type Hash = types.Hash
type State = types.State

local Hash = class.define_class(nil, "Hash", nil :: any)

class.define_method(Hash, "initialize", function(state: State, argc: number)
    if argc ~= 0 then
        exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
    end
end)

return {}