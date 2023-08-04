--!strict
local types = require("types")
local object_class = require("builtins/object")
local class = require("class")

type VM = types.VM
type IREP = types.IREP
type Proc = types.Proc
type State = types.State

local Proc = class.define_class(nil, "Proc", object_class)

class.define_method(Proc, "initialize", function(state: State, argc: number)
    error("Proc intialization not implemented")
end)

class.define_method(Proc, "call", function(state: State, argc: number)
    local self = state.get_register(0)
    assert(self.type == "proc")

    local proc = self.value
    local callinfo_self = proc.callinfo_self
    local method_id = if callinfo_self ~= nil then callinfo_self.method_id else 0

    local callinfo = state.vm:push_callinfo(method_id or 0, state.current_self_idx - state.vm.current_self_idx, argc)
    
    if callinfo_self then
        callinfo.own_class = callinfo_self.own_class
    end

    state.vm.current_irep = proc.irep
    state.vm.inst.cursor = state.vm.current_irep.inst_idx
    state.vm.current_self_idx = state.current_self_idx
end)

return Proc