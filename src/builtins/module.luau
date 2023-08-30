--!strict
local class = require("class")
local types = require("types")
local value = require("value")
local exception = require("exception")

type VM = types.VM
type Value = types.Value
type State = types.State
type Class = types.Class

local Module = class.define_class(nil, "Module", nil :: any)

class.define_method(Module, "attr_reader", function(state: State, argc: number)
    local self = state.get_register(0)
    assert(self.type == "class")

    for i = 1, argc do      
        local val = state.get_register(i)
    
        local attr_name: string
        if val.type == "string" then
            attr_name = val.value.str
        elseif val.type == "symbol" then
            attr_name = val.value.symbol
        else
            exception.raise(state.vm, exception.TypeError, `#<{val.value.class.name}:{tostring(val):sub(8)}> is not a symbol nor a string`)
            return
        end
    
        class.define_method(self.value, attr_name, function(state: State, argc: number)
            local self = state.get_register(0)
    
            state.set_register(0, self.value.ivar[attr_name] or value.nil_value)
        end)
    end
end)

class.define_method(Module, "attr_writer", function(state: State, argc: number)
    local self = state.get_register(0)
    assert(self.type == "class")

    for i = 1, argc do        
        local val = state.get_register(i)
    
        local attr_name: string
        if val.type == "string" then
            attr_name = val.value.str
        elseif val.type == "symbol" then
            attr_name = val.value.symbol
        else
            exception.raise(state.vm, exception.TypeError, `#<{val.value.class.name}:{tostring(val):sub(8)}> is not a symbol nor a string`)
            return
        end
    
        class.define_method(self.value, attr_name .. "=", function(state: State, argc: number)
            local self = state.get_register(0)
    
            self.value.ivar[attr_name] = state.get_register(i) or value.nil_value
        end)
    end
end)

class.define_method(Module, "attr_accessor", function(state: State, argc: number)
    local self = state.get_register(0)
    assert(self.type == "class")

    for i = 1, argc do
        local val = state.get_register(i)
    
        local attr_name: string
        if val.type == "string" then
            attr_name = val.value.str
        elseif val.type == "symbol" then
            attr_name = val.value.symbol
        else
            exception.raise(state.vm, exception.TypeError, `#<{val.value.class.name}:{tostring(val):sub(8)}> is not a symbol nor a string`)
            return
        end
    
        local sym_id = "@" .. attr_name
        class.define_method(self.value, attr_name, function(state: State, argc: number)
            local self = state.get_register(0)
    
            state.set_register(0, self.value.ivar[sym_id] or value.nil_value)
        end)
        
        class.define_method(self.value, attr_name .. "=", function(state: State, argc: number)
            local self = state.get_register(0)
    
            self.value.ivar[sym_id] = state.get_register(i) or value.nil_value
        end)
    end
end)

class.alias_method(Module, "attr", "attr_accessor")

return {}