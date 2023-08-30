--!strict
local global = require("global")
local types = require("types")

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
	sym = "BasicObject",
	is_singleton = false,
	is_module = false,
	attached_object = nil,
	superclass = nil :: any,
	cvar = {},
	ivar = {},
	methods = {},
	definitions = {},
	subclasses = {},
	class = nil :: any,
}

local Object: Class = {
	name = "Object",
	sym = "Object",
	is_singleton = false,
	is_module = false,
	attached_object = nil,
	superclass = BasicObject,
	cvar = BasicObject.cvar,
	ivar = {},
	methods = {},
	definitions = {},
	subclasses = {},
	class = nil :: any,
}

local Module: Class = {
	name = "Module",
	sym = "Module",
	is_singleton = false,
	is_module = false,
	attached_object = nil,
	superclass = Object,
	cvar = Object.cvar,
	ivar = {},
	methods = {},
	definitions = {},
	subclasses = {},
	class = nil :: any,
}

local Class: Class = {
	name = "Class",
	sym = "Class",
	is_singleton = false,
	is_module = false,
	attached_object = nil,
	superclass = Module,
	cvar = Module.cvar,
	ivar = {},
	methods = {},
	definitions = {},
	subclasses = {},
	class = nil :: any,
}

-- Set their classes to Class
BasicObject.class = Class
Object.class = Class
Module.class = Class
Class.class = Class

-- and save them to the consts table
global.consts.set("BasicObject", {
	type = "class",
	value = BasicObject,
})

global.consts.set(Object.sym, {
	type = "class",
	value = Object,
})

global.consts.set(Module.sym, {
	type = "class",
	value = Module,
})

global.consts.set(Class.sym, {
	type = "class",
	value = Class,
})

local function define_class_under(vm: VM, outer: Class, name: string, super: Class): Class
	assert(outer ~= nil)
	assert(name ~= nil)

	local val = global.consts.get_class_const(outer, name)

	if val ~= nil then
		assert(val.type == "class")
		return val.value
	end

	assert(super ~= nil)

	local class: Class = {
		name = name,
		sym = name,
		is_singleton = false,
		is_module = false,
		attached_object = nil,
		superclass = super,
		cvar = if super then super.cvar else {},
		ivar = {},
		methods = {},
		definitions = {},
		subclasses = {},
		class = Class,
	}

	table.insert(super.subclasses, class)

	global.consts.set_class_const(outer, name, {
		type = "class",
		value = class,
	})

	return class
end

local function define_class(vm: VM?, name: string, super: Class): Class
	assert(name ~= nil)

	-- if vm ~= nil and vm:get_register(0).type == "class" then
	--     assert(vm.target_class == vm:get_register(0).value)

	--     return define_class_under(vm, vm.target_class, name, super)
	-- end

	local val = global.consts.get(name)
	if val ~= nil then
		assert(val.type == "class")
		return val.value
	end

	assert(super ~= nil)

	local class: Class = {
		name = name,
		sym = name,
		is_singleton = false,
		is_module = false,
		attached_object = nil,
		superclass = super,
		cvar = super.cvar, -- TODO Make this compliant with CRuby
		ivar = {},
		methods = Class.definitions,
		subclasses = {},
		definitions = {},
		class = Class,
	}

	table.insert(super.subclasses, class)

	global.consts.set(name, {
		type = "class",
		value = class,
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
	while cls.is_singleton or cls.is_module do
		cls = cls.superclass
	end

	return cls
end

local function get_singleton_class(obj: Object): Class
	local cls = obj.class
	if cls.is_singleton then
		return cls
	end

	-- Make singleton_class
	local singleton_class: Class = {
		name = cls.name,
		sym = cls.sym,
		is_singleton = true,
		is_module = false,
		attached_object = obj,
		superclass = cls,
		cvar = cls.cvar,
		ivar = {},
		subclasses = cls.subclasses,
		methods = cls.definitions,
		definitions = {},
		class = Class,
	}

	obj.class = singleton_class
	obj.methods = singleton_class.definitions
	return singleton_class
end

local function define_method(cls: Class, name: string, luafunc: LuaMethod)
	assert(cls ~= nil)
	local method: Method = {
		type = "luafunc",
		sym = name,
		value = luafunc,
	}

	cls.definitions[name] = method
end

local function obj_kind_of(obj: Object, cls: Class): boolean
	local c = obj.class
	while c do
		if c == cls then
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
		ivar = {},
	}

	local obj_type = "object"
	if obj_kind_of(instance, BUILTIN_CLASSES.Array) then
		obj_type = "array";
		(instance :: Array).array = {}
	elseif obj_kind_of(instance, BUILTIN_CLASSES.Hash) then
		obj_type = "hash";
		(instance :: Hash).hash = {}
	elseif obj_kind_of(instance, BUILTIN_CLASSES.String) then
		obj_type = "string";
		(instance :: String).str = ""
	elseif obj_kind_of(instance, BUILTIN_CLASSES.Proc) then
		obj_type = "proc";
		(instance :: Proc).type = "block"
	elseif obj_kind_of(instance, BUILTIN_CLASSES.Range) then
		obj_type = "range";
		(instance :: Range).start = 0;
		(instance :: Range).stop = 0
	elseif obj_kind_of(instance, BUILTIN_CLASSES.Exception) then
		obj_type = "exception";
		(instance :: Exception).call_nest = {};
		(instance :: Exception).method_sym = "?";
		(instance :: Exception).message = ""
	end

	-- TODO Error for Integer, Class

	return {
		type = obj_type,
		value = instance,
	} :: any
end

local function instance_setiv(instance: Value, sym: string, val: Value)
	assert(instance.type == "object")
	instance.value.ivar[sym] = val
end

local function instance_getiv(instance: Value, sym: string): Value?
	assert(instance.type == "object")

	return instance.value.ivar[sym]
end

local function get_method(obj: Object, sym: string): Method?
	local method = obj.methods[sym]
	local cls = obj.class

	while method == nil and cls ~= nil do
		method = cls.definitions[sym]
		cls = cls.superclass
	end

	return method
end

local function get_super_method(obj: Object, sym: string): Method?
	local cls = obj.class.superclass
	local method = nil
	while method == nil and cls ~= nil do
		method = cls.definitions[sym]
		cls = cls.superclass
	end

	return method
end

local function undefine_method(cls: Class, sym: string)
	cls.methods[sym] = false :: any
end

local function alias_method(cls: Class, alias_name: string, method_name: string)
	local method = get_method({ class = cls, methods = cls.definitions } :: any, method_name)
	if method == nil then
		error(`undefined method '{method_name}' for class '{cls.name}'`)
		return
	end

	cls.definitions[alias_name] = method
end

local function get_class_by_name(name: string): Class?
	local obj: Value = global.consts.get(name)
	if obj == nil or obj.type ~= "class" then
		return nil
	end

	return obj.value
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
	alias_method = alias_method,
	builtins = BUILTIN_CLASSES,
}
