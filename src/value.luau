--!strict
local class = require("src/class")
local types = require("src/types")

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
local True: TrueValue = {
	type = "true",
	value = {
		class = class.builtins.TrueClass,
		methods = class.builtins.TrueClass.definitions,
		ivar = {},
	},
}

local False: FalseValue = {
	type = "false",
	value = {
		class = class.builtins.FalseClass,
		methods = class.builtins.FalseClass.definitions,
		ivar = {},
	},
}

local Nil: NilValue = {
	type = "nil",
	value = {
		class = class.builtins.NilClass,
		methods = class.builtins.NilClass.definitions,
		ivar = {},
	},
}

-- Define conversion functions into their respective Ruby values
local function toboolean(value: boolean): TrueValue | FalseValue
	return if value then True else False
end

local function tostr(value: string): StringValue
	local string_value: StringValue = {
		type = "string",
		value = {
			class = class.builtins.String,
			methods = class.builtins.String.definitions,
			ivar = {},
			str = value,
		},
	}

	return string_value
end

local sym_literal_cache: { [string]: SymbolValue } = {}

local function tosymbol(value: string): SymbolValue
	if sym_literal_cache[value] == nil then
		local symbol_value: SymbolValue = {
			type = "symbol",
			value = {
				class = class.builtins.Symbol,
				methods = class.builtins.Symbol.definitions,
				ivar = {},
				symbol = value,
			},
		}

		sym_literal_cache[value] = symbol_value
	end

	return sym_literal_cache[value]
end

-- Preallocate table for integers -1 and 0..7 as they are used in opcodes
local int_literal_cache: { [number]: IntegerValue } = table.create(9)

local function tointeger(value: number): IntegerValue
	if int_literal_cache[value] == nil then
		local int_value: IntegerValue = {
			type = "integer",
			value = {
				class = class.builtins.Integer,
				methods = class.builtins.Integer.definitions,
				ivar = {},
				number = value,
			},
		}

		int_literal_cache[value] = int_value
	end

	return int_literal_cache[value]
end

local float_literal_cache: { [number]: FloatValue } = {}

local function tofloat(value: number): FloatValue
	if float_literal_cache[value] == nil then
		local float_value: FloatValue = {
			type = "float",
			value = {
				class = class.builtins.Float,
				methods = class.builtins.Float.definitions,
				ivar = {},
				number = value,
			},
		}

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
