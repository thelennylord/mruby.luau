--!strict
local types = require("types")
local class = require("class")
local keyvalue = require("keyvalue")
local err = require("error")
local error_class = require("builtins/errors")
local object_class = require("builtins/object")

type VM = types.VM
type Value = types.Value
type Hash = types.Hash

local Hash = class.define_class(nil, "Array", object_class)

class.define_method(Hash, "new", function(vm: VM, argc: number)
    local new_hash: Hash = {
        class = Hash,
        ivar = keyvalue.new(),
        hash = {}
    }

    -- Hash.new()
    if argc == 0 then
        vm:set_register(1, {
            type = "hash",
            value = new_hash
        })
        return
    end

    err.raise(vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
end)

return Hash