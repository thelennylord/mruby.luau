--!strict
-- Object class
local types = require("types")
local symbol = require("symbol")
local class = require("class")
local value = require("value")
local keyvalue = require("keyvalue")

type LuaMethod = types.LuaMethod
type VM = types.VM
type Value = types.Value
type Method = types.Method
type Class = types.Class
type State = types.State

local sym = symbol.str_to_symid

local function initialize_call(state: State, argc: number)
    local val = state.get_register(0)
    local cls = class.find_class_by_object(val)

    local method = class.find_method(cls, sym("initialize"))
    if not method then
        -- TODO 
        return
    end

    if method.type == "luafunc" then
        method.value(state, argc)
        return
    end

    local callinfo = state.vm:push_callinfo(sym("initialize"), 1, argc)
    callinfo.own_class = cls

    state.vm.current_irep = method.value
    state.vm.inst.cursor = state.vm.current_irep.inst_idx
    --vm.current_self_idx = vm.current_self_idx
end

-- Define class
local Object = class.define_class(nil, "Object", nil :: any)

-- Methods
class.define_method(Object, "new", function(state: State, argc: number)
    local cls = state.get_register(0)

    state.set_register(0, class.instance_new(cls.value))
    initialize_call(state, argc)
end)

class.define_method(Object, "!", function(state: State, argc: number)
    local cls = state.get_register(0)

    local ret = value.autocast(cls.type == "nil" or cls.type == "false")
    state.set_register(0, ret)
end)

class.define_method(Object, "!=", function(state: State, argc: number)
    local val1 = state.get_register(0)
    local val2 = state.get_register(0)

    local ret = value.autocast(value.compare(val1, val2) ~= 0)
    state.set_register(0, ret)
end)

class.define_method(Object, "<=>", function(state: State, argc: number)
    local val1 = state.get_register(0)
    local val2 = state.get_register(0)

    local ret = value.autocast(value.compare(val1, val2), "integer")
    state.set_register(0, ret)
end)

class.define_method(Object, "==", function(state: State, argc: number)
    local val1 = state.get_register(0)
    local val2 = state.get_register(1)

    local ret = value.autocast(value.compare(val1, val2) == 0)
    state.set_register(0, ret)
end)

class.define_method(Object, "===", function(state: State, argc: number)
    local val1 = state.get_register(0)
    local val2 = state.get_register(1)

    local ret: Value
    if val1.type == "class" then
        ret = value.autocast(class.obj_kind_of(val2, val1.value))
    else
        ret = value.autocast(value.compare(val1, val2) == 0)
    end
    state.set_register(0, ret)
end)

class.define_method(Object, "class", function(state: State, argc: number)
    local val1 = state.get_register(0)

    local ret: Value = {
        type = "class",
        value = class.find_class_by_object(val1)
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
    local callinfo = state.vm.callinfo_tail
    if callinfo == nil then
        state.vm:set_register(0, value.autocast(false))
        return
    end

    local offset = callinfo.current_self_idx + callinfo.reg_offset

    local val1 = state.vm.registers[offset]
    if val1.type == "proc" then
        callinfo = val1.value.callinfo_self
        if callinfo == nil then
            state.set_register(0, value.autocast(false))
            return
        end

        offset = callinfo.current_self_idx + callinfo.reg_offset
    end

    -- TODO test
    local ret = state.vm.registers[offset + callinfo.num_args + 1].type == "proc"
    state.set_register(0, value.autocast(ret))
end)

class.define_method(Object, "nil?", function(state: State, argc: number)
    state.set_register(0, value.autocast(false))
end)


local kind_of = function(state: State, argc: number)
    local instance = state.get_register(0)
    local cls = state.get_register(1)
    if cls.type ~= "class" then
        -- TODO Raise error
        return
    end

    state.set_register(0, value.autocast(class.obj_kind_of(instance, cls.value)))
end

class.define_method(Object, "kind_of?", kind_of)
class.define_method(Object, "is_a?", kind_of)

class.define_method(Object, "puts", function(state: State, argc: number)
    if argc > 0 then
        for i = 1, argc do
            local val = state.get_register(i)
            assert(val.type == "string")
            print(val.value.str)
        end
    end

    state.set_register(0, value.autocast(nil))
end)

return Object