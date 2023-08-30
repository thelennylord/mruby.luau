--!strict
local class = require("class")
local exception = require("exception")
local types = require("types")
local value = require("value")

local Class = class.define_class(nil, "Class", nil :: any)

type State = types.State
type VM = types.VM
type Array = types.Array
type Object = types.Object
type ClassValue = types.ClassValue
type ArrayValue = types.ArrayValue

class.define_method(Class, "new", function(state: State, argc: number)
	local self = state.get_register(0)
	assert(self.type == "class")

	local cls = self.value
	state.set_register(0, class.instance_new(cls))

	local offset = state.current_self_idx - state.vm.current_callinfo.self_reg_idx
	state.vm:send_by_name("initialize", offset + 0, argc)
end)

class.define_method(Class, "allocate", function(state: State, argc: number)
	local self = state.get_register(0)
	assert(self.type == "class")

	local cls = self.value
	state.set_register(0, class.instance_new(cls))
end)

class.define_method(Class, "attached_object", function(state: State, argc: number)
	local cls = state.get_register(0)
	assert(cls.type == "class")

	if not cls.value.is_singleton then
		exception.raise(state.vm, exception.TypeError, `'{cls.value.name}' is not a singleton class`)
		return
	end

	state.set_register(0, {
		type = "object",
		value = cls.value.attached_object :: Object,
	})
end)

class.define_method(Class, "subclasses", function(state: State, argc: number)
	local self = state.get_register(0)
	assert(self.type == "class")

	local cls = self.value
	local new_arr_val: ArrayValue = class.instance_new(class.builtins.Array)
	local new_arr = new_arr_val.value

	for _, subclass in cls.subclasses do
		table.insert(new_arr.array, {
			type = "class",
			value = subclass :: any, -- typechecker keeps complaining
		})
	end

	state.set_register(0, new_arr_val)
end)

class.define_method(Class, "superclass", function(state: State, argc: number)
	local self = state.get_register(0)
	assert(self.type == "class")

	local cls = self.value
	if cls.superclass then
		state.set_register(0, {
			type = "class",
			value = cls.superclass,
		})
		return
	end

	state.set_register(0, value.nil_value)
end)

Class.methods = Class.definitions

return Class
