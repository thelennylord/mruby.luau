--!strict
local types = require("types")
local class = require("class")
local keyvalue = require("keyvalue")
local value = require("value")
local err = require("error")
local error_class = require("builtins/errors")
local object_class = require("builtins/object")

type VM = types.VM
type Value = types.Value
type Array = types.Array
type State = types.State

local Array = class.define_class(nil, "Array", object_class)

class.define_method(Array, "new", function(state: State, argc: number)
    local new_arr: Array = {
        class = Array,
        ivar = keyvalue.new(),
        array = {}
    }

    -- Array.new()
    if argc == 0 then
        state.set_register(0, {
            type = "array",
            value = new_arr
        })
        return
    end

    -- Array.new(number)
    if argc > 1 then
        local val = state.get_register(0)
        if val.type == "integer" and val.value > 0 then
            new_arr.array = table.create(val.value, value.autocast(nil))

        elseif val.type == "array" then
            new_arr.array = val.value.array

        else
            local value_type = if val.type == "object" then val.value.class.name else val.type:gsub("^%l", string.upper)
            err.raise(state.vm, error_class.TypeError, `no implicit conversion of {value_type} into Integer`)
        end

        state.set_register(0, {
            type = "array",
            value = new_arr
        })
        return
    end

    -- Array.new(number, obj)
    if argc == 2 then
        local val1 = state.get_register(0)
        if val1.type == "integer" and val1.value > 0 then
            local val2 = state.get_register(1)
            new_arr.array = table.create(val1.value, val2.value)
        else
            local value_type = if val1.type == "object" then val1.value.class.name else val1.type:gsub("^%l", string.upper)
            err.raise(state.vm, error_class.TypeError, `no implicit conversion of {value_type} into Integer`)
        end

        state.set_register(0, {
            type = "array",
            value = new_arr
        })
        return
    end

    err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
end)

class.define_method(Array, "[]", function(state: State, argc: number)
    if argc == 0 or argc > 2 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1..2)`)
        return
    end

    local self = state.get_register(0)
    assert(self.type == "array")

    local idx = state.get_register(1)
    -- TODO Call to_int
    if idx.type ~= "integer" then
        local value_type = if idx.type == "object" then idx.value.class.name else idx.type:gsub("^%l", string.upper)
        err.raise(state.vm, error_class.TypeError, `no implicit conversion of {value_type} into Integer`)
        return
    end
    
    if argc == 1 then
        local val = self.value.array[idx.value + 1] or value.autocast(nil)
        state.set_register(0, val)
        return
    end

    local till = state.get_register(3)
    if till.type ~= "integer" then
        local value_type = if till.type == "object" then till.value.class.name else till.type:gsub("^%l", string.upper)
        err.raise(state.vm, error_class.TypeError, `no implicit conversion of {value_type} into Integer`)
        return
    end

    local new_arr: Array = {
        class = Array,
        ivar = keyvalue.new(),
        array = {}
    }

    table.move(self.value.array, idx.value + 1, idx.value + till.value + 1, 1, new_arr.array)

    state.set_register(0, {
        type = "array",
        value = new_arr
    })
end)

class.define_method(Array, "[]=", function(state: State, argc: number)
    if argc == 0 or argc > 2 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1..2)`)
        return
    end

    local self = state.get_register(0)
    assert(self.type == "array")

    local idx = state.get_register(1)
    -- TODO Call to_int
    if idx.type ~= "integer" then
        local value_type = if idx.type == "object" then idx.value.class.name else idx.type:gsub("^%l", string.upper)
        err.raise(state.vm, error_class.TypeError, `no implicit conversion of {value_type} into Integer`)
        return
    end
    
    if argc == 1 then
        local val = self.value.array[idx.value] or value.autocast(nil)
        state.set_register(0, val)
        return
    end

    local till = state.get_register(3)
    if till.type ~= "integer" then
        local value_type = if till.type == "object" then till.value.class.name else till.type:gsub("^%l", string.upper)
        err.raise(state.vm, error_class.TypeError, `no implicit conversion of {value_type} into Integer`)
        return
    end

    local new_arr: Array = {
        class = Array,
        ivar = keyvalue.new(),
        array = {}
    }

    table.move(self.value.array, idx.value + 1, idx.value + till.value + 1, 1, new_arr.array)

    state.set_register(0, {
        type = "array",
        value = new_arr
    })
end)

class.define_method(Array, "count", function(state: State, argc: number)
    local self = state.get_register(0)
    assert(self.type == "array")

    state.set_register(0, value.autocast(#self.value.array, "integer"))
end)

return Array