--!strict
-- Object class
local types = require("types")
local class = require("class")
local value = require("value")
local keyvalue = require("keyvalue")

type LuaMethod = types.LuaMethod
type VM = types.VM
type Value = types.Value
type Method = types.Method
type Class = types.Class
type State = types.State
type String = types.String
type CallInfo = types.CallInfo
type ClassValue = types.ClassValue

-- An empty class of Object was already pre-defined in class.luau
local Object = class.define_class(nil, "Object", nil :: any)

-- Methods
class.define_method(Object, "!=", function(state: State, argc: number)
    local val1 = state.get_register(0)
    local val2 = state.get_register(1)

    local ret = value.autocast(value.compare(val1, val2) ~= 0)
    state.set_register(0, ret)
end)

class.define_method(Object, "<=>", function(state: State, argc: number)
    local val1 = state.get_register(0)
    local val2 = state.get_register(1)

    local ret = value.autocast(value.compare(val1, val2), "integer")
    state.set_register(0, ret)
end)

class.define_method(Object, "==", function(state: State, argc: number)
    local val1 = state.get_register(0)
    local val2 = state.get_register(1)

    local ret = value.autocast(value.compare(val1, val2) == 0)
    state.set_register(0, ret)
end)

class.define_method(Object, "inspect", function(state: State, argc: number)
    local self = state.get_register(0)

    local ret = class.instance_new(class.builtins.String);
    (ret.value :: String).str = `#<{self.value.class.name}:{tostring(self):sub(8)}>`

    state.set_register(0, ret)
end)

class.alias_method(Object, "to_s", "inspect")

class.alias_method(Object, "object_id", "__id__")

class.define_method(Object, "===", function(state: State, argc: number)
    local val1 = state.get_register(0)
    local val2 = state.get_register(1)

    local ret: Value
    if val1.type == "class" then
        ret = value.autocast(class.obj_kind_of(val2.value, val1.value))
    else
        ret = value.autocast(value.compare(val1, val2) == 0)
    end
    state.set_register(0, ret)
end)

class.define_method(Object, "class", function(state: State, argc: number)
    local val1 = state.get_register(0)

    local ret: ClassValue = {
        type = "class",
        value = class.get_class(val1.value)
    } 

    state.set_register(0, ret)
end)

class.define_method(Object, "dup", function(state: State, argc: number)
    local val1 = state.get_register(0)

    local dup_instance = class.instance_new(val1.value.class)
    dup_instance.value.ivar = keyvalue.dup(val1.value.ivar)

    -- TODO Support Proc and Range
    state.set_register(0, dup_instance)
end)

class.define_method(Object, "block_given?", function(state: State, argc: number)
    if #state.vm.callinfo_stack == 0 then
        state.vm:set_register(0, value.autocast(false))
        return
    end
    
    local callinfo = state.vm.current_callinfo

    local self = state.get_register(0)
    if self.type == "proc" then
        callinfo = self.value.caller_callinfo :: CallInfo
        if callinfo == nil then
            state.set_register(0, value.autocast(false))
            return
        end
    end

    local ret = state.vm:get_register(callinfo.arg_count + 1).type == "proc"
    state.set_register(0, value.autocast(ret))
end)

class.define_method(Object, "nil?", function(state: State, argc: number)
    state.set_register(0, value.autocast(false))
end)

class.define_method(Object, "kind_of?", function(state: State, argc: number)
    local obj = state.get_register(0)
    local cls = state.get_register(1)
    if cls.type ~= "class" then
        -- TODO Raise
        return
    end

    state.set_register(0, value.autocast(class.obj_kind_of(obj.value, cls.value)))
end)

class.alias_method(Object, "is_a?", "kind_of?")

class.define_method(Object, "echo", function(state: State, argc: number)
    if argc > 0 then
        for i = 1, argc do
            local val = state.get_register(i)
            assert(val.type == "string", `internal: echo only supports string value`)

            print(val.value.str)
        end
    end

    state.set_register(0, state.get_register(argc))
end)

return {}