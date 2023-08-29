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
type Object = types.Object
type IREP = types.IREP
type Proc = types.Proc
type CallInfo = types.CallInfo
type Array = types.Array
type String = types.String
type Range = types.Range
type Integer = types.Integer
type Float = types.Float
type Hash = types.Hash
type Exception = types.Exception
type Symbol = types.Symbol
type ClassValue = types.ClassValue

-- Predefine builtin classes
local BasicObject: Class = {
    name = "BasicObject",
    sym_id = symbol.str_to_symid("BasicObject"),
    is_singleton = false,
    is_module = false,
    attached_object = nil,
    superclass = nil :: any,
    cvar = keyvalue.new(),
    ivar = keyvalue.new(),
    methods = {},
    definitions = {},
    subclasses = {},
    class = nil :: any
}

local Object: Class = {
    name = "Object",
    sym_id = symbol.str_to_symid("Object"),
    is_singleton = false,
    is_module = false,
    attached_object = nil,
    superclass = BasicObject,
    cvar = BasicObject.cvar,
    ivar = keyvalue.new(),
    methods = {},
    definitions = {},
    subclasses = {},
    class = nil :: any
}

local Module: Class = {
    name = "Module",
    sym_id = symbol.str_to_symid("Module"),
    is_singleton = false,
    is_module = false,
    attached_object = nil,
    superclass = Object,
    cvar = Object.cvar,
    ivar = keyvalue.new(),
    methods = {},
    definitions = {},
    subclasses = {},
    class = nil :: any
}

local Class: Class = {
    name = "Class",
    sym_id = symbol.str_to_symid("Class"),
    is_singleton = false,
    is_module = false,
    attached_object = nil,
    superclass = Module,
    cvar = Module.cvar,
    ivar = keyvalue.new(),
    methods = {},
    definitions = {},
    subclasses = {},
    class = nil :: any
}

-- Set their classes to Class 
BasicObject.class = Class
Object.class = Class
Module.class = Class
Class.class = Class

-- and save them to the consts table
global.consts.set(BasicObject.sym_id, {
    type = "class",
    value = BasicObject
})

global.consts.set(Object.sym_id, {
    type = "class",
    value = Object
})

global.consts.set(Module.sym_id, {
    type = "class",
    value = Module
})

global.consts.set(Class.sym_id, {
    type = "class",
    value = Class
})

local function define_class_under(vm: VM, outer: Class, name: string, super: Class): Class
    assert(outer ~= nil)
    assert(name ~= nil)
    
    local sym_id = symbol.str_to_symid(name)
    local val = global.consts.get_class_const(outer, sym_id)
    
    if val ~= nil then
        assert(val.type == "class")
        return val.value
    end

    assert(super ~= nil)

    local class: Class = {
        name = name,
        sym_id = sym_id,
        is_singleton = false,
        is_module = false,
        attached_object = nil,
        superclass = super,
        cvar = if super then super.cvar else keyvalue.new(),
        ivar = keyvalue.new(),
        methods = {},
        definitions = {},
        subclasses = {},
        class = Class
    }

    table.insert(super.subclasses, class)

    global.consts.set_class_const(outer, sym_id, {
        type = "class",
        value = class
    })

    return class
end

local function define_class(vm: VM?, name: string, super: Class): Class
    assert(name ~= nil)

    -- if vm ~= nil and vm:get_register(0).type == "class" then
    --     assert(vm.target_class == vm:get_register(0).value)
        
    --     return define_class_under(vm, vm.target_class, name, super)
    -- end
    
    local sym_id = symbol.str_to_symid(name)
    local val = global.consts.get(sym_id)
    if val ~= nil then
        assert(val.type == "class")
        return val.value
    end
    
    assert(super ~= nil)

    local class: Class = {
        name = name,
        sym_id = sym_id,
        is_singleton = false,
        is_module = false,
        attached_object = nil,
        superclass = super,
        cvar = super.cvar, -- TODO Make this compliant with CRuby
        ivar = keyvalue.new(),
        methods = Class.definitions,
        subclasses = {},
        definitions = {},
        class = Class
    }

    table.insert(super.subclasses, class)

    global.consts.set(sym_id, {
        type = "class",
        value = class
    })

    return class
end

-- Predefine the other builtin classes
local BUILTIN_CLASSES: { [string]: Class } = {
    BasicObject = BasicObject,
    Object = Object,
    Module = Module,
    Class = Class,
    Exception = define_class(nil, "Exception", Object),
    FalseClass = define_class(nil, "FalseClass", Object),
    TrueClass = define_class(nil, "TrueClass", Object),
    NilClass = define_class(nil, "NilClass", Object),
    Integer = define_class(nil, "Integer", Object),
    Float = define_class(nil, "Float", Object),
    String = define_class(nil, "String", Object),
    Proc = define_class(nil, "Proc", Object),
    Range = define_class(nil, "Range", Object),
    Array = define_class(nil, "Array", Object),
    Hash = define_class(nil, "Hash", Object),
    Symbol = define_class(nil, "Symbol", Object),
}

local function get_class(obj: Object): Class
    local cls = obj.class
    while cls.is_singleton == true or cls.is_module == true do
        cls = cls.superclass
    end

    return cls
end

local function get_class_from_name(name: string): Class?
    local val = global.consts.get(symbol.str_to_symid(name)) :: ClassValue
    if val ~= nil then
        return val.value
    end

    return nil
end

local function get_singleton_class(obj: Object): Class
    local cls = obj.class
    if cls.is_singleton then
        return cls
    end

    -- Make singleton_class
    local singleton_class: Class = {
        name = cls.name,
        sym_id = cls.sym_id,
        is_singleton = true,
        is_module = false,
        attached_object = obj,
        superclass = cls,
        cvar = cls.cvar,
        ivar = keyvalue.new(),
        subclasses = cls.subclasses,
        methods = cls.definitions,
        definitions = {},
        class = Class
    }

    obj.class = singleton_class
    obj.methods = singleton_class.definitions
    return singleton_class
end

local function define_method(cls: Class, name: string, luafunc: LuaMethod)
    assert(cls ~= nil)
    local sym_id = symbol.str_to_symid(name)
    local method: Method = {
        type = "luafunc",
        sym_id = sym_id,
        value = luafunc
    } 

    cls.definitions[sym_id] = method
end

local function obj_kind_of(obj: Object, cls: Class): boolean
    local c = obj.class
    while c ~= nil do
        if c.name == cls.name then
            return true
        end
        
        c = c.superclass
    end
    
    return false
end

-- note: this is same as calling :allocate
local function instance_new<T>(cls: Class): T
    local instance: Object = {
        class = cls,
        methods = cls.definitions,
        ivar = keyvalue.new()
    }

    local obj_type = "object"
    if obj_kind_of(instance, BUILTIN_CLASSES.Array) then
        obj_type = "array"
        (instance :: Array).array = {}

    elseif obj_kind_of(instance, BUILTIN_CLASSES.Hash) then
        obj_type = "hash"
        (instance :: Hash).hash = {}

    elseif obj_kind_of(instance, BUILTIN_CLASSES.String) then
        obj_type = "string"
        (instance :: String).str = ""

    elseif obj_kind_of(instance, BUILTIN_CLASSES.Proc) then
        obj_type = "proc"
        (instance :: Proc).type = "block"

    elseif obj_kind_of(instance, BUILTIN_CLASSES.Range) then
        obj_type = "range"
        (instance :: Range).start = 0
        (instance :: Range).stop = 0

    elseif obj_kind_of(instance, BUILTIN_CLASSES.Exception) then
        obj_type = "exception"
        (instance :: Exception).call_nest = {}
        (instance :: Exception).method_id = 0
        (instance :: Exception).message = ""

    elseif obj_kind_of(instance, BUILTIN_CLASSES.Symbol) then
        obj_type = "symbol"
        (instance :: Symbol).sym_str = ""
        (instance :: Symbol).sym_id = -1
    end

    -- TODO Error for Integer, Class

    return {
        type = obj_type,
        value = instance
    } :: any
end

local function instance_setiv(instance: Value, sym_id: number, val: Value)
    assert(instance.type == "object")
    instance.value.ivar[sym_id] = val
end

local function instance_getiv(instance: Value, sym_id: number): Value?
    assert(instance.type == "object")

    return instance.value.ivar[sym_id]
end

local function get_method(obj: Object, sym_id: number): Method?
    local method = obj.methods[sym_id]
    if method then
        return method
    end

    local cls = obj.class
    while method == nil and cls ~= nil do
        method = cls.definitions[sym_id]
        cls = cls.superclass
    end

    return method
end

local function get_super_method(obj: Object, sym_id: number): Method?
    local cls = obj.class.superclass
    local method = nil
    while method == nil and cls ~= nil do
        method = cls.definitions[sym_id]
        cls = cls.superclass
    end

    return method
end

local function undefine_method(cls: Class, sym_id: number)
    cls.methods[sym_id] = false :: any
end

local function alias_method(cls: Class, alias_name: string, method_name: string)
    local method_id = symbol.str_to_symid(method_name)
    local alias_id = symbol.str_to_symid(alias_name)

    local method = get_method( { class = cls, methods = cls.definitions } :: Object, method_id)
    if method == nil then
        error(`undefined method '{symbol.symid_to_str(method_id)}' for class '{cls.name}'`)
        return
    end

    cls.definitions[alias_id] = method
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

local function include_module(cls: Class, module: Class)
    
end

local function define_module()
    
end

return {
    define_class = define_class,
    define_class_under = define_class_under,
    define_method = define_method,
    instance_new = instance_new,
    instance_setiv = instance_setiv,
    instance_getiv = instance_getiv,
    obj_kind_of = obj_kind_of,
    get_class_by_name = get_class_by_name,
    undefine_method = undefine_method,
    get_method = get_method,
    get_super_method = get_super_method,
    get_class = get_class,
    get_singleton_class = get_singleton_class,
    get_class_from_name = get_class_from_name,
    alias_method = alias_method,
    builtins = BUILTIN_CLASSES
}