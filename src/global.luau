-- Constant and global variable store
local symbol = require("symbol")
local types = require("types")

type Class = types.Class
type Value = types.Value
type Symbol = types.Symbol

local consts: { [string]: Value } = {}
local globals: { [string]: Value } = {}

local function set_const(sym: string, value: Value)
	if consts[sym] ~= nil then
		-- TODO
		print(`warn: constant already initialised: {sym}`)
	end

	consts[sym] = value
end

local function get_const(sym: string): Value
	return consts[sym]
end

local function set_class_const(class: Class, sym: string, value: Value)
	local new_sym = symbol.make_nested_sym(class.sym, sym)

	if value.type == "class" then
		value.value.sym = new_sym
	end

	set_const(new_sym, value)
end

local function get_class_const(class: Class, sym: string): Value?
	local obj: Value? = nil

	while obj == nil and class ~= nil do
		local nested_sym = symbol.make_nested_sym(class.sym, sym)
		obj = consts[nested_sym]

		class = class.superclass
	end

	return obj
end

local function set_global(sym: string, value: Value)
	globals[sym] = value
end

local function get_global(sym: string): Value?
	return globals[sym]
end

return {
	consts = {
		set = set_const,
		get = get_const,
		get_class_const = get_class_const,
		set_class_const = set_class_const,
	},

	globals = {
		set = set_global,
		get = get_global,
	},
}
