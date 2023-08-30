--!strict
local function make_nested_sym(sym1: string, sym2: string): string
	assert(sym1 ~= nil)
	assert(sym2 ~= nil)

	local nested_sym_str = sym1 .. "::" .. sym2
	return nested_sym_str
end

local function is_nested_sym(sym: string): boolean
	assert(sym ~= nil)

	return sym:find("::") ~= nil
end

local function separate_nested_symid(sym: string): ...string
	assert(sym ~= nil)

	return table.unpack(string.split(sym, "::"))
end

return {
	make_nested_sym = make_nested_sym,
	is_nested_sym = is_nested_sym,
	separate_nested_symid = separate_nested_symid,
}
