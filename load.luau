--!strict
local types = require("types")
local opcodes = require("opcodes")
local symbol = require("symbol")

type ByteStream = types.ByteStream
type Proc = types.Proc
type IREP = types.IREP
type Instruction = types.Instruction
type CatchHandler = types.CatchHandler

local function read_binary_header(reader: ByteStream)
    -- TODO Don't use asserts
    assert(reader:read_string(4) == "RITE")
    assert(reader:read_string(2) == "03")
    
    -- Skip minor version as older minor versions are accepted
    reader:skip(2)

    assert(reader:read_byte(4) == reader:length())

    -- Skip the following:
    -- compiler name
    -- compiler version
    -- section ident
    -- section size
    -- rite version
    reader:skip(20) 
end

-- TODO Convert addresses into table
local function read_instructions(reader: ByteStream, length: number): { Instruction }
    local instructions: { Instruction } = {}
    local ext_type = 0
    local jmp_pc_adjustments: { Instruction } = {}

    local end_idx = reader.cursor + length
    while reader.cursor < end_idx do
        local where = reader.cursor
        local opcode = reader:read_byte()
        local op_name = opcodes.opcodes[opcode]
        assert(op_name ~= nil, `invalid opcode \`{opcode}'`)
        
        if op_name == "OP_EXT1" then
            ext_type = 1
            continue
        end

        if op_name == "OP_EXT2" then
            ext_type = 2
            continue
        end

        if op_name == "OP_EXT3" then
            ext_type = 3
            continue
        end

        local operand_types = opcodes.operands[opcode]
        local operands = {}
        
        for i = 1, #operand_types do
            local operand_type = operand_types[i]
            local operand: number

            if operand_type == "B" then
                operand = reader:read_byte()
                if i < 3 and bit32.band(i, ext_type) ~= 0 then
                    operand = bit32.bor(bit32.lshift(operand, 8), reader:read_byte())
                end

            elseif operand_type == "S" then
                operand = reader:read_byte(2)

            elseif operand_type == "W" then
                operand = reader:read_byte(3)

            end

            table.insert(operands, operand)
        end

        -- Reset ext_type to 0
        if ext_type ~= 0 then
            ext_type = 0
        end

        local inst = {
            opcode = opcode,
            operand = operands,
            where = where
        }
        -- Check if its a jump instruction and needs adjustments
        -- OP_JMP
        if inst.opcode == 0x25 then
            
        -- OP_JMP, OP_JMPIF, OP_JMPNOT, OP_JMPNIL
        elseif inst.opcode >= 0x26 and inst.opcode <= 0x28 then
            
        end

        table.insert(instructions, inst)
    end

    return instructions
end

local function read_catch_handlers(reader: ByteStream, length: number): { CatchHandler }
    local handlers: { CatchHandler } = {}

    while #handlers < length do
        local catch_type = if reader:read_byte() == 0 then "rescue" else "ensure"
        
        local handler: CatchHandler = {
            type = catch_type :: ("rescue" | "ensure"),
            beginning = reader:read_byte(4),
            ending = reader:read_byte(4),
            target = reader:read_byte(4)
        }

        table.insert(handlers, handler)
    end

    return handlers
end

local function read_pool(reader: ByteStream, length: number): { boolean | string | number }
    local pool: { boolean | string | number } = {}

    while #pool < length do
        local ptype = reader:read_byte()
        
        -- String
        if ptype == 0 then
            local str_len = reader:read_byte(2)
            table.insert(pool, reader:read_string(str_len))
            
            -- Skip \0 character (lua doesn't need it)
            reader:skip(1)

        -- int32
        elseif ptype == 1 then
            table.insert(pool, reader:read_byte(4))

        -- int64
        elseif ptype == 3 then
            table.insert(pool, reader:read_byte(8))

        -- float/double
        elseif ptype == 5 then
            local val = string.unpack("d", reader:read_string(8))
            table.insert(pool, val)

        -- bigint
        elseif ptype == 7 then
            -- TODO Support big int
            local len = reader:read_byte(2)
            table.insert(pool, reader:read_string(len))

            error("big int isn't supported")
        end
    end

    return pool
end

local function read_syms(reader: ByteStream, length: number): { number }
    local syms: { number } = {}

    while #syms < length do
        local len = reader:read_byte(2)
        local str = reader:read_string(len)

        -- Skip \0
        reader:skip(1)

        table.insert(syms, symbol.str_to_symid(str))
    end

    return syms
end

local function read_irep(reader: ByteStream): IREP
    -- Skip record size
    reader:skip(4)

    local irep = {} :: IREP
    irep.num_locals = reader:read_byte(2)
    irep.num_regs = reader:read_byte(2)
    
    local num_child_ireps = reader:read_byte(2)

    local num_catch_handler = reader:read_byte(2)
    
    local num_instructions = reader:read_byte(4)
    irep.num_instructions = num_instructions
    irep.inst_idx = reader.cursor
    irep.debug_instructions = read_instructions(reader, num_instructions)

    irep.catch_handlers = read_catch_handlers(reader, num_catch_handler)
    
    local pool_len = reader:read_byte(2)
    irep.pool = read_pool(reader, pool_len)

    local syms_len = reader:read_byte(2)
    irep.syms = read_syms(reader, syms_len)

    irep.children = {}
    for _ = 1, num_child_ireps do
        table.insert(irep.children, read_irep(reader))
    end

    return irep
end

local function load_bytecode(reader: ByteStream): IREP
    read_binary_header(reader)
    
    return read_irep(reader)
end

return {
    load_bytecode = load_bytecode,
    read_irep = read_irep
}