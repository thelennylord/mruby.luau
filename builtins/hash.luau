--!strict
local types = require("types")
local class = require("class")
local err = require("error")
local error_class = require("builtins/errors")
local object_class = require("builtins/object")

type VM = types.VM
type Value = types.Value
type Hash = types.Hash
type State = types.State

local Hash = class.define_class(nil, "Hash", object_class)

class.define_method(Hash, "initialize", function(state: State, argc: number)
    if argc ~= 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
    end
end)

return Hash