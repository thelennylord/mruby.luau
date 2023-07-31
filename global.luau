-- Constant and global variable store
local types = require("types")
local keyvalue = require("keyvalue")
local symbol = require("symbol")

type Class = types.Class
type Value = types.Value
type KeyValue = types.KeyValue

local consts: KeyValue = keyvalue.new()
local globals: KeyValue = keyvalue.new()

local function set_const(sym_id: number, value: Value)
    if consts[sym_id] ~= nil then
        -- TODO
        warn(`constant already initialised: {symbol.symid_to_str(sym_id)}`)
    end

    consts[sym_id] = value
end

local function get_const(sym_id: number): Value
    return consts[sym_id]
end


local function set_class_const(class: Class, sym_id: number, value: Value)
    local str = symbol.make_nested_sym(class.sym_id, sym_id)
    local id = symbol.new_symbol(str).value

    if value.type == "class" then
        value.value.sym_id = id
    end

    set_const(id, value)
end

local function get_class_const(class: Class, sym_id: number): Value?
    local res = consts[class.sym_id]
    if res ~= nil then
        return res
    end

    local str = symbol.make_nested_sym(class.sym_id, sym_id)
    local id = symbol.search_symid(str)
    if id == nil then
        return nil
    end

    return consts[id]
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
        get_class = get_class_const,
        set_class = set_class_const
    },

    globals = {
        set = set_global,
        get = get_global
    }
}
