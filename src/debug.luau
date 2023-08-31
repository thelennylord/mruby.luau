--!strict
local opcodes = require("src/opcodes")
local types = require("src/types")

type ByteStream = types.ByteStream
type Value = types.Value
type Instruction = {
	opcode: number,
	operand: { number },
	where: number,
}

local function read_instructions(reader: ByteStream, length: number): { Instruction }
	local instructions: { Instruction } = {}
	local ext_type = 0
	--local jmp_pc_adjustments: { Instruction } = {}

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
			where = where,
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

local function print_irep(reader: ByteStream, irep: types.IREP, level: number, idx: number)
	local ident = string.rep("   ", level)

	print(`{ident}{idx}. IREP: `)
	print(`{ident}    No. of local variables: {irep.num_locals}`)
	print(`{ident}    No. of registers needed: {irep.num_regs}`)

	print(`{ident}    Pool:`)
	for i, v in irep.pool do
		if type(v) == "string" then
			print(`{ident}        {i}. "{v}"`)
		else
			print(`{ident}        {i}. {v}`)
		end
	end

	print(`{ident}    Catch Handlers:`)
	for i, v in irep.catch_handlers do
		print(`{ident}        {i}. type = {v.type}`)
		print(`{ident}           begin = {v.beginning}`)
		print(`{ident}           end = {v.ending}`)
		print(`{ident}           target = {v.target}`)
	end

	print(`{ident}    Symbols:`)
	for i, v in irep.symbols do
		print(`{ident}        {i}. "{v}"`)
	end

	reader.cursor = irep.inst_idx
	local instructions = read_instructions(reader, irep.num_instructions)

	print(`{ident}    Instructions (length: {#instructions}):`)

	for _, instruction in instructions do
		print(
			`{ident}        {instruction.where - irep.inst_idx}| {opcodes.opcodes[instruction.opcode]} {table.concat(instruction.operand, ", ")}`
		)
	end

	if #irep.children > 0 then
		print(`{ident}    Child IREPs ({#irep.children} children):`)
		for i, v in irep.children do
			print_irep(reader, v, level + 1, i)
		end
	end
end

local function obj_rep(obj: Value): string
	if obj.type == "integer" or obj.type == "float" then
		return tostring(obj.value.number)

	elseif obj.type == "true" then
		return "true"

	elseif obj.type == "false" then
		return "false"

	elseif obj.type == "symbol" then
		return ":" .. obj.value.symbol

	elseif obj.type == "class" then
		return obj.value.name .. ":Class"

	elseif obj.type == "nil" then
		return "nil"
		
	end

	return `#<{obj.value.class.name}:{string.sub(tostring(obj.value), #"table: " + 1)}>`
end

return {
	print_irep = print_irep,
	obj_rep = obj_rep
}
