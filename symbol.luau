--!strict
--local types = require("types")

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

local function make_nested_sym(sym_id1: number, sym_id2: number): number
    local sym1_str = symid_to_str(sym_id1)
    assert(sym1_str ~= nil)
    
    local sym2_str = symid_to_str(sym_id2)
    assert(sym2_str ~= nil)

    local nested_sym_str = sym1_str .. "::" .. sym2_str
    return str_to_symid(nested_sym_str)
end

local function is_nested_symid(id: number): boolean
    local str = symid_to_str(id)
    assert(str ~= nil)

    return str:find("::") ~= nil
end

local function separate_nested_symid(id: number): (number, number)
    local str = symid_to_str(id)
    assert(str ~= nil)

    local separated = str:split("::")

    return str_to_symid(separated[1]), str_to_symid(separated[2])
end

-- TODO: Symbol class and methods

return {
    str_to_symid = str_to_symid,
    symid_to_str = symid_to_str,
    make_nested_sym = make_nested_sym,
    is_nested_symid = is_nested_symid,
    separate_nested_symid = separate_nested_symid,
    search_symid = search_symid,
    clear_symbols = clear_symbols,
}