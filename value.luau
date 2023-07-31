--!strict
local types = require("types")

type Value = types.Value
type String = types.String

local static_values: { [boolean | string | "nil"]: Value } = {
    [true] = {
        type = "true",
        value = true
    },

    [false] = {
        type = "false",
        value = false
    },

    ["nil"] = {
        type = "nil",
        value = nil
    }
}

local function get_static_number(value: number, _type: "integer" | "float"): Value
    if _type == "integer" then
        local key = "i" .. value
        if static_values[key] == nil then
            static_values[key] = {
                type = "integer",
                value = value
            }
        end

        return static_values[key]
        
    elseif _type == "float" then
        local key = "f" .. value
        if static_values[key] == nil then
            static_values[key] = {
                type = "float",
                value = value
            }
        end

        return static_values[key]
    end

    error(`could not determine value cast for number {value} (is it an integer or a float?)`)
end

local function compare(val1: Value, val2: Value): number
    if (val1.type == "integer" or val1.type == "float") and (val2.type == "integer" or val2.type == "float") then
        return val1.value - val2.value
    end
    
    error(`internal: compare for other types not implemented`)
end

-- Immediate values
local function autocast(value: any, _type: string?): Value
    local valType = type(value)

    if valType == "number" then
        assert(type(value) == "number")
        
        if _type == "symbol" then
            return {
                type = "symbol",
                value = value -- TODO Replace with SymbolClass
            }

        elseif _type == "integer" or _type == "float" then
            return get_static_number(value, _type)
        end

    elseif valType == "boolean" then
        assert(type(value) == "boolean")

        return static_values[value]

    elseif valType == "nil" then
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