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

local Float = class.define_class(nil, "Float", object_class)

class.define_method(Float, "zero?", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local val = state.get_register(0)
    state.set_register(0, value.autocast(val.value.number == 0))
end)

class.define_method(Float, "nonzero?", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local val = state.get_register(0)
    state.set_register(0, value.autocast(val.value.number ~= 0))
end)

class.define_method(Float, "positive?", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local val = state.get_register(0)
    state.set_register(0, value.autocast(val.value.number > 0))
end)

class.define_method(Float, "negative?", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local val = state.get_register(0)
    state.set_register(0, value.autocast(val.value.number < 0))
end)

class.define_method(Float, "abs", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local val = state.get_register(0)
    state.set_register(0, value.autocast(math.abs(val.value.number), "float"))
end)
class.alias_method(Float, "magnitude", "abs")

class.define_method(Float, "abs2", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local val = state.get_register(0)
    state.set_register(0, value.autocast(math.abs(val.value.number) ^ 2, "float"))
end)

class.define_method(Float, "integer?", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    state.set_register(0, value.autocast(false))
end)

class.define_method(Float, "to_i", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end
    
    local self = state.get_register(0)
    state.set_register(0, value.autocast(math.floor(self.value.number), "integer`"))
end)
class.alias_method(Float, "to_int", "to_i")

class.define_method(Float, "to_f", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end
    
    -- Do nothing as it returns self
end)

class.define_method(Float, "inspect", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end
    
    local val = state.get_register(0)
    local new_str_val = class.instance_new(string_class);
    (new_str_val.value :: String).str = tostring(val.value.number)

    state.set_register(0, new_str_val)
end)
class.alias_method(Float, "to_s", "inspect")

class.define_method(Float, "div", function(state: State, argc: number)
    if argc > 1 or argc == 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end
    
    local self = state.get_register(0)
    local val = state.get_register(1)
    if val.type ~= "integer" and val.type ~= "float" then
        err.raise(state.vm, error_class.TypeError, `{val.value.name} can't be coerced into Float`)
        return
    end

    state.set_register(0, value.autocast(math.floor(self.value.number / val.value.number), "integer"))
end)

class.define_method(Float, "fdiv", function(state: State, argc: number)
    if argc > 1 or argc == 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end
    
    local self = state.get_register(0)
    local val = state.get_register(1)
    if val.type ~= "integer" and val.type ~= "float" then
        err.raise(state.vm, error_class.TypeError, `{val.value.name} can't be coerced into Float`)
        return
    end

    state.set_register(0, value.autocast(self.value.number / val.value.number, "float"))
end)
class.alias_method(Float, "quo", "fdiv")

class.define_method(Float, "ceil", function(state: State, argc: number)
    if argc > 1 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end
    
    local self = state.get_register(0)

    local ndigits = 0
    if argc > 0 then
        local val = state.get_register(1)
        if val.type ~= "integer" and val.type ~= "float" then
            err.raise(state.vm, error_class.TypeError, `{val.value.name} can't be coerced into Float`)
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

    state.set_register(0, value.autocast(ret, "float"))
end)

class.define_method(Float, "floor", function(state: State, argc: number)
    if argc > 1 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 1)`)
        return
    end
    
    local self = state.get_register(0)

    local ndigits = 0
    if argc > 0 then
        local val = state.get_register(1)
        if val.type ~= "integer" and val.type ~= "float" then
            err.raise(state.vm, error_class.TypeError, `{val.value.name} can't be coerced into Float`)
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

    state.set_register(0, value.autocast(ret, "float"))
end)

return Float