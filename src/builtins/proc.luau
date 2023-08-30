--!strict
local types = require("types")
local class = require("class")

type VM = types.VM
type IREP = types.IREP
type Proc = types.Proc
type State = types.State

local Proc = class.define_class(nil, "Proc", nil :: any)

class.define_method(Proc, "initialize", function(state: State, argc: number)
    error("Proc intialization not implemented")
end)

class.define_method(Proc, "call", function(state: State, argc: number)
    local self = state.get_register(0)
    assert(self.type == "proc")

    local proc = self.value
    local embracing_callinfo = proc.embracing_callinfo

    --local callinfo = state.vm:push_callinfo(method_sym or 0, state.current_self_idx - state.vm.current_self_idx, argc)
    local callinfo = state.vm:enter_callinfo(
        embracing_callinfo.method_sym, 
        proc.irep, 
        state.vm.current_callinfo.target_class, 
        state.current_self_idx - state.vm.current_callinfo.self_reg_idx, 
        argc
    )

    if embracing_callinfo then
        callinfo.self_class = embracing_callinfo.self_class
    end
end)

return {}