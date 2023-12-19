--!strict

local loader = require("src/loader")
local types = require("src/types")
local VM = require("src/vm")

type IREP = types.IREP
type VM = types.VM

local function execute_bytecode(buf: buffer, debug: boolean)
    local irep: IREP = loader.load_bytecode(buf, debug)

    local vm: VM = VM.new(debug)
    vm:load(buf, irep)
    vm:execute()
end

return execute_bytecode