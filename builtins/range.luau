--!strict
local types = require("types")
local class = require("class")
local object_class = require("builtins/object")

type VM = types.VM
type State = types.State

local Range = class.define_class(nil, "Range", object_class)

class.define_method(Range, "new", function(state: State, argc: number)
    
end)

return Range