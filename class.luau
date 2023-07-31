--!strict
local types = require("types")
local symbol = require("symbol")
local global = require("global")
local keyvalue = require("keyvalue")

type Class = types.Class
type VM = types.VM
type Value = types.Value
type LuaMethod = types.LuaMethod
type Method = types.Method
type Instance = types.Instance
type IREP = types.IREP
type Proc = types.Proc
type CallInfo = types.CallInfo

local function find_class_by_object(val: Value): Class
    if val.type == "class" then
        return val.value
    
    elseif val.type == "integer" or val.type == "float" or val.type == "symbol" then
        error("numeric/symbol class not implemented")
    end

    return val.value.class
end

local function define_class_under(vm: VM, outer: Class, name: string, super: Class): Class
    assert(outer ~= nil)
    assert(name ~= nil)
    assert(super ~= nil)
    
    local sym_id = symbol.str_to_symid(name)
    local val = global.consts.get_class(outer, sym_id)

    if val ~= nil then
        assert(val.type == "class")
        return val.value
    end

    local class: Class = {
        sym_id = sym_id,
        super = super,
        cvar = if super then super.cvar else keyvalue.new(),
        methods = {},
        name = name
    }

    global.consts.set_class(outer, sym_id, {
        type = "class",
        value = class
    })

    return class
end

local function define_class(vm: VM?, name: string, super: Class): Class
    -- if vm ~= nil and vm:get_register(1).type == "class" then
    --     assert(vm.target_class == vm:get_register(1).value)
        
    --     return define_class_under(vm, vm.target_class, name, super)
    -- end
    assert(name ~= nil)
    if name ~= "Object" then
        assert(super ~= nil)
    end

    local sym_id = symbol.str_to_symid(name)
    local val = global.consts.get(sym_id)
    if val ~= nil then
        assert(val.type == "class")        
        return val.value
    end

    local cls: Class = {
        sym_id = sym_id,
        super = super,
        cvar = if super then super.cvar else keyvalue.new(),
        methods = {},
        name = name
    }

    global.consts.set(sym_id, {
        type = "class",
        value = cls
    })

    return cls
end

local function define_method(cls: Class, name: string, luafunc: LuaMethod)
    assert(cls ~= nil)

    local sym_id = symbol.str_to_symid(name)
    local method: Method = {
        type = "luafunc",
        sym_id = sym_id,
        value = luafunc
    } 

    cls.methods[sym_id] = method
end

local function instance_new(cls: Class): { type: "object", value: Instance }
    local instance: Instance = {
        class = cls,
        data = {},
        ivar = keyvalue.new()
    }

    return {
        type = "object",
        value = instance
    }
end

local function instance_delete(val: Value)
    assert(val.type == "object")
    table.clear(val.value)
end

local function instance_setiv(instance: Value, sym_id: number, val: Value)
    assert(instance.type == "object")
    instance.value.ivar[sym_id] = val
end

local function instance_getiv(instance: Value, sym_id: number): Value
    assert(instance.type == "object")

    local val = instance.value.ivar[sym_id]
    if not val then
        return {
            type = "nil",
            value = nil
        }
    end

    return val
end

-- Proc
local function proc_new(vm: VM, irep: IREP, proc_type: string): Proc
    local proc = {
        type = proc_type,
        irep = irep,
        callinfo = vm.callinfo_tail
    }

    if proc_type == "block" and vm:get_register(1).type == "proc" then
        proc.callinfo_self = vm:get_register(1).value.callinfo_self
    else
        proc.callinfo_self = vm.callinfo_tail
    end

    return proc :: any
end

local function proc_delete(val: Value)
    assert(val.type == "proc")

    val.value = nil :: any
end

-- local function proc_get_top(proc: Proc): CallInfo?
--     local top: Proc
--     while true do
--         top = proc
--         if proc.type == "block" then
--             continue
--         end

--         return top.callinfo 
--     end

--     return nil
-- end

local function obj_kind_of(instance: Value, cls: Class): boolean
    local c = find_class_by_object(instance)
    while c ~= nil do
        if c == cls then
            return true
        end
        c = c.super
    end

    return false
end

local function find_method(cls: Class, sym_id: number): Method?
    while cls ~= nil do
        local method = cls.methods[sym_id]
        if method then
            return method
        end

        cls = cls.super
    end

    return nil
end

local function undefine_method(cls: Class, sym_id: number)
    while cls ~= nil do
        cls.methods[sym_id] = nil
        cls = cls.super
    end
end

local function get_class_by_name(name: string): Class?
    local sym_id = symbol.search_symid(name)
    if sym_id == nil then
        return nil
    end

    local obj: Value = global.consts.get(sym_id)
    if obj == nil then
        return nil
    end

    if obj.type ~= "class" then
        return nil
    end

    return obj.value
end

return {
    find_class_by_object = find_class_by_object,
    define_class = define_class,
    define_class_under = define_class_under,
    define_method = define_method,
    instance_new = instance_new,
    instance_delete = instance_delete,
    instance_setiv = instance_setiv,
    instance_getiv = instance_getiv,
    proc_new = proc_new,
    proc_delete = proc_delete,
    obj_kind_of = obj_kind_of,
    find_method = find_method,
    get_class_by_name = get_class_by_name,
    undefine_method = undefine_method,
    --proc_get_top= proc_get_top
}