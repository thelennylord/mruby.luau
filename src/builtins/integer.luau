--!strict
local types = require("types")
local class = require("class")
local err = require("error")
local value = require("value")

local object_class = require("builtins/object")
local error_class = require("builtins/errors")
local string_class = require("builtins/string")

type State = types.State
type String = types.String

local Integer = class.define_class(nil, "Integer", object_class)

class.define_method(Integer, "zero?", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local val = state.get_register(0)
    state.set_register(0, value.autocast(val.value.number == 0))
end)

class.define_method(Integer, "nonzero?", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local val = state.get_register(0)
    state.set_register(0, value.autocast(val.value.number ~= 0))
end)

class.define_method(Integer, "positive?", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local val = state.get_register(0)
    state.set_register(0, value.autocast(val.value.number > 0))
end)

class.define_method(Integer, "negative?", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local val = state.get_register(0)
    state.set_register(0, value.autocast(val.value.number < 0))
end)

class.define_method(Integer, "abs", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local val = state.get_register(0)
    state.set_register(0, value.autocast(math.abs(val.value.number), "integer"))
end)

class.define_method(Integer, "abs2", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local val = state.get_register(0)
    state.set_register(0, value.autocast(math.abs(val.value.number) ^ 2, "integer"))
end)

class.define_method(Integer, "integer?", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    state.set_register(0, value.autocast(true))
end)

class.define_method(Integer, "even?", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local self = state.get_register(0)
    state.set_register(0, value.autocast(self.value.number % 2 == 0))
end)

class.define_method(Integer, "odd?", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local self = state.get_register(0)
    state.set_register(0, value.autocast(self.value.number % 2 == 1))
end)

class.define_method(Integer, "to_i", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end
    
    -- Do nothing since it returns itself
end)
class.alias_method(Integer, "to_int", "to_i")

class.define_method(Integer, "inspect", function(state: State, argc: number)
    if argc > 1 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0..1)`)
        return
    end
    
    local val = state.get_register(0)
    local new_str_val = class.instance_new(string_class);
    (new_str_val.value :: String).str = tostring(val.value.number)

    if argc == 1 then
        local val1 = state.get_register(1)
        if val1.type ~= "integer" and val1.type ~= "float" then
            err.raise(state.vm, error_class.TypeError, `no implicit conversion of {val1.value.class.name} into Integer`)
            return    
        end
        
        local base = math.round(val1.value.number)
        if base < 2 and base > 36 then
            err.raise(state.vm, error_class.ArgumentError, `invalid radix {base}`)
            return    
        end

        if base ~= 10 then
            local num = val.value.number
            local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
            local num_str = {}
            if num < 0 then
                table.insert(num_str, "-")
            end
    
            num = math.abs(num)
            repeat
                local digit = (num % base) + 1
                num = math.floor(num / base)
                table.insert(num_str, 1, digits:sub(digit, digit))
            until num == 0
            (new_str_val.value :: String).str = table.concat(num_str, "")
        end 
    end

    state.set_register(0, new_str_val)
end)
class.alias_method(Integer, "to_s", "inspect")

class.define_method(Integer, "succ", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end
    
    local self = state.get_register(0)
    state.set_register(0, value.autocast(self.value.number + 1, "integer"))
end)
class.alias_method(Integer, "next", "succ")

class.define_method(Integer, "div", function(state: State, argc: number)
    if argc > 1 or argc == 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end
    
    local self = state.get_register(0)
    local val = state.get_register(1)
    if val.type ~= "integer" and val.type ~= "float" then
        err.raise(state.vm, error_class.TypeError, `{class.get_class(val.value).name} can't be coerced into Integer`)
        return
    end

    state.set_register(0, value.autocast(math.floor(self.value.number / val.value.number), "integer"))
end)

class.define_method(Integer, "ceil", function(state: State, argc: number)
    if argc > 1 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end
    
    local self = state.get_register(0)

    local ndigits = 0
    if argc > 0 then
        local val = state.get_register(1)
        if val.type ~= "integer" and val.type ~= "float" then
            err.raise(state.vm, error_class.TypeError, `{class.get_class(val.value).name} can't be coerced into Integer`)
            return
        end
        
        ndigits = val.value.number
    end

    local ret: number
    if ndigits >= 0 then
        ret = self.value.number
    else
        ret = self.value.number - (self.value.number % -10^ndigits)
    end

    state.set_register(0, value.autocast(ret, "integer"))
end)

class.define_method(Integer, "floor", function(state: State, argc: number)
    if argc > 1 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end
    
    local self = state.get_register(0)

    local ndigits = 0
    if argc > 0 then
        local val = state.get_register(1)
        if val.type ~= "integer" and val.type ~= "float" then
            err.raise(state.vm, error_class.TypeError, `{class.get_class(val.value).name} can't be coerced into Integer`)
            return
        end
        
        ndigits = val.value.number
    end

    local ret: number
    if ndigits >= 0 then
        ret = self.value.number
    else
        ret = self.value.number - (self.value.number % -10^ndigits)
    end

    state.set_register(0, value.autocast(ret, "integer"))
end)

return Integer