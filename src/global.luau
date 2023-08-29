-- Constant and global variable store
local types = require("types")
local keyvalue = require("keyvalue")
local symbol = require("symbol")

type Class = types.Class
type Value = types.Value
type KeyValue = types.KeyValue
type Symbol = types.Symbol

local consts: KeyValue = keyvalue.new()
local globals: KeyValue = keyvalue.new()

local function set_const(sym_id: number, value: Value)
    if consts[sym_id] ~= nil then
        -- TODO
        print(`warn: constant already initialised: {symbol.symid_to_str(sym_id)}`)
    end

    consts[sym_id] = value
end

local function get_const(sym_id: number): Value
    return consts[sym_id]
end


local function set_class_const(class: Class, sym_id: number, value: Value)
    local new_symid = symbol.make_nested_sym(class.sym_id, sym_id)

    if value.type == "class" then
        value.value.sym_id = new_symid
    end

    set_const(new_symid, value)
end

local function get_class_const(class: Class, sym_id: number): Value?
    local obj: Value? = nil

    while obj == nil and class ~= nil do
        local nested_symid = symbol.make_nested_sym(class.sym_id, sym_id)
        obj = consts[nested_symid]

        class = class.superclass
    end

    return obj
end

local function set_global(sym_id: number, value: Value)
    globals[sym_id] = value
end

local function get_global(sym_id: number): Value?
    return globals[sym_id]
end

return {
    consts = {
        set = set_const,
        get = get_const,
        get_class_const = get_class_const,
        set_class_const = set_class_const
    },

    globals = {
        set = set_global,
        get = get_global
    }
}
