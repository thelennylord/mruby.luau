--!strict
local types = require("types")

type Symbol = string

-- Map of string -> symbol_id (aka the index)
local str_symid_map: { [Symbol]: number } = {}

-- Table containing all the symbols
local symbols_index: { Symbol } = {}

local function new_sym_raw(str: string): number
    table.insert(symbols_index, str)
    str_symid_map[str] = #symbols_index

    return #symbols_index
end

local function clear_symbols()
    table.clear(symbols_index)
    table.clear(str_symid_map)
end

local function str_to_symid(str: string): number
    local id = str_symid_map[str]
    if id ~= nil then
        return id
    end

    return new_sym_raw(str)
end

local function symid_to_str(id: number): string?
    return symbols_index[id]
end

local function search_symid(str: string): number?
    return str_symid_map[str]
end

local function new_symbol(str: string): types.Value
    local id = str_to_symid(str)
    return { 
        type = "symbol",
        value = id
    }
end

local function make_nested_sym(sym_id1: number, sym_id2: number): string
    local buf = {}
    local size = 4 -- Assume symbol_id is int16

    for i = 1, size do
        local code = ("0"):byte(1) + bit32.band(sym_id2, 0x0f)
        sym_id2 = bit32.rshift(sym_id2, size)

        table.insert(buf, 1, string.char(code)) 
    end

    for i = 1, size do
        local code = ("0"):byte(1) + bit32.band(sym_id1, 0x0f)
        sym_id1 = bit32.rshift(sym_id1, size)

        table.insert(buf, 1, string.char(code)) 
    end

    return table.concat(buf)
end

local function is_nested_symid(id: number): boolean
    local str = symid_to_str(id)
    assert(str ~= nil)

    return ("0"):byte() <= str:byte(1, 1) and str:byte(1, 1) <= (("9"):byte() + 6) 
end

local function separate_nested_symid(id: number): (number, number)
    local str = symid_to_str(id)
    local size = 4

    assert(str ~= nil)
    assert(is_nested_symid(id))
    
    local id1 = 0
    for i = 1, size do
        id1 = bit32.lshift(id1, 4) + (str:byte(i, i) - ("0"):byte())
    end
    
    local id2 = 0
    for i = size + 1, size * 2 do
        id2 = bit32.lshift(id2, 4) + (str:byte(i, i) - ("0"):byte())
    end

    return id1, id2
end

-- TODO: Symbol class and methods

return {
    str_to_symid = str_to_symid,
    symid_to_str = symid_to_str,
    make_nested_sym = make_nested_sym,
    separate_nested_symid = separate_nested_symid,
    new_symbol = new_symbol,
    search_symid = search_symid,
    clear_symbols = clear_symbols,
}