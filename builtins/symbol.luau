--!strict
local types = require("types")
local class = require("class")
local err = require("error")
local value = require("value")

local error_class = require("builtins/errors")
local object_class = require("builtins/object")

type VM = types.VM
type Value = types.Value
type Symbol = types.Symbol
type State = types.State
type String = types.String
type Class = types.Class

-- TODO Symbol class
local Symbol = class.define_class(nil, "Symbol", object_class)

return Symbol