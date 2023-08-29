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
type IntegerValue = types.IntegerValue
type FloatValue = types.FloatValue
type SymbolValue = types.SymbolValue
type TrueValue = types.TrueValue
type FalseValue = types.FalseValue
type NilValue = types.NilValue

local singleton_instances: { [string]: Value } = {
    True = class.instance_new(class.builtins.TrueClass),
    False = class.instance_new(class.builtins.FalseClass),
    Nil = class.instance_new(class.builtins.NilClass)
}

(singleton_instances.True :: TrueValue).type = "true"
(singleton_instances.False:: FalseValue).type = "false"
(singleton_instances.Nil :: NilValue).type = "nil"

local function compare(val1: Value, val2: Value): number
    if (val1.type == "integer" or val1.type == "float") and (val2.type == "integer" or val2.type == "float") then
        return val1.value.number - val2.value.number
    end
    
    error(`internal: compare for other types not implemented`)
end

-- Immediate values
local function autocast(value: unknown, _type: string?): Value
    if type(value) == "boolean" then
        return if value then singleton_instances.True else singleton_instances.False

    elseif type(value) == "nil" then
        return singleton_instances.Nil
    
    elseif type(value) == "number" then
        if _type == "integer" then
            local key = "i" .. value
            if singleton_instances[key] == nil then
                local int_value: IntegerValue = class.instance_new(class.builtins.Integer)
                int_value.type = "integer"
                int_value.value.number = math.floor(value)
                singleton_instances[key] = int_value
            end
    
            return singleton_instances[key]
            
        elseif _type == "float" then
            local key = "f" .. value
            if singleton_instances[key] == nil then
                local float_value: FloatValue = class.instance_new(class.builtins.Float)
                float_value.type = "float"
                float_value.value.number = value
    
                singleton_instances[key] = float_value
            end
    
            return singleton_instances[key]
    
        elseif _type == "symbol" then
            local key = "s" .. value
            if singleton_instances[key] == nil then
                local symbol_value: SymbolValue = class.instance_new(class.builtins.Symbol)
                symbol_value.type = "symbol"
                symbol_value.value.sym_id = value
                singleton_instances[key] = symbol_value
            end
    
            return singleton_instances[key]
        end
    
        error(`could not determine value cast for number {value} (is it an integer or a float?)`)
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