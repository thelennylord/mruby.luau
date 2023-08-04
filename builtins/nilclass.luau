--!strict
local types = require("types")
local class = require("class")
local err = require("error")
local value = require("value")

local error_class = require("builtins/errors")
local object_class = require("builtins/object")

type VM = types.VM
type Value = types.Value
type NilClass = types.NilClass
type State = types.State
type String = types.String
type Class = types.Class
type Array = types.Array
type Hash = types.Hash

local NilClass = class.define_class(nil, "NilClass", object_class)

class.define_method(NilClass, "&", function(state: State, argc: number)
    if argc > 1 or argc == 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end

    state.set_register(0, value.autocast(false))
end)

class.define_method(NilClass, "=~", function(state: State, argc: number)
    if argc > 1 or argc == 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end

    state.set_register(0, value.autocast(nil))
end)

class.define_method(NilClass, "^", function(state: State, argc: number)
    if argc > 1 or argc == 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end

    local val1 = state.get_register(1)
    if val1.type == "nil" or val1.type == "false" then
        state.set_register(0, value.autocast(false))
        return
    end

    state.set_register(0, value.autocast(true))
end)

class.alias_method(NilClass, "|", "^")

class.define_method(NilClass, "inspect", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local ret = class.instance_new(class.get_class_by_name("String") :: Class);
    (ret.value :: String).str = "nil"

    state.set_register(0, ret)
end)

class.define_method(NilClass, "to_s", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local ret = class.instance_new(class.get_class_by_name("String") :: Class);
    (ret.value :: String).str = ""

    state.set_register(0, ret)
end)

class.define_method(NilClass, "nil?", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    state.set_register(0, value.autocast(true))
end)

class.define_method(NilClass, "to_a", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local ret = class.instance_new(class.get_class_by_name("Array") :: Class);
    (ret.value :: Array).array = {}

    state.set_register(0, ret)
end)

class.define_method(NilClass, "to_h", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local ret = class.instance_new(class.get_class_by_name("Hash") :: Class);
    (ret.value :: Hash).hash = {}

    state.set_register(0, ret)
end)

class.define_method(NilClass, "to_i", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    state.set_register(0, value.autocast(0, "integer"))
end)

class.define_method(NilClass, "to_f", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    state.set_register(0, value.autocast(0, "float"))
end)

return NilClass