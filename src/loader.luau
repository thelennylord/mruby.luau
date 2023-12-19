--!strict
local types = require("src/types")

type Proc = types.Proc
type IREP = types.IREP
type CatchHandler = types.CatchHandler

local function read_binary_header(buf: buffer)
	-- TODO Don't use asserts
	assert(buffer.readstring(buf, 0, 4) == "RITE")
	assert(buffer.readstring(buf, 4, 2) == "03")

	-- assert(reader:read_string(4) == "RITE")
	-- assert(reader:read_string(2) == "03")

	-- Skip minor version as older minor versions are accepted

	assert(buffer.readu32(buf, 8) == buffer.len(buf))
	--assert(reader:read_byte(4) == reader:length())

	-- Skip the following:
	-- compiler name
	-- compiler version
	-- section ident
	-- section size
	-- rite version
end

local function read_catch_handlers(buf: buffer, offset: number, length: number): ({ CatchHandler }, number)
	local handlers: { CatchHandler } = {}

	while #handlers < length do
		local catch_type = if buffer.readu8(buf, offset) == 0 then "rescue" else "ensure"

		local handler: CatchHandler = {
			type = catch_type :: "rescue" | "ensure",
			beginning = buffer.readu32(buf, offset + 1),
			ending = buffer.readu32(buf, offset + 5),
			target = buffer.readu32(buf, offset + 9),
		}

		table.insert(handlers, handler)
		offset += 13
	end

	return handlers, offset
end

local function read_pool(buf: buffer, offset: number, length: number): ({ boolean | string | number }, number)
	local pool: { boolean | string | number } = {}

	while #pool < length do
		local ptype = buffer.readu8(buf, offset)
		offset += 1

		-- String
		if ptype == 0 then
			local str_len = buffer.readu16(buf, offset)
			table.insert(pool, buffer.readstring(buf, offset + 2, str_len))

			-- Add 1 to skip NULL character
			offset += 4 + str_len + 1
			
		-- int32
		elseif ptype == 1 then
			table.insert(pool, buffer.readi32(buf, offset))
			offset += 4

		-- int64
		elseif ptype == 3 then
			local num, offset = string.unpack(`>I8`, buffer.tostring(buf), offset)
			table.insert(pool, num)

		-- float/double
		elseif ptype == 5 then
			table.insert(pool, buffer.readf64(buf, offset))
			offset += 8

		-- bigint
		elseif ptype == 7 then
			-- TODO Support big int
			local len = buffer.readu16(buf, offset)
			table.insert(pool, buffer.readstring(buf, offset + 2, len))

			error("big int isn't supported")
		end
	end

	return pool, offset
end

local function read_syms(buf: buffer, offset: number, length: number): ({ string }, number)
	local syms: { string } = {}

	while #syms < length do
		local len = buffer.readu16(buf, offset)
		local str = buffer.readstring(buf, offset + 2, len)
		-- Add 1 to skip NULL character
		offset += 2 + len + 1

		table.insert(syms, str)
	end

	return syms, offset
end

local function read_irep(buf: buffer, offset: number, debug: boolean): (IREP, number)
	-- Skip record size
	offset += 4

	local irep = {} :: IREP
	irep.num_locals = buffer.readu16(buf, offset)
	irep.num_regs = buffer.readu16(buf, offset + 2)

	local num_child_ireps = buffer.readu16(buf, offset + 4)

	local num_catch_handler = buffer.readu16(buf, offset + 6)

	local num_instructions = buffer.readu32(buf, offset + 8)
	irep.num_instructions = num_instructions
	irep.inst_idx = offset + 12

	offset += 12 + num_instructions
	irep.catch_handlers, offset = read_catch_handlers(buf, offset, num_catch_handler)

	local pool_len = buffer.readu16(buf, offset)
	irep.pool, offset = read_pool(buf, offset + 2, pool_len)

	local syms_len = buffer.readu16(buf, offset)
	irep.symbols, offset = read_syms(buf, offset + 2, syms_len)
	irep.children = {}
	for _ = 1, num_child_ireps do
		local children
		children, offset = read_irep(buf, offset, debug)
		table.insert(irep.children, children)
	end

	return irep, offset
end

local function load_bytecode(buf: buffer, debug: boolean): IREP
	read_binary_header(buf)

	return select(1, read_irep(buf, 32, debug))
end

return {
	load_bytecode = load_bytecode,
	read_irep = read_irep,
}
