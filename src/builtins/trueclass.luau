--!strict
local types = require("types")
local class = require("class")
local exception = require("exception")
local value = require("value")

type VM = types.VM
type Value = types.Value
type TrueClass = types.TrueClass
type State = types.State
type String = types.String
type Class = types.Class

local TrueClass = class.define_class(nil, "TrueClass", nil :: any)

class.define_method(TrueClass, "&", function(state: State, argc: number)
    if argc > 1 or argc == 0 then
        exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end

    local val = state.get_register(1)
    if val.type == "nil" or val.type == "false" then
        state.set_register(0, value.autocast(false))
    end
end)

class.define_method(TrueClass, "^", function(state: State, argc: number)
    if argc > 1 or argc == 0 then
        exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end

    local val = state.get_register(1)
    if val.type ~= "nil" and val.type ~= "false" then
        state.set_register(0, value.autocast(false))
    end
end)

class.define_method(TrueClass, "|", function(state: State, argc: number)
    if argc > 1 or argc == 0 then
        exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end
end)

class.define_method(TrueClass, "to_s", function(state: State, argc: number)
    if argc > 0 then
        exception.raise(state.vm, exception.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local ret = class.instance_new(class.builtins.String);
    (ret.value :: String).str = "true"

    state.set_register(0, ret)
end)
class.alias_method(TrueClass, "inspect", "to_s")

return {}