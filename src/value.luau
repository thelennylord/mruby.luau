--!strict
local class = require("class")
local types = require("types")

type Value = types.Value
type String = types.String
type Class = types.Class
type TrueClass = types.TrueClass
type FalseClass = types.FalseClass
type NilClass = types.NilClass
type Object = types.Object
type Integer = types.Integer
type Float = types.Float
type Symbol = types.Symbol
type IntegerValue = types.IntegerValue
type FloatValue = types.FloatValue
type SymbolValue = types.SymbolValue
type TrueValue = types.TrueValue
type FalseValue = types.FalseValue
type NilValue = types.NilValue
type StringValue = types.StringValue

-- Initialise the singleton true, false and nil value
local True: TrueValue = class.instance_new(class.builtins.TrueClass)
True.type = "true"

local False: FalseValue = class.instance_new(class.builtins.FalseClass)
False.type = "false"

local Nil: NilValue = class.instance_new(class.builtins.NilClass)
Nil.type = "nil"

-- Define conversion functions into their respective Ruby values
local function toboolean(value: boolean): TrueValue | FalseValue
	return if value then True else False
end

local function tostr(value: string): StringValue
	local str_val: StringValue = class.instance_new(class.builtins.String)
	str_val.value.str = value

	return str_val
end

local sym_literal_cache: { [string]: SymbolValue } = {}

local function tosymbol(value: string): SymbolValue
	if sym_literal_cache[value] == nil then
		local symbol_value: SymbolValue = class.instance_new(class.builtins.Symbol)
		symbol_value.type = "symbol"
		symbol_value.value.symbol = value
		sym_literal_cache[value] = symbol_value
	end

	return sym_literal_cache[value]
end

local int_literal_cache: { [number]: IntegerValue } = {}

local function tointeger(value: number): IntegerValue
	if int_literal_cache[value] == nil then
		local int_value: IntegerValue = class.instance_new(class.builtins.Symbol)
		int_value.type = "integer"
		int_value.value.number = value
		int_literal_cache[value] = int_value
	end

	return int_literal_cache[value]
end

local float_literal_cache: { [number]: FloatValue } = {}

local function tofloat(value: number): FloatValue
	if float_literal_cache[value] == nil then
		local float_value: FloatValue = class.instance_new(class.builtins.Symbol)
		float_value.type = "float"
		float_value.value.number = value
		float_literal_cache[value] = float_value
	end

	return float_literal_cache[value]
end

-- Util function for quick comparsion between ruby literals
local function compare(val1: Value, val2: Value): number
	if (val1.type == "integer" or val1.type == "float") and (val2.type == "integer" or val2.type == "float") then
		return val1.value.number - val2.value.number
	end

	error(`internal: compare for other types not implemented`)
end

return {
	compare = compare,

	tosymbol = tosymbol,
	toboolean = toboolean,
	tostr = tostr,
	tointeger = tointeger,
	tofloat = tofloat,
	nil_value = Nil,
	false_value = False,
	true_value = True,
}
