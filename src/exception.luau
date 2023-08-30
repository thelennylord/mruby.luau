--!strict
local class = require("class")
local types = require("types")

type Exception = types.Exception
type VM = types.VM
type Class = types.Class
type Value = types.Value
type ExceptionValue = types.ExceptionValue

local function sub_exception_new(vm: VM, exc_class: Class): Exception
	assert(exc_class ~= nil)

	local val = class.instance_new(exc_class)
	local obj = val.value :: Exception

	-- TODO: verify if the modification works
	for i = #vm.callinfo_stack, 1, -1 do
		local callinfo = vm.callinfo_stack[i]
		local method_sym = callinfo.method_sym or "?"
		table.insert(obj.call_nest, method_sym)
	end

	return obj
end

local function exception_new(vm: VM, exc_class: Class, message: string): Value
	local ex = sub_exception_new(vm, exc_class)
	local ex_val: ExceptionValue = {
		type = "exception",
		value = ex,
	}

	ex.message = message or "Exception"

	return ex_val
end

local function raise(vm: VM, exc_class: Class, message: string)
	if vm ~= nil then
		local class = exc_class -- TODO Add RuntimeError class here
		vm.exception = exception_new(vm, class, message)
	else
		print(`Exception: {message or exc_class.sym} ({exc_class.sym})`)
	end
end

local function print_exception(val: Value)
	if val.type ~= "exception" then
		return
	end

	local exc = val.value
	local name = exc.class.sym

	print(`Exception: {exc.message or name} ({name})`)
end

local function print_exception_vm(vm: VM)
	if vm.exception.type ~= "exception" then
		return
	end

	local exc = vm.exception.value
	local name = exc.class.sym

	local str = `Exception:`
	if exc.method_sym then
		str ..= ` in \`{exc.method_sym}'`
	end

	str ..= ` {exc.message or name} ({name})\n`

	for _, v in exc.call_nest do
		str ..= `    in \`{v}'`
	end

	print(str)
end

local export: { [string]: any } = {}

-- Export functions
export.simple_print = print_exception
export.raise = raise
export.new = exception_new
export.print = print_exception_vm

-- Export built-in Exception classes
export.NoMemoryError = class.define_class(nil, "NoMemoryError", class.builtins.Exception)
export.NotImplementedError = class.define_class(nil, "NotImplementedError", class.builtins.Exception)
export.StandardError = class.define_class(nil, "StandardError", class.builtins.Exception)
export.ArgumentError = class.define_class(nil, "ArgumentError", export.StandardError)
export.IndexError = class.define_class(nil, "IndexError", export.StandardError)
export.NameError = class.define_class(nil, "NameError", export.StandardError)
export.NoMethodError = class.define_class(nil, "NoMethodError", export.NameError)
export.RangeError = class.define_class(nil, "RangeError", export.StandardError)
export.RuntimeError = class.define_class(nil, "RuntimeError", export.StandardError)
export.TypeError = class.define_class(nil, "TypeError", export.StandardError)
export.LocalJumpError = class.define_class(nil, "LocalJumpError", export.StandardError)
export.ZeroDivisionError = class.define_class(nil, "ZeroDivisionError", export.StandardError)

return export
