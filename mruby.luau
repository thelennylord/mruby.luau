--!strict

local loader = require("src/loader")
local types = require("src/types")
local VM = require("src/vm")

type IREP = types.IREP
type ByteStream = types.ByteStream
type VM = types.VM

local function execute_bytecode(byte_string: string, debug: boolean)
    local irep: IREP = loader.load_bytecode(byte_string, debug)

    local vm: VM = VM.new(debug)
    vm:load(byte_string, irep)
    vm:run()
end

return execute_bytecode