--!strict
local class = require("class")
local types = require("types")
local value = require("value")
local symbol = require("symbol")
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
            attr_name = symbol.symid_to_str(val.value.sym_id) :: string
        else
            exception.raise(state.vm, exception.TypeError, `#<{val.value.class.name}:{tostring(val):sub(8)}> is not a symbol nor a string`)
            return
        end
    
        local sym_id = symbol.str_to_symid(attr_name)
        class.define_method(self.value, attr_name, function(state: State, argc: number)
            local self = state.get_register(0)
    
            state.set_register(0, self.value.ivar[sym_id] or value.autocast(nil))
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
            attr_name = symbol.symid_to_str(val.value.sym_id) :: string
        else
            exception.raise(state.vm, exception.TypeError, `#<{val.value.class.name}:{tostring(val):sub(8)}> is not a symbol nor a string`)
            return
        end
    
        local sym_id = symbol.str_to_symid(attr_name)
        class.define_method(self.value, attr_name .. "=", function(state: State, argc: number)
            local self = state.get_register(0)
    
            self.value.ivar[sym_id] = state.get_register(i) or value.autocast(nil)
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
            attr_name = symbol.symid_to_str(val.value.sym_id) :: string
        else
            exception.raise(state.vm, exception.TypeError, `#<{val.value.class.name}:{tostring(val):sub(8)}> is not a symbol nor a string`)
            return
        end
    
        local sym_id = symbol.str_to_symid("@" .. attr_name)
        class.define_method(self.value, attr_name, function(state: State, argc: number)
            local self = state.get_register(0)
    
            state.set_register(0, self.value.ivar[sym_id] or value.autocast(nil))
        end)
        
        class.define_method(self.value, attr_name .. "=", function(state: State, argc: number)
            local self = state.get_register(0)
    
            self.value.ivar[sym_id] = state.get_register(i) or value.autocast(nil)
        end)
    end
end)

class.alias_method(Module, "attr", "attr_accessor")

return {}