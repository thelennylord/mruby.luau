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

local sym = symbol.str_to_symid

local function initialize_call(vm: VM, argc: number)
    local val = vm:get_register(1)
    local cls = class.find_class_by_object(val)

    local method = class.find_method(cls, sym("initialize"))
    if not method then
        -- TODO 
        return
    end

    if method.type == "luafunc" then
        method.value(vm, argc)
        return
    end

    local callinfo = vm:push_callinfo(sym("initialize"), 1, argc)
    callinfo.own_class = cls
    callinfo.prev = vm.callinfo_tail

    vm.callinfo_tail = callinfo
    vm.current_irep = method.value
    vm.inst.cursor = vm.current_irep.inst_idx
    --vm.current_reg_idx = vm.current_reg_idx
end

-- Define class
local Object = class.define_class(nil, "Object", nil :: any)

-- Methods
class.define_method(Object, "new", function(vm: VM, argc: number)
    local cls = vm:get_register(1)

    vm:set_register(1, class.instance_new(cls.value))
    initialize_call(vm, argc)
end)

class.define_method(Object, "!", function(vm: VM, argc: number)
    local cls = vm:get_register(1)

    local ret = value.autocast(cls.type == "nil" or cls.type == "false")
    vm:set_register(1, ret)
end)

class.define_method(Object, "!=", function(vm: VM, argc: number)
    local val1 = vm:get_register(1)
    local val2 = vm:get_register(2)

    local ret = value.autocast(value.compare(val1, val2) ~= 0)
    vm:set_register(1, ret)
end)

class.define_method(Object, "<=>", function(vm: VM, argc: number)
    local val1 = vm:get_register(1)
    local val2 = vm:get_register(2)

    local ret = value.autocast(value.compare(val1, val2), "integer")
    vm:set_register(1, ret)
end)

class.define_method(Object, "==", function(vm: VM, argc: number)
    local val1 = vm:get_register(1)
    local val2 = vm:get_register(2)

    local ret = value.autocast(value.compare(val1, val2) == 0)
    vm:set_register(1, ret)
end)

class.define_method(Object, "===", function(vm: VM, argc: number)
    local val1 = vm:get_register(1)
    local val2 = vm:get_register(2)

    local ret: Value
    if val1.type == "class" then
        ret = value.autocast(class.obj_kind_of(val2, val1.value))
    else
        ret = value.autocast(value.compare(val1, val2) == 0)
    end
    vm:set_register(1, ret)
end)

class.define_method(Object, "class", function(vm: VM, argc: number)
    local val1 = vm:get_register(1)

    local ret: Value = {
        type = "class",
        value = class.find_class_by_object(val1)
    } 

    vm:set_register(1, ret)
end)

class.define_method(Object, "dup", function(vm: VM, argc: number)
    local val1 = vm:get_register(1)

    local dup_instance = class.instance_new(val1.value.class)
    dup_instance.value.ivar = keyvalue.dup(val1.value.ivar)

    -- TODO Support Proc and Range
    vm:set_register(1, dup_instance)
end)

class.define_method(Object, "block_given?", function(vm: VM, argc: number)
    local callinfo = vm.callinfo_tail
    if callinfo == nil then
        vm:set_register(1, value.autocast(false))
        return
    end

    local offset = callinfo.current_reg_idx + callinfo.reg_offset

    local val1 = vm.registers[offset]
    if val1.type == "proc" then
        callinfo = val1.value.callinfo_self
        if callinfo == nil then
            vm:set_register(1, value.autocast(false))
            return
        end

        offset = callinfo.current_reg_idx + callinfo.reg_offset
    end

    local ret = vm.registers[offset + callinfo.num_args + 1].type == "proc"
    vm:set_register(1, value.autocast(ret))
end)

class.define_method(Object, "nil?", function(vm: VM, argc: number)
    vm:set_register(1, value.autocast(false))
end)


local kind_of = function(vm: VM, argc: number)
    local instance = vm:get_register(1)
    local cls = vm:get_register(2)
    if cls.type ~= "class" then
        -- TODO Raise error
        return
    end

    vm:set_register(1, value.autocast(class.obj_kind_of(instance, cls.value)))
end

class.define_method(Object, "kind_of?", kind_of)
class.define_method(Object, "is_a?", kind_of)

class.define_method(Object, "puts", function(vm: VM, argc: number)
    if argc > 0 then
        for i = 2, 1 + argc do
            local val = vm:get_register(i)
            assert(val.type == "string")
            print(val.value.str)
        end
    end

    vm:set_register(1, value.autocast(nil))
end)

return Object