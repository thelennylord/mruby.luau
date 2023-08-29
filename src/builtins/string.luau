--!strict
local class = require("class")
local types = require("types")
local value = require("value")
local err = require("error")
local error_class = require("builtins/errors")
local object_class = require("builtins/object")

type VM = types.VM
type String = types.String
type Value = types.Value
type State = types.State

local String = class.define_class(nil, "String", object_class)

-- TODO Deprecate this function and make use of class.instance_new
local function str_new(str: string): String
    local val = class.instance_new(String)
    local obj = val.value :: String
    obj.str = str

    return obj
end

class.define_method(String, "initialize", function(state: State, argc: number)
    local val = state.get_register(0)
    if argc == 1 and val.type ~= "string" then
        local value_type = if val.type == "object" then class.get_class(val.value).name else val.type:gsub("^%l", string.upper)
        err.raise(state.vm, error_class.TypeError, `no implicit conversion of {value_type} into String`)
        return
    end
    
    if argc > 1 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0..1)`)
        return
    end

    if argc == 0 then
        state.set_register(0, {
            type = "string",
            value = str_new("")
        })

        return
    end


    state.set_register(0, {
        type = "string",
        value = str_new(val.value.str)
    })
end)

class.define_method(String, "+", function(state: State, argc: number)
    if argc ~= 1 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end

    local self = state.get_register(0)
    assert(self.type == "string")

    local val = state.get_register(1)
    if val.type ~= "string" then
        local value_type = if val.type == "object" then class.get_class(val.value).name else val.type:gsub("^%l", string.upper)
        err.raise(state.vm, error_class.TypeError, `no implicit conversion of {value_type} into String`)
        return
    end

    state.set_register(0, {
        type = "string",
        value = str_new(self.value.str .. val.value.str)
    })
end)

class.define_method(String, "*", function(state: State, argc: number)
    if argc ~= 1 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end

    local self = state.get_register(0)
    assert(self.type == "string")

    local val = state.get_register(1)
    local rep: number
    if val.type ~= "integer" then
        if val.type ~= "float" then
            local value_type = if val.type == "object" then class.get_class(val.value).name else val.type:gsub("^%l", string.upper)
            err.raise(state.vm, error_class.TypeError, `no implicit conversion of {value_type} into String`)
            return
        end

        rep = math.floor(val.value.number)
    else
        rep = val.value.number
    end

    state.set_register(0, {
        type = "string",
        value = str_new(self.value.str:rep(rep))
    })
end)

local str_len = function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end

    local self = state.get_register(0)
    assert(self.type == "string")

    state.set_register(0, value.autocast(#self.value.str, "integer"))
end

class.define_method(String, "size", str_len)
class.define_method(String, "length", str_len)

class.define_method(String, "to_i", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end

    local self = state.get_register(0)
    assert(self.type == "string")

    local beg, _, strnum = self.value.str:find("(^%d+)")
    if beg == nil then
        state.set_register(0, value.autocast(0, "integer"))
        return
    end

    state.set_register(0, value.autocast(tonumber(strnum), "integer"))
end)

class.define_method(String, "to_f", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end

    local self = state.get_register(0)
    assert(self.type == "string")

    local beg, _, strnum = self.value.str:find("^(%d+%.%d+)")
    if beg == nil then
        state.set_register(0, value.autocast(0, "float"))
        return
    end

    state.set_register(0, value.autocast(tonumber(strnum), "float"))
end)

class.define_method(String, "to_s", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end

    local self = state.get_register(0)
    assert(self.type == "string")

    state.set_register(0, self)
end)

class.define_method(String, "<<", function(state: State, argc: number)
    if argc ~= 1 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end

    local self = state.get_register(0)
    assert(self.type == "string")

    local val = state.get_register(1)
    if val.type == "integer" then
        self.value.str ..= string.char(val.value.number)

    elseif val.type == "string" then
        self.value.str ..= val.value.str

    else
        -- TODO Call to_s of other types
        local value_type = if val.type == "object" then class.get_class(val.value).name else val.type:gsub("^%l", string.upper)
        err.raise(state.vm, error_class.TypeError, `no implicit conversion of {value_type} into String (calling of to_s isn't implemented yet)`)
        return
    end

    state.set_register(0, self)
end)

class.define_method(String, "[]", function(state: State, argc: number)
    if argc ~= 1 or argc ~= 2 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1..2)`)
        return
    end

    local self = state.get_register(0)
    assert(self.type == "string")

    local start_idx: number
    local end_idx: number
    
    local val1 = state.get_register(1)
    if val1.type == "integer" or val1.type == "float" then
        start_idx = math.floor(val1.value.number) + 1
    else
        -- TODO Call to_s of other types
        local value_type = if val1.type == "object" then class.get_class(val1.value).name else val1.type:gsub("^%l", string.upper)
        err.raise(state.vm, error_class.TypeError, `no implicit conversion of {value_type} into String (calling of to_s isn't implemented yet)`)
        return
    end

    if argc == 2 then
        local val2 = state.get_register(3)
        if val2.type == "integer" or val2.type == "float" then
            end_idx = math.floor(val2.value.number) + 1
        else
            -- TODO Call to_s of other types
            local value_type = if val2.type == "object" then class.get_class(val2.value).name else val1.type:gsub("^%l", string.upper)
            err.raise(state.vm, error_class.TypeError, `no implicit conversion of {value_type} into String (calling of to_s isn't implemented yet)`)
            return
        end
    else
        end_idx = start_idx
    end

    local substr = self.value.str:sub(start_idx, end_idx)
    state.set_register(0, {
        type = "string",
        value = str_new(substr)
    })
end)

return String