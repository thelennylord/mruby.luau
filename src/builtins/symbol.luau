--!strict
local types = require("types")
local class = require("class")
local err = require("error")
local value = require("value")
local symbol = require("symbol")

local error_class = require("builtins/errors")
local object_class = require("builtins/object")
local string_class = require("builtins/string")

type VM = types.VM
type Value = types.Value
type Symbol = types.Symbol
type State = types.State
type String = types.String
type Class = types.Class

-- TODO Symbol class
local Symbol = class.define_class(nil, "Symbol", object_class)

class.define_method(Symbol, "inspect", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local self = state.get_register(0)

    local str_val = class.instance_new(string_class);
    (str_val.value :: String).str = ":" .. symbol.symid_to_str((self.value :: Symbol).sym_id) :: string

    state.set_register(0, str_val)
end)

class.define_method(Symbol, "to_s", function(state: State, argc: number)
    if argc > 0 then
        err.raise(state.vm, error_class.ArgumentError, `wrong number of arguments (given {argc}, expected 0)`)
        return
    end

    local self = state.get_register(0)

    local str_val = class.instance_new(string_class);
    (str_val.value :: String).str = symbol.symid_to_str((self.value :: Symbol).sym_id) :: string

    state.set_register(0, str_val)
end)

return Symbol