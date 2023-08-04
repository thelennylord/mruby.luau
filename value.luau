--!strict
local types = require("types")
local class = require("class")

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

local static_values: { [boolean | string | "nil"]: Value } = {}

local function get_static_number(value: number, _type: "integer" | "float" | "symbol"): Value
    if _type == "integer" then
        local key = "i" .. value
        if static_values[key] == nil then
            local int = class.instance_new(class.get_class_from_name("Integer") :: Class).value :: Integer
            int.number = math.floor(value)
            
            static_values[key] = {
                type = "integer",
                value = int
            }
            
            table.freeze(int)
            table.freeze(static_values[key])
            
        end

        return static_values[key]
        
    elseif _type == "float" then
        local key = "f" .. value
        if static_values[key] == nil then
            local float = class.instance_new(class.get_class_from_name("Integer") :: Class).value :: Float
            float.number = value

            static_values[key] = {
                type = "float",
                value = float
            }

            table.freeze(float)
            table.freeze(static_values[key])
        end

        return static_values[key]

    elseif _type == "symbol" then
        local key = "s" .. value
        if static_values[key] == nil then
            local symbol = class.instance_new(class.get_class_from_name("Symbol") :: Class).value :: Symbol
            symbol.sym_id = value

            static_values[key] = {
                type = "symbol",
                value = symbol
            }

            table.freeze(symbol)
            table.freeze(static_values[key])
        end

        return static_values[key]
    end

    error(`could not determine value cast for number {value} (is it an integer or a float?)`)
end

local function compare(val1: Value, val2: Value): number
    if (val1.type == "integer" or val1.type == "float") and (val2.type == "integer" or val2.type == "float") then
        return val1.value.number - val2.value.number
    end
    
    error(`internal: compare for other types not implemented`)
end

-- Immediate values
local function autocast(value: any, _type: string?): Value
    local valType = type(value)

    if valType == "number" then
        assert(type(value) == "number")

        if _type == "integer" or _type == "float" or _type == "symbol" then
            return get_static_number(value, _type)
        end

    elseif valType == "boolean" then
        assert(type(value) == "boolean")

        if value == true and not static_values[true] then
            static_values[true] = {
                type = "true",
                value = class.instance_new(class.get_class_from_name("TrueClass") :: Class).value :: TrueClass
            }
        end

        if value == false and not static_values[false] then
            static_values[false] = {
                type = "false",
                value = class.instance_new(class.get_class_from_name("FalseClass") :: Class).value :: FalseClass
            }
        end

        return static_values[value]

    elseif valType == "nil" then
        if not static_values["nil"] then
            static_values["nil"] = {
                type = "nil",
                value = class.instance_new(class.get_class_from_name("NilClass") :: Class).value :: NilClass
            }
        end
        return static_values["nil"]
    end

    error("could not determine type to cast value into")
end

type autocast = (
    (value: boolean, _type: nil) -> { type: "true" | "false", value: boolean }
    | (value: number, _type: "integer") -> { type: "integer", value: number }
    | (value: number, _type: "float") -> { type: "float", value: number }
    | (value: number, _type: "symbol") -> { type: "symbol", value: number }
    | (value: nil, _type: nil) -> { type: "nil", value: nil }
)

return {
    compare = compare,
    autocast = autocast
}