--!strict
local types = require("types")
local class = require("class")
local err = require("error")
local value = require("value")

local error_class = require("builtins/errors")
local object_class = require("builtins/object")

type VM = types.VM
type Value = types.Value
type FalseClass = types.FalseClass
type State = types.State
type String = types.String
type Class = types.Class

local FalseClass = class.define_class(nil, "FalseClass", object_class)

class.define_method(FalseClass, "&", function(state: State, argc: number)
    if argc > 1 or argc == 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end
end)

class.define_method(FalseClass, "^", function(state: State, argc: number)
    if argc > 1 or argc == 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end

    local val = state.get_register(1)
    if val.type == "nil" or val.type == "false" then
        state.set_register(0, value.autocast(false))
    end
end)

class.alias_method(FalseClass, "|", "^")

class.define_method(FalseClass, "to_s", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local ret = class.instance_new(class.get_class_by_name("String") :: Class);
    (ret.value :: String).str = "false"

    state.set_register(0, ret)
end)
class.alias_method(FalseClass, "inspect", "to_s")

return FalseClass