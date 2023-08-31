--!strict
local class = require("src/class")
local exception = require("src/exception")
local global = require("src/global")
local opcodes = require("src/opcodes")
local types = require("src/types")
local value = require("src/value")
local debuglib = require("src/debug")

-- Require definitions of the built-in classes
require("src/builtins/basic_object")
require("src/builtins/object")
require("src/builtins/array")
require("src/builtins/exception")
require("src/builtins/string")
require("src/builtins/proc")
require("src/builtins/hash")
require("src/builtins/class")
require("src/builtins/symbol")
require("src/builtins/integer")
require("src/builtins/float")
require("src/builtins/nilclass")
require("src/builtins/trueclass")
require("src/builtins/falseclass")
require("src/builtins/module")

type VM = types.VM
type IREP = types.IREP
type CallInfo = types.CallInfo
type Value = types.Value
type Proc = types.Proc
type Hash = types.Hash
type Array = types.Array
type String = types.String
type Exception = types.Exception
type Class = types.Class
type CatchHandler = types.CatchHandler
type ByteStream = types.ByteStream
type HashValue = types.HashValue
type SymbolValue = types.SymbolValue
type ExceptionValue = types.ExceptionValue
type ArrayValue = types.ArrayValue

--[[
    Helper functions

    They have been defined in this file so the Luau compiler can inline them
]]
local function proc_new(vm: VM, irep: IREP, proc_type: "block" | "lambda" | "method"): Proc
	local val = class.instance_new(class.builtins.Proc)
	local proc = val.value :: Proc
	proc.type = proc_type
	proc.irep = irep

	local self = vm:get_register(0)
	if proc_type == "block" and self.type == "proc" then
		proc.embracing_callinfo = self.value.embracing_callinfo
	else
		proc.embracing_callinfo = vm.current_callinfo
	end

	return proc
end

local function fetch_Z(vm: VM)
	vm.pc += 1
end

local function fetch_BB(vm: VM): (number, number)
	local A, B, updated_pos = string.unpack(
		`>I{if bit32.btest(vm.ext, 0x01) then 2 else 1}I{if bit32.btest(vm.ext, 0x02) then 2 else 1}`,
		vm.inst,
		vm.pc + 1
	)

	vm.pc = updated_pos

	return A, B
end

local function fetch_B(vm: VM): number
	local A, updated_pos = string.unpack(if bit32.btest(vm.ext, 0x01) then ">H" else ">B", vm.inst, vm.pc + 1)

	vm.pc = updated_pos

	return A
end

local function fetch_BBB(vm: VM): (number, number, number)
	local A, B, C, updated_pos = string.unpack(
		`>I{if bit32.btest(vm.ext, 0x01) then 2 else 1}I{if bit32.btest(vm.ext, 0x02) then 2 else 1}B`,
		vm.inst,
		vm.pc + 1
	)

	vm.pc = updated_pos

	return A, B, C
end

local function fetch_BS(vm: VM): (number, number)
	local A, B, updated_pos = string.unpack(`>{if bit32.btest(vm.ext, 0x01) then "H" else "B"}H`, vm.inst, vm.pc + 1)

	vm.pc = updated_pos
	return A, B
end

local function fetch_W(vm: VM): number
	local A, updated_pos = string.unpack(">I3", vm.inst, vm.pc + 1)
	vm.pc = updated_pos

	return A
end

local function fetch_Bs(vm: VM): (number, number)
	local A, B, updated_pos = string.unpack(`>{if bit32.btest(vm.ext, 0x01) then "H" else "B"}h`, vm.inst, vm.pc + 1)

	vm.pc = updated_pos
	return A, B
end

local function fetch_s(vm: VM): number
	local A, updated_pos = string.unpack(`>h`, vm.inst, vm.pc + 1)

	vm.pc = updated_pos
	return A
end

local function fetch_Bi(vm: VM): (number, number)
	local A, B, updated_pos = string.unpack(`>{if bit32.btest(vm.ext, 0x01) then "h" else "b"}i`, vm.inst, vm.pc + 1)

	vm.pc = updated_pos

	return A, B
end

--[[
	MRuby Virtual Machine
]]
local VM = {}
VM.__index = VM

function VM.new(debug_mode: boolean?): VM
	debug_mode = if debug_mode == nil then false else debug_mode

	local self = {
		ext = 0,
		debug_mode = debug_mode or false,
		should_stop = false,
		ensure_state = {
			ensuring = false,
		},
		exception = nil,
		callinfo_stack = {},
	}

	return setmetatable(self, VM) :: any
end

function VM.load(vm: VM, inst: string, irep: IREP)
	assert(inst ~= nil)
	assert(irep ~= nil)

	vm.registers = table.create(irep.num_regs)
	vm.registers[1] = class.instance_new(class.builtins.Object)

	vm.top_irep = irep
	vm.inst = inst
	vm.pc = irep.inst_idx

	vm.current_callinfo = {
		irep = irep,
		inst_cursor_pos = irep.inst_idx,
		self_reg_idx = 1,
		target_class = class.builtins.Object,
		self_class = nil,
		arg_count = 0,
		super_called = false,
		method_sym = "<top>",
		deleted_kargs = {},
		dead = false,
	}
end

function VM.get_self(vm: VM): Value
	local self = vm:get_register(0)
	if self.type == "proc" then
		local callinfo = self.value.embracing_callinfo
		if callinfo ~= nil then
			self = vm.registers[callinfo.self_reg_idx]
		else
			self = vm.registers[1]
		end

		assert(self.type ~= "proc")
	end

	return self
end

function VM.get_catch_handler(vm: VM, handler_type: string?): CatchHandler?
	if #vm.current_callinfo.irep.catch_handlers == 0 then
		return nil
	end

	local inst_rel = vm.pc - vm.current_callinfo.irep.inst_idx
	for _, handler in vm.current_callinfo.irep.catch_handlers do
		if handler.type == handler_type and handler.beginning < inst_rel and inst_rel <= handler.ending then
			return handler
		end
	end

	return nil
end

local CALL_MAXARGS = 15
function VM.send_by_name(vm: VM, sym: string, A: number, C: number, call_super: boolean)
	assert(sym ~= nil)
	assert(A ~= nil)
	assert(C ~= nil)

	call_super = if call_super == nil then false else call_super
	-- OP_SEND:
	--     R[a] = R[a].send(Syms[b], R[a+1].., R[a+n+1]:R[a+n+2]..) (c = n|k<<4)

	local current_self_idx = vm.current_callinfo.self_reg_idx
	local num_args = bit32.band(C, 0x0f)
	local num_kwargs = bit32.extract(C, 4, 4)
	local block_given = bit32.btest(C, 0x100)

	local args = table.create(num_args)

	-- Arguments are packed into an array, so unpack them
	if num_args == CALL_MAXARGS then
		local arg_array = vm:get_register(A + 1)
		assert(arg_array.type == "array")

		table.move(arg_array.value.array, 1, #arg_array.value.array, 1, args)
		vm.registers[A + 1] = nil
	elseif num_args > 0 then
		table.move(vm.registers, current_self_idx + A + 1, current_self_idx + A + num_args, 1, args)

		-- Clear registers
		for i = A + 1, A + num_args do
			vm:set_register(i, nil :: any)
		end
	end

	-- Convert keyword arguments into hash
	local kw_start = if num_args == CALL_MAXARGS then current_self_idx + A + 2 else current_self_idx + A + num_args + 1
	if num_kwargs > 0 then
		if num_kwargs ~= CALL_MAXARGS then
			local hash_val: HashValue = class.instance_new(class.builtins.Hash)
			local kw_hash = hash_val.value.hash

			for i = 0, num_kwargs * 2 - 1, 2 do
				local key = vm.registers[kw_start + i] :: types.SymbolValue
				local val = vm.registers[kw_start + i + 1]

				vm.registers[kw_start + i] = nil
				vm.registers[kw_start + i + 1] = nil

				kw_hash[value.tosymbol(key.value.symbol)] = val
			end

			table.insert(args, hash_val)
		else
			table.insert(args, vm.registers[kw_start])
			vm.registers[kw_start] = nil
		end
	end

	local proc_start = if num_kwargs == CALL_MAXARGS then kw_start + 1 else kw_start + num_kwargs * 2
	if block_given then
		table.insert(args, vm.registers[proc_start])
		vm.registers[proc_start] = nil
	end

	table.move(args, 1, #args, current_self_idx + A + 1, vm.registers)

	local obj = vm:get_register(A).value
	local cls = class.get_class(obj)

	local method = if call_super then class.get_super_method(obj, sym) else class.get_method(obj, sym)
	if not method then
		if call_super then
			exception.raise(vm, exception.NoMethodError, `no superclass method for {sym}`)
		else
			exception.raise(vm, exception.NoMethodError, `undefined local variable or method '{sym}' for {cls.name}`)
		end

		if vm.exception and #vm.callinfo_stack > 0 then
			vm.exception.method_sym = vm.current_callinfo.method_sym
		end

		return
	end

	if method.type == "luafunc" then
		--local old_idx = vm.current_self_idx
		local curr_idx = current_self_idx + A
		local statefunc = {
			get_register = function(register: number): Value
				assert(register >= 0)
				return vm.registers[curr_idx + register] :: Value
			end,

			set_register = function(register: number, val: Value)
				assert(register >= 0)
				assert(val ~= nil)
				vm.registers[curr_idx + register] = val
			end,

			send_by_name = function(sym: string, A: number, C: number, super: boolean?)
				vm:send_by_name(sym, curr_idx + A, C)
			end,

			vm = vm,
			current_self_idx = curr_idx,
		}

		method.value(statefunc, #args)

		if vm.exception and vm.exception.method_sym == "?" then
			vm.exception.method_sym = sym
		end

		-- Clear registers
		for i = A + 1, A + #args + 1 do
			vm:set_register(i, nil :: any)
		end

		return
	end

	local callinfo = vm:enter_callinfo(
		method.sym,
		method.value,
		vm.current_callinfo.target_class,
		A,
		if not block_given then #args else #args - 1
	)
	callinfo.self_class = cls
	callinfo.super_called = call_super
end

function VM.enter_callinfo(
	vm: VM,
	method_sym: string?,
	irep: IREP,
	target_class: Class,
	self_idx: number,
	arg_count: number
): CallInfo
	local callinfo: CallInfo = {
		irep = irep,
		inst_cursor_pos = irep.inst_idx,
		self_reg_idx = vm.current_callinfo.self_reg_idx + self_idx,
		target_class = target_class,
		self_class = nil,
		arg_count = arg_count,
		super_called = false,
		method_sym = method_sym or "?",
		deleted_kargs = {},
		dead = false,
	}

	-- Push current_callinfo to callinfo_stack
	vm.current_callinfo.inst_cursor_pos = vm.pc
	table.insert(vm.callinfo_stack, vm.current_callinfo)

	vm.current_callinfo = callinfo
	vm.pc = callinfo.inst_cursor_pos

	return callinfo
end

function VM.exit_callinfo(vm: VM)
	assert(vm.current_callinfo ~= nil)

	local callinfo = vm.current_callinfo

	-- Clear remaining registers starting from self_reg_idx + 1
	for i = callinfo.self_reg_idx + 1, callinfo.self_reg_idx + callinfo.irep.num_regs do
		vm.registers[i] = nil
	end

	callinfo.deleted_kargs = nil :: any
	callinfo.dead = true

	-- Restore VM to its state based on CallInfo
	local prev_callinfo = table.remove(vm.callinfo_stack)
	if prev_callinfo == nil then
		-- VM finished executing everything
		vm.should_stop = true
		return
	end

	vm.current_callinfo = prev_callinfo
	vm.pc = prev_callinfo.inst_cursor_pos
end

function VM.get_register(vm: VM, register: number)
	assert(register ~= nil)
	assert(register >= 0)

	return vm.registers[vm.current_callinfo.self_reg_idx + register]
end

function VM.set_register(vm: VM, register: number, value: Value)
	assert(register ~= nil)
	assert(register >= 0)

	vm.registers[vm.current_callinfo.self_reg_idx + register] = value
end

-- Operands: Z
local function op_nop(vm: VM)
	fetch_Z(vm)
end

-- R[a] = R[b]
-- Operands: BB
local function op_move(vm: VM)
	local A, B = fetch_BB(vm)

	vm:set_register(A, vm:get_register(B))
end

-- R[a] = Pool[b]
-- Operands: BB
local function op_loadl(vm: VM)
	local A, B = fetch_BB(vm)

	local pool_val = vm.current_callinfo.irep.pool[B + 1]
	local ret = if type(pool_val) == "number"
		then if math.floor(pool_val) == pool_val then value.tointeger(pool_val) else value.tofloat(pool_val)
		elseif type(pool_val) == "boolean" then value.toboolean(pool_val)
		else value.tostr(pool_val)

	vm:set_register(A, ret)
end

-- R[a] = mrb_int(b)
-- Operands: BB
local function op_loadi(vm: VM)
	local A, B = fetch_BB(vm)

	vm:set_register(A, value.tointeger(B))
end

-- R[a] = mrb_int(-b)
-- Operands: BB
local function op_loadineg(vm: VM)
	local A, B = fetch_BB(vm)

	vm:set_register(A, value.tointeger(-B))
end

-- R[a] = mrb_int(-1)
-- Operands: B
local int__1 = value.tointeger(-1)
local function op_loadi__1(vm: VM)
	local A = fetch_B(vm)

	vm:set_register(A, int__1)
end

-- R[a] = mrb_int(0)
-- Operands: B
local int_0 = value.tointeger(0)
local function op_loadi_0(vm: VM)
	local A = fetch_B(vm)

	vm:set_register(A, int_0)
end

-- R[a] = mrb_int(1)
-- Operands: B
local int_1 = value.tointeger(1)
local function op_loadi_1(vm: VM)
	local A = fetch_B(vm)

	vm:set_register(A, int_1)
end

-- R[a] = mrb_int(2)
-- Operands: B
local int_2 = value.tointeger(2)
local function op_loadi_2(vm: VM)
	local A = fetch_B(vm)

	vm:set_register(A, int_2)
end

-- R[a] = mrb_int(3)
-- Operands: B
local int_3 = value.tointeger(3)
local function op_loadi_3(vm: VM)
	local A = fetch_B(vm)

	vm:set_register(A, int_3)
end

-- R[a] = mrb_int(4)
-- Operands: B
local int_4 = value.tointeger(4)
local function op_loadi_4(vm: VM)
	local A = fetch_B(vm)

	vm:set_register(A, int_4)
end

-- R[a] = mrb_int(5)
-- Operands: B
local int_5 = value.tointeger(5)
local function op_loadi_5(vm: VM)
	local A = fetch_B(vm)

	vm:set_register(A, int_5)
end

-- R[a] = mrb_int(6)
-- Operands: B
local int_6 = value.tointeger(6)
local function op_loadi_6(vm: VM)
	local A = fetch_B(vm)

	vm:set_register(A, int_6)
end

-- R[a] = mrb_int(7)
-- Operands: B
local int_7 = value.tointeger(7)
local function op_loadi_7(vm: VM)
	local A = fetch_B(vm)

	vm:set_register(A, int_7)
end

-- R[a] = mrb_int16(b)
-- Operands: Bs
local function op_loadi16(vm: VM)
	local A, B = fetch_Bs(vm)

	vm:set_register(A, value.tointeger(B))
end

-- R[a] = mrb_int32( (b << 16) + c )
-- Operands: Bi
local function op_loadi32(vm: VM)
	local A, B = fetch_Bi(vm)

	vm:set_register(A, value.tointeger(B))
end

-- R[a] = Syms[b]
-- Operands: BB
local function op_loadsym(vm: VM)
	local A, B = fetch_BB(vm)

	local sym_id = vm.current_callinfo.irep.symbols[B + 1]
	vm:set_register(A, value.tosymbol(sym_id))
end

-- R[a] = nil
-- Operands: B
local function op_loadnil(vm: VM)
	local A = fetch_B(vm)

	vm:set_register(A, value.nil_value)
end

-- R[a] = self
-- Operands: B
local function op_loadself(vm: VM)
	local A = fetch_B(vm)

	vm:set_register(A, vm:get_self())
end

-- R[a] = true
-- Operands: B
local function op_loadt(vm: VM)
	local A = fetch_B(vm)

	vm:set_register(A, value.true_value)
end

-- R[a] = false
-- Operands: B
local function op_loadf(vm: VM)
	local A = fetch_B(vm)

	vm:set_register(A, value.false_value)
end

-- R[a] = getglobal(Syms[b])
-- Operands: BB
local function op_getgv(vm: VM)
	local A, B = fetch_BB(vm)

	local sym_id = vm.current_callinfo.irep.symbols[B + 1]
	local val = global.globals.get(sym_id)
	if val ~= nil then
		vm:set_register(A, val)
	else
		vm:set_register(A, value.nil_value)
	end
end

-- setglobal(Syms[b], R[a])
-- Operands: BB
local function op_setgv(vm: VM)
	local A, B = fetch_BB(vm)

	local sym_id = vm.current_callinfo.irep.symbols[B + 1]
	global.globals.set(sym_id, vm:get_register(A))
end

-- R[a] = Special[Syms[b]]
-- Operands: BB
local function op_getsv(vm: VM)
	local _A, _B = fetch_BB(vm)
	error("not implemented")
end

-- Special[Syms[b]] = R[a]
-- Operands: BB
local function op_setsv(vm: VM)
	local _A, _B = fetch_BB(vm)
	error("not implemented")
end

-- R[a] = ivget(Syms[b])
-- Operands: BB
local function op_getiv(vm: VM)
	local A, B = fetch_BB(vm)

	local sym_id = vm.current_callinfo.irep.symbols[B + 1]
	local self = vm:get_self()

	vm:set_register(A, self.value.ivar[sym_id] or value.nil_value)
end

-- ivset(Syms[b], R[a])
-- Operands: BB
local function op_setiv(vm: VM)
	local A, B = fetch_BB(vm)

	local sym_id = vm.current_callinfo.irep.symbols[B + 1]
	local self = vm:get_self()

	self.value.ivar[sym_id] = vm:get_register(A)
end

-- R[a] = cvget(Syms[b])
-- Operands: BB
local function op_getcv(vm: VM)
	local A, B = fetch_BB(vm)

	local sym_id = vm.current_callinfo.irep.symbols[B + 1]
	local self = vm:get_self()

	vm:set_register(A, self.value.class.cvar[sym_id])
end

-- cvset(Syms[b], R[a])
-- Operands: BB
local function op_setcv(vm: VM)
	local A, B = fetch_BB(vm)

	local sym = vm.current_callinfo.irep.symbols[B + 1]
	local self = vm:get_self()

	self.value.class.cvar[sym] = vm:get_register(A)
end

-- R[a] = constget(Syms[b])
-- Operands: BB
local function op_getconst(vm: VM)
	local A, B = fetch_BB(vm)

	local sym = vm.current_callinfo.irep.symbols[B + 1]

	local cls: Class = if vm.current_callinfo.self_class ~= nil
		then vm.current_callinfo.self_class
		else vm.current_callinfo.target_class

	local val = global.consts.get_class_const(cls, sym) or global.consts.get(sym)
	if val == nil then
		exception.raise(vm, exception.NameError, `uninitialized constant {sym}`)
		return
	end

	vm:set_register(A, val)
end

-- constset(Syms[b], R[a])
-- Operands: BB
local function op_setconst(vm: VM)
	local A, B = fetch_BB(vm)

	local value = vm:get_register(A)
	local sym = vm.current_callinfo.irep.symbols[B + 1]
	local self = vm:get_register(0)

	if self.type == "class" then
		global.consts.set_class_const(self.value, sym, value)
	else
		global.consts.set(sym, vm:get_register(A))
	end
end

-- R[a] = R[a]::Syms[b]
-- Operands: BB
local function op_getmcnst(vm: VM)
	local A, B = fetch_BB(vm)

	local val = vm:get_register(A)
	if val.type ~= "class" then
		-- TODO use val.to_s
		exception.raise(vm, exception.TypeError, `object is not a class/module`)
		return
	end

	local sym = vm.current_callinfo.irep.symbols[B + 1]

	local obj = global.consts.get_class_const(val.value, sym)
	if obj == nil then
		exception.raise(vm, exception.NameError, `uninitialized constant {val.value.sym}::{sym}`)
		return
	end

	vm:set_register(A, obj)
end

-- R[a+1]::Syms[b] = R[a]
-- Operands: BB
local function op_setmcnst(vm: VM)
	local A, B = fetch_BB(vm)

	local val1 = vm:get_register(A)

	local val2 = vm:get_register(A + 1)
	if val2.type ~= "class" then
		-- TODO use val1.to_s
		exception.raise(vm, exception.TypeError, `object is not a class/module`)
		return
	end

	local sym_id = vm.current_callinfo.irep.symbols[B + 1]
	global.consts.set_class_const(val2.value, sym_id, val1)
end

-- R[a] = uvget(b,c)
-- Operands: BBB
local function op_getupvar(vm: VM)
	local A, B, C = fetch_BBB(vm)

	local proc = vm:get_register(0)
	assert(proc.type == "proc")

	local callinfo = vm.callinfo_stack[#vm.callinfo_stack - C]
	assert(callinfo ~= nil)

	local val = vm.registers[callinfo.self_reg_idx + B]
	vm:set_register(A, val)
end

-- uvset(b,c,R[a])
-- Operands: BBB
local function op_setupvar(vm: VM)
	local A, B, C = fetch_BBB(vm)

	local proc = vm:get_register(0)
	assert(proc.type == "proc")

	local callinfo = vm.callinfo_stack[#vm.callinfo_stack - C]
	assert(callinfo ~= nil)

	vm.registers[callinfo.self_reg_idx + B] = vm:get_register(A)
end

-- R[a] = R[a][R[a+1]]
-- Operands: B
local function op_getidx(vm: VM)
	local A = fetch_B(vm)

	vm:send_by_name("[]", A, 1)
end

-- R[a][R[a+1]] = R[a+2]
-- Operands: B
local function op_setidx(vm: VM)
	local A = fetch_B(vm)
	vm:send_by_name("[]=", A, 2)
end

-- pc += a
-- Operands: s
local function op_jmp(vm: VM)
	local A = fetch_s(vm)
	vm.pc += A
end

-- if R[a] pc+=b
-- Operands: Bs
local function op_jmpif(vm: VM)
	local A, B = fetch_Bs(vm)

	local val = vm:get_register(A)
	if val.type ~= "false" then
		vm.pc += B
	end
end

-- if !R[a] pc+=b
-- Operands: Bs
local function op_jmpnot(vm: VM)
	local A, B = fetch_Bs(vm)

	local val = vm:get_register(A)
	if val.type == "false" or val.type == "nil" then
		vm.pc += B
	end
end

-- if R[a] == nil pc+=b
-- Operands: Bs
local function op_jmpnil(vm: VM)
	local A, B = fetch_Bs(vm)

	local val = vm:get_register(A)
	if val.type == "nil" then
		vm.pc += B
	end
end

-- unwind_and_jump_to(a)
-- Operands: s
local function op_jmpuw(vm: VM)
	local A = fetch_s(vm)

	local jump_inst_idx = vm.pc + A

	local handler = vm:get_catch_handler("ensure")
	if not handler then
		vm.pc = jump_inst_idx
		return
	end

	vm.pc = vm.current_callinfo.irep.inst_idx + handler.target
end

-- R[a] = exc
-- Operands: B
local function op_except(vm: VM)
	local A = fetch_B(vm)

	local exc_val: ExceptionValue = { type = "exception", value = vm.exception :: Exception }
	vm.exception = nil

	vm:set_register(A, exc_val)
end

-- R[b] = R[a].is_a?(R[b])
-- Operands: BB
local function op_rescue(vm: VM)
	local A, B = fetch_BB(vm)

	local val1 = vm:get_register(A)
	local val2 = vm:get_register(B)

	assert(val1.type == "exception")
	assert(val2.type == "class")

	local ret = class.obj_kind_of(val1.value, val2.value)
	vm:set_register(B, value.toboolean(ret))
end

-- raise(R[a]) if R[a]
-- Operands: B
local function op_raiseif(vm: VM)
	local A = fetch_B(vm)

	local val = vm:get_register(A)
	if val.type == "nil" then
		return
	end

	assert(val.type == "exception")
	vm.exception = val.value
end

-- R[a] = self.send(Syms[b],R[a+1]..,R[a+n+1]:R[a+n+2]..) (c=n|k<<4)
-- Operands: BBB
local function op_ssend(vm: VM)
	local A, B, C = fetch_BBB(vm)

	vm:set_register(A, vm:get_self())
	local sym = vm.current_callinfo.irep.symbols[B + 1]

	vm:send_by_name(sym, A, C)
end

-- R[a] = self.send(Syms[b],R[a+1]..,R[a+n+1]:R[a+n+2]..,&R[a+n+2k+1])
-- Operands: BBB
local function op_ssendb(vm: VM)
	local A, B, C = fetch_BBB(vm)

	vm:set_register(A, vm:get_self())
	local sym = vm.current_callinfo.irep.symbols[B + 1]

	vm:send_by_name(sym, A, bit32.bor(C, 0x100))
end

-- R[a] = R[a].send(Syms[b],R[a+1]..,R[a+n+1]:R[a+n+2]..) (c=n|k<<4)
-- Operands: BBB
local function op_send(vm: VM)
	local A, B, C = fetch_BBB(vm)

	local sym = vm.current_callinfo.irep.symbols[B + 1]
	vm:send_by_name(sym, A, C)
end

-- R[a] = R[a].send(Syms[b],R[a+1]..,R[a+n+1]:R[a+n+2]..,&R[a+n+2k+1])
-- Operands: BBB
local function op_sendb(vm: VM)
	local A, B, C = fetch_BBB(vm)

	local sym = vm.current_callinfo.irep.symbols[B + 1]
	vm:send_by_name(sym, A, bit32.bor(C, 0x100))
end

-- R[0] = self.call(frame.argc, frame.argv)
-- Operands: Z
local function op_call(vm: VM)
	fetch_Z(vm)
	error("not implemented")
end

-- R[a] = super(R[a+1],... ,R[a+b+1])
-- Operands: BB
local function op_super(vm: VM)
	local A, B = fetch_BB(vm)

	local callinfo = vm.current_callinfo
	if callinfo == nil or callinfo.target_class == nil or callinfo.method_sym == nil then
		exception.raise(vm, exception.NoMethodError, "super called outside of method")
		return
	end

	local self = vm:get_register(0)
	vm:set_register(A, self)
	vm:send_by_name(callinfo.method_sym, A, bit32.bor(B, 0x100), true)
end

-- R[a] = argument array (16=m5:r1:m5:d1:lv4)
-- Operands: BS
local function op_argary(vm: VM)
	local A, B = fetch_BS(vm)
	local m1_count = bit32.extract(B, 11, 5)
	local should_rest = bit32.btest(B, 0x400)
	local m2_count = bit32.extract(B, 5, 5)
	local dict = bit32.btest(B, 0x10)
	local lv = bit32.band(B, 0x0f)

	if vm.current_callinfo.method_sym == nil then
		exception.raise(vm, exception.NoMethodError, `super called outside of method`)
		return
	end

	local reg_idx = if lv == 0
		then vm.current_callinfo.self_reg_idx + 1
		else vm.callinfo_stack[#vm.callinfo_stack - lv - 1].self_reg_idx + 1

	-- Move all values of m1, *args and m2 arguments into a single array
	local ary_val: ArrayValue = class.instance_new(class.builtins.Array)
	local new_ary = ary_val.value
	table.move(vm.registers, reg_idx, reg_idx + m1_count - 1, 1, new_ary.array)

	reg_idx += m1_count

	if should_rest then
		local ary = vm.registers[reg_idx]
		assert(ary.type == "array", `expected Array but got {ary.type}`)

		table.move(ary.value.array, 1, #ary.value.array, #new_ary.array + 1, new_ary.array)
		reg_idx += 1

		if m2_count > 0 then
			table.move(vm.registers, reg_idx, reg_idx + m2_count - 1, #new_ary.array + 1, new_ary.array)
			reg_idx += m2_count
		end
	end

	vm:set_register(A, ary_val)

	if dict then
		local hash = vm.registers[reg_idx]
		assert(hash.type == "hash", `expected Hash but got {hash.type}`)

		-- Duplicate the kwarg hash along with deleted OP_KARG keys
		local dup_hash: HashValue = class.instance_new(class.builtins.Hash)
		for k, v in pairs(hash.value.hash) do
			dup_hash.value.hash[k] = v
		end

		for k, v in pairs(vm.current_callinfo.deleted_kargs) do
			dup_hash.value.hash[k] = v
		end

		vm:set_register(A + 1, dup_hash)
		reg_idx += 1
	end

	local proc = vm.registers[reg_idx]
	assert(proc.type == "proc" or proc.type == "nil", `expected Proc? but got {proc.type}`)
	vm:set_register(A + 2, proc)
end

-- arg setup according to flags (23=m5:o5:r1:m5:k5:d1:b1)
-- Operands: W
local function op_enter(vm: VM)
	local A = fetch_W(vm)
	local m1_count = bit32.extract(A, 18, 5)
	local optional_count = bit32.extract(A, 13, 5)
	local should_rest = bit32.btest(A, 0x1000)
	local m2_count = bit32.extract(A, 7, 5)
	local kwargs_count = bit32.extract(A, 2, 5)
	local should_dict = bit32.btest(A, 0x02)
	local check_block = bit32.btest(A, 0x01)

	assert(#vm.callinfo_stack > 0)

	local args_given = vm.current_callinfo.arg_count
	local reg_idx = m1_count + optional_count + 1

	if args_given < m1_count then
		-- TODO make it better
		exception.raise(
			vm,
			exception.ArgumentError,
			`wrong number of arguments (given {args_given}, expected {m1_count}+)`
		)
		return
	end

	-- Save proc or nil
	local proc = vm:get_register(args_given + 1)
	if proc == nil then
		proc = value.nil_value
	end

	if should_rest then
		-- Collect remaining values and put them in an array,
		-- until we reach a Hash, Proc or NilClass
		local new_arr_val: ArrayValue = class.instance_new(class.builtins.Array)
		local new_arr = new_arr_val.value

		do
			local i = reg_idx
			while true do
				local val = vm:get_register(i)
				if val == nil or val.type == "hash" or val.type == "proc" or val.type == "nil" then
					break
				end

				table.insert(new_arr.array, val)
				vm:set_register(i, nil :: any)
				i += 1
			end
		end

		vm:set_register(reg_idx, new_arr_val)
		reg_idx += 1

		-- Extract m2 arguments
		for i = #new_arr.array - m2_count + 1, #new_arr.array do
			vm:set_register(reg_idx, new_arr.array[i])
			new_arr.array[i] = nil
			reg_idx += 1
		end
	end

	-- Relocate Hash, if exists
	if kwargs_count > 0 or should_dict then
		local hash = vm:get_register(args_given) -- Last argument is the Hash
		assert(hash.type == "hash")

		vm:set_register(reg_idx, hash)
		reg_idx += 1
	end

	-- Relocate Proc, if it exists
	if check_block or proc.type == "proc" then
		vm:set_register(reg_idx, proc)
	else
		vm:set_register(reg_idx, value.nil_value)
	end
	reg_idx += 1

	-- Clear remaining unused values
	for i = reg_idx, reg_idx + args_given + 1 do
		vm:set_register(i, nil :: any)
	end

	-- Set new number of arguments (don't include proc)
	vm.current_callinfo.arg_count = reg_idx - 2

	-- Jump depending on the amount of optional arguments
	local jump_offset = args_given - m1_count
	if jump_offset > 0 then
		if jump_offset > optional_count then
			jump_offset = optional_count

			-- TODO understand this
			if
				not should_rest
				and (vm:get_register(0).type ~= "proc" or (vm:get_register(0).value :: Proc).type ~= "block")
			then
				exception.raise(vm, exception.ArgumentError, `wrong number of arguments`)
				return
			end
		end

		vm.pc += jump_offset * 3
	end
end

-- R[a] = kdict.key?(Syms[b])
-- Operands: BB
local function op_key_p(vm: VM)
	local A, B = fetch_BB(vm)

	assert(#vm.callinfo_stack > 0)

	local kdict = vm:get_register(vm.current_callinfo.arg_count)
	assert(kdict.type == "hash")

	local sym = vm.current_callinfo.irep.symbols[B + 1]

	for _, v in kdict.value.hash do
		if v.type == "symbol" and v.value.symbol == sym then
			vm:set_register(A, value.true_value)
			return
		end
	end

	vm:set_register(A, value.false_value)
end

-- raise unless kdict.empty?
-- Operands: Z
local function op_keyend(vm: VM)
	fetch_Z(vm)
	assert(#vm.callinfo_stack > 0)

	local kdict = vm:get_register(vm.current_callinfo.arg_count)
	assert(kdict.type == "hash")

	if #kdict.value.hash > 0 then
		-- TODO I'll probably have to change how hash is implemented lol
		exception.raise(vm, exception.ArgumentError, `unknown keyword: ???`)
	end
end

-- R[a] = kdict[Syms[b]]; kdict.delete(Syms[b])
-- Operands: BB
local function op_karg(vm: VM)
	local A, B = fetch_BB(vm)

	assert(#vm.callinfo_stack > 0)

	local kdict = vm:get_register(vm.current_callinfo.arg_count)
	assert(kdict.type == "hash")

	local sym = vm.current_callinfo.irep.symbols[B + 1]
	local sym_value = value.tosymbol(sym)
	local ret = kdict.value.hash[sym_value]

	if ret == nil then
		exception.raise(vm, exception.ArgumentError, `missing keyword: {sym}`)
		return
	end

	kdict.value.hash[sym_value] = nil
	vm.current_callinfo.deleted_kargs[sym_value] = ret

	vm:set_register(A, ret)
end

-- return R[a] (normal)
-- Operands: B
local function op_return(vm: VM)
	local A = fetch_B(vm)

	-- Jump to ensure if exists
	do
		local handler = vm:get_catch_handler("ensure")
		if handler then
			vm.pc = vm.current_callinfo.irep.inst_idx + handler.target
			return
		end
	end

	-- Ignore and stop the VM if it's a top level return
	if #vm.callinfo_stack == 0 then
		vm.should_stop = true
		return
	end

	local callinfo = vm.current_callinfo

	if vm.ensure_state.ensuring then
		-- Handle different cases for an explicit and implicit return in an ensure block
		-- The last instruction of a callinfo (aka OP_RETURN) is an implicit return
		if vm.pc == callinfo.irep.num_instructions then
			-- Implicit return
			while vm.ensure_state.target_callinfo ~= vm.current_callinfo do
				vm:exit_callinfo()

				local handler = vm:get_catch_handler("ensure")
				if handler then
					vm.pc = vm.current_callinfo.irep.inst_idx + handler.target
					return
				end
			end

			vm:set_register(0, vm.ensure_state.return_value)
			vm:exit_callinfo()
		else
			-- Explicit return
			vm.ensure_state.ensuring = false
			vm.ensure_state.target_callinfo = nil :: any
			vm.ensure_state.return_value = nil :: any
		end
	end

	-- Ignore initialize method's return as that always returns a new object of a Class (internally done via a lua function)
	if callinfo.method_sym ~= "initialize" then
		local ret = vm:get_register(A)
		vm:set_register(0, ret)
	end

	vm:exit_callinfo()
end

-- return R[a] (in-block return)
-- Operands: B
local function op_return_blk(vm: VM)
	local A = fetch_B(vm)
	local ret = vm:get_register(A)

	local self = vm:get_register(0)

	assert(self.type == "proc", `instruction OP_RETURN_BLK should be in a block`)
	local proc = self.value

	if vm.ensure_state.ensuring then
		-- The instruction should stop carrying forward return values from
		-- previous OP_BREAK and OP_RETURN_BLK, so we disable the ensure state

		vm.ensure_state.ensuring = false
		vm.ensure_state.target_callinfo = nil :: any
		vm.ensure_state.return_value = nil :: any
	end

	if proc.embracing_callinfo.dead then
		-- TODO Make the error message more clear
		exception.raise(vm, exception.LocalJumpError, `unexpected return`)
		return
	end

	-- Go back to the level where the proc was generated
	while proc.embracing_callinfo ~= vm.current_callinfo do
		-- Be sure to jump to ensures
		local handler = vm:get_catch_handler("ensure")
		if handler then
			vm.pc = vm.current_callinfo.irep.inst_idx + handler.target

			-- Enable the ensure state so the return value can carry forward
			vm.ensure_state.ensuring = true
			vm.ensure_state.return_value = ret
			vm.ensure_state.target_callinfo = proc.embracing_callinfo
			return
		end

		vm:exit_callinfo()
	end

	vm:set_register(0, ret)
	vm:exit_callinfo()
end

-- break R[a]
-- Operands: B
local function op_break(vm: VM)
	local A = fetch_B(vm)
	local ret = vm:get_register(A)

	local self = vm:get_register(0)
	if self.type ~= "proc" then
		-- TODO verify
		exception.raise(vm, exception.LocalJumpError, "unexpected break")
		return
	end

	local proc = self.value
	assert(proc.caller_callinfo ~= nil)

	if proc.type ~= "lambda" and proc.caller_callinfo.dead then
		exception.raise(vm, exception.LocalJumpError, `break from proc-closure`)
		return
	end

	if vm.ensure_state.ensuring then
		-- The instruction should stop carrying forward return values from
		-- previous OP_BREAK and OP_RETURN_BLK, so we disable the ensure state

		vm.ensure_state.ensuring = false
		vm.ensure_state.target_callinfo = nil :: any
		vm.ensure_state.return_value = nil :: any
	end

	-- If it's lambda, treat OP_BREAK as OP_RETURN
	local handler = vm:get_catch_handler("ensure")
	if proc.type == "lambda" then
		if handler then
			vm.pc = vm.current_callinfo.irep.inst_idx + handler.target
		else
			vm:set_register(0, ret)
			vm:exit_callinfo()
		end

		return
	end

	-- Loop for handling ensure
	while proc.caller_callinfo ~= vm.current_callinfo do
		handler = vm:get_catch_handler("ensure")
		if handler then
			vm.pc = vm.current_callinfo.irep.inst_idx + handler.target

			-- Enable the ensure state so the return value can carry forward
			vm.ensure_state.ensuring = true
			vm.ensure_state.return_value = ret
			vm.ensure_state.target_callinfo = proc.embracing_callinfo
			return
		end

		vm:exit_callinfo()
	end

	vm:set_register(0, ret)
	vm:exit_callinfo()
end

-- R[a] = block (16=m5:r1:m5:d1:lv4)
-- Operands: BS
local function op_blkpush(vm: VM)
	local A, B = fetch_BS(vm)

	local m1_count = bit32.extract(B, 11, 5)
	local rest = bit32.extract(B, 10)
	local m2_count = bit32.extract(B, 5, 5)
	local kd = bit32.extract(B, 4)
	local lv = bit32.extract(B, 0, 4)

	local offset = m1_count + rest + m2_count + kd + 1

	local block: Value
	if lv == 0 then
		block = vm:get_register(offset)
	else
		local proc = vm:get_register(0)
		if
			proc.type ~= "proc"
			or proc.value.embracing_callinfo == nil
			or proc.value.embracing_callinfo.irep.num_regs <= offset
		then
			exception.raise(vm, exception.LocalJumpError, `unexpected yield`)
			return
		end

		local callinfo = proc.value.embracing_callinfo
		block = vm.registers[callinfo.self_reg_idx + offset]
	end

	if block.type ~= "proc" then
		exception.raise(vm, exception.LocalJumpError, `unexpected yield`)
		return
	end

	vm:set_register(A, block)
end

-- R[a] = R[a] + R[a+1]
-- Operands: B
local function op_add(vm: VM)
	local A = fetch_B(vm)

	local val1 = vm:get_register(A)
	local val2 = vm:get_register(A + 1)

	if val1.type == "integer" then
		if val2.type == "integer" then
			vm:set_register(A, value.tointeger(val1.value.number + val2.value.number))
			return
		elseif val2.type == "float" then
			vm:set_register(A, value.tofloat(val1.value.number + val2.value.number))
			return
		end
	elseif val1.type == "float" and (val2.type == "integer" or val2.type == "float") then
		vm:set_register(A, value.tofloat(val1.value.number + val2.value.number))
		return
	end

	vm:send_by_name("+", A, 1)
end

-- R[a] = R[a] + mrb_int(b)
-- Operands: BB
local function op_addi(vm: VM)
	local A, B = fetch_BB(vm)

	local val = vm:get_register(A)

	if val.type == "integer" then
		vm:set_register(A, value.tointeger(val.value.number + B))
		return
	elseif val.type == "float" then
		vm:set_register(A, value.tofloat(val.value.number + B))
		return
	end

	local value_type = if val.type == "object" then val.value.class.name else string.gsub(val.type, "^%l", string.upper)
	exception.raise(vm, exception.TypeError, `no implicit conversion of {value_type} to Integer`)
end

-- R[a] = R[a] - R[a+1]
-- Operands: B
local function op_sub(vm: VM)
	local A = fetch_B(vm)

	local val1 = vm:get_register(A)
	local val2 = vm:get_register(A + 1)

	if val1.type == "integer" then
		if val2.type == "integer" then
			vm:set_register(A, value.tointeger(val1.value.number - val2.value.number))
			return
		elseif val2.type == "float" then
			vm:set_register(A, value.tofloat(val1.value.number - val2.value.number))
			return
		end
	elseif val1.type == "float" and (val2.type == "integer" or val2.type == "float") then
		vm:set_register(A, value.tofloat(val1.value.number - val2.value.number))
		return
	end

	vm:send_by_name("-", A, 1)
end

-- R[a] = R[a] - mrb_int(b)
-- Operands: BB
local function op_subi(vm: VM)
	local A, B = fetch_BB(vm)

	local val = vm:get_register(A)

	if val.type == "integer" then
		vm:set_register(A, value.tointeger(val.value.number - B))
		return
	elseif val.type == "float" then
		vm:set_register(A, value.tofloat(val.value.number - B))
		return
	end

	local value_type = if val.type == "object" then val.value.class.name else string.gsub(val.type, "^%l", string.upper)
	exception.raise(vm, exception.TypeError, `no implicit conversion of {value_type} to Integer`)
end

-- R[a] = R[a] * R[a+1]
-- Operands: B
local function op_mul(vm: VM)
	local A = fetch_B(vm)

	local val1 = vm:get_register(A)
	local val2 = vm:get_register(A + 1)

	if val1.type == "integer" then
		if val2.type == "integer" then
			vm:set_register(A, value.tointeger(val1.value.number * val2.value.number))
			return
		elseif val2.type == "float" then
			vm:set_register(A, value.tofloat(val1.value.number * val2.value.number))
			return
		end
	elseif val1.type == "float" and (val2.type == "integer" or val2.type == "float") then
		vm:set_register(A, value.tofloat(val1.value.number * val2.value.number))
		return
	end

	vm:send_by_name("*", A, 1)
end

-- R[a] = R[a] / R[a+1]
-- Operands: B
local function op_div(vm: VM)
	local A = fetch_B(vm)

	local val1 = vm:get_register(A)
	local val2 = vm:get_register(A + 1)

	if (val2.type == "integer" or val2.type == "float") and val2.value.number == 0 then
		exception.raise(vm, exception.ZeroDivisionError, `divided by 0`)
		return
	end

	if val1.type == "integer" then
		if val2.type == "integer" then
			vm:set_register(A, value.tointeger(val1.value.number / val2.value.number))
			return
		elseif val2.type == "float" then
			vm:set_register(A, value.tofloat(val1.value.number / val2.value.number))
			return
		end
	elseif val1.type == "float" and (val2.type == "integer" or val2.type == "float") then
		vm:set_register(A, value.tofloat(val1.value.number / val2.value.number))
		return
	end

	vm:send_by_name("/", A, 1)
end

-- R[a] = R[a] == R[a+1]
-- Operands: B
local function op_eq(vm: VM)
	local A = fetch_B(vm)
	local val1 = vm:get_register(A)

	if val1.type == "object" then
		vm:send_by_name("==", A, 1)
		return
	end

	local res = value.compare(val1, vm:get_register(A + 1))
	vm:set_register(A, value.toboolean(res == 0))
end

-- R[a] = R[a] < R[a+1]
-- Operands: B
local function op_lt(vm: VM)
	local A = fetch_B(vm)
	local val1 = vm:get_register(A)

	if val1.type == "object" then
		vm:send_by_name("<", A, 1)
		return
	end

	local res = value.compare(val1, vm:get_register(A + 1))
	vm:set_register(A, value.toboolean(res < 0))
end

-- R[a] = R[a] <= R[a+1]
-- Operands: B
local function op_le(vm: VM)
	local A = fetch_B(vm)
	local val1 = vm:get_register(A)

	if val1.type == "object" then
		vm:send_by_name("<=", A, 1)
		return
	end

	local res = value.compare(val1, vm:get_register(A + 1))
	vm:set_register(A, value.toboolean(res <= 0))
end

-- R[a] = R[a] > R[a+1]
-- Operands: B
local function op_gt(vm: VM)
	local A = fetch_B(vm)
	local val1 = vm:get_register(A)

	if val1.type == "object" then
		vm:send_by_name(">", A, 1)
		return
	end

	local res = value.compare(val1, vm:get_register(A + 1))
	vm:set_register(A, value.toboolean(res > 0))
end

-- R[a] = R[a] >= R[a+1]
-- Operands: B
local function op_ge(vm: VM)
	local A = fetch_B(vm)
	local val1 = vm:get_register(A)

	if val1.type == "object" then
		vm:send_by_name(">=", A, 1)
		return
	end

	local res = value.compare(val1, vm:get_register(A + 1))
	vm:set_register(A, value.toboolean(res >= 0))
end

-- R[a] = ary_new(R[a],R[a+1]..R[a+b])
-- Operands: BB
local function op_array(vm: VM)
	local A, B = fetch_BB(vm)

	local new_arr_val: ArrayValue = class.instance_new(class.builtins.Array)
	local new_arr = new_arr_val.value

	for i = A, A + B do
		table.insert(new_arr.array, vm:get_register(i))
		vm:set_register(i, nil :: any)
	end

	vm:set_register(A, new_arr_val)
end

-- R[a] = ary_new(R[b],R[b+1]..R[b+c])
-- Operands: BBB
local function op_array2(vm: VM)
	local A, B, C = fetch_BBB(vm)

	local new_arr_val: ArrayValue = class.instance_new(class.builtins.Array)
	local new_arr = new_arr_val.value

	for i = B, B + C do
		table.insert(new_arr.array, vm:get_register(i))
		vm:set_register(i, nil :: any)
	end

	vm:set_register(A, new_arr_val)
end

-- ary_cat(R[a],R[a+1])
-- Operands: B
local function op_arycat(vm: VM)
	local A = fetch_B(vm)

	local val1 = vm:get_register(A)
	assert(val1.type == "array")

	local val2 = vm:get_register(A + 1)
	assert(val2.type == "array")

	table.move(val2.value.array, 1, #val2.value.array, #val1.value.array + 1, val1.value.array)
end

-- ary_push(R[a],R[a+1]..R[a+b])
-- Operands: BB
local function op_arypush(vm: VM)
	local A, B = fetch_BB(vm)

	local val1 = vm:get_register(A)
	assert(val1.type == "array")

	for i = A + 1, B do
		table.insert(val1.value.array, vm:get_register(i))
		vm:set_register(i, nil :: any)
	end
end

-- R[a] = ary_dup(R[a])
-- Operands: B
local function op_arydup(vm: VM)
	local A = fetch_B(vm)

	local val1 = vm:get_register(A)
	assert(val1.type == "array")

	local new_arr_val: ArrayValue = class.instance_new(class.builtins.Array)
	local new_arr = new_arr_val.value
	new_arr.array = table.clone(val1.value.array)

	return vm:set_register(A, new_arr_val)
end

-- R[a] = R[b][c]
-- Operands: BBB
local function op_aref(vm: VM)
	local A, B, C = fetch_BBB(vm)

	local val1 = vm:get_register(B)

	if val1.type == "array" then
		vm:set_register(A, val1.value.array[C + 1])
	else
		if C == 0 then
			vm:set_register(A, vm:get_register(B))
			return
		end

		-- TODO: do we call .[] ?
		vm:set_register(A, value.nil_value)
	end
end

-- R[b][c] = R[a]
-- Operands: BBB
local function op_aset(vm: VM)
	local A, B, C = fetch_BBB(vm)

	local val1 = vm:get_register(B)
	assert(val1.type == "array")

	val1.value.array[C + 1] = vm:get_register(A)
end

-- *R[a],R[a+1]..R[a+c] = R[a][b..]
-- Operands: BBB
local function op_apost(vm: VM)
	-- TODO what does this opcode even do?
	local A, B, C = fetch_BBB(vm)

	local val1 = vm:get_register(A)
	if val1.type ~= "array" then
		-- val1 = {
		--     type = "array",
		--     value = {
		--         class = class.builtins.Array,
		--         ivar = {},
		--         array = table.clone(val1.value.array)
		--     } :: Array
		-- }
	end

	local pre = B
	local post = C

	assert(val1.type == "array") -- for the typechecker
	if #val1.value.array > pre + post then
		local ary_size = #val1.value.array - pre - post
		table.move(val1.value.array, pre + 1, pre + ary_size, 1, (vm:get_register(A).value :: Array).array)
	else
		vm:set_register(A, {
			type = "array",
			value = {
				class = class.builtins.Array,
				methods = class.builtins.Array.definitions,
				ivar = {},
				array = table.clone(val1.value.array),
			} :: Array,
		})
	end
end

-- R[a] = intern(R[a])
-- Operands: B
local function op_intern(vm: VM)
	local A = fetch_B(vm)

	local val = vm:get_register(A)
	assert(val.type == "string")

	local sym = val.value.str
	vm:set_register(A, value.tosymbol(sym))
end

-- R[a] = intern(Pool[b])
-- Operands: BB
local function op_symbol(vm: VM)
	local A, B = fetch_BB(vm)

	local sym = vm.current_callinfo.irep.pool[B + 1]
	assert(type(sym) == "string")

	vm:set_register(A, value.tosymbol(sym))
end

-- R[a] = str_dup(Pool[b])
-- Operands: BB
local function op_string(vm: VM)
	local A, B = fetch_BB(vm)

	local str = vm.current_callinfo.irep.pool[B + 1]
	assert(type(str) == "string")

	vm:set_register(A, value.tostr(str))
end

-- str_cat(R[a], R[a+1])
-- Operands: B
local function op_strcat(vm: VM)
	local A = fetch_B(vm)

	local val1 = vm:get_register(A)
	assert(val1.type == "string")

	local val2 = vm:get_register(A + 1)
	-- TODO Support to_s/to_str (idk which one it is)
	assert(val2.type == "string", `call to to_s for OP_STRCAT isn't implemented for {val2.type}`)

	-- TODO support calling to_s
	val1.value.str ..= val2.value.str
end

-- R[a] = hash_new(R[a],R[a+1]..R[a+b*2-1])
-- Operands: BB
local function op_hash(vm: VM)
	local A, B = fetch_BB(vm)

	local new_hash_val: HashValue = class.instance_new(class.builtins.Hash)
	local new_hash = new_hash_val.value

	for i = A, A + 2 * B - 1, 2 do
		local key = vm:get_register(i)
		local value = vm:get_register(i + 1)

		-- TODO
		new_hash.hash[key] = value
	end

	vm:set_register(A, new_hash_val)
end

-- hash_push(R[a],R[a+1]..R[a+b*2])
-- Operands: BB
local function op_hashadd(vm: VM)
	local A, B = fetch_BB(vm)
	local hash = vm:get_register(A)
	assert(hash.type == "hash")

	for i = A + 1, A + B * 2, 2 do
		local key = vm:get_register(i)
		local value = vm:get_register(i + 1)

		hash.value.hash[key] = value
	end
end

-- R[a] = hash_cat(R[a],R[a+1])
-- Operands: B
local function op_hashcat(vm: VM)
	local A = fetch_B(vm)

	local hash1 = vm:get_register(A)
	assert(hash1.type == "hash")

	local hash2 = vm:get_register(A + 1)
	assert(hash2.type == "hash")

	local new_hash_val: HashValue = class.instance_new(class.builtins.Hash)
	local new_hash = new_hash_val.value

	new_hash.hash = table.clone(hash1.value.hash)

	for k, v in pairs(hash2.value.hash) do
		new_hash.hash[k] = v
	end

	vm:set_register(A, new_hash_val)
end

-- R[a] = lambda(Irep[b],L_LAMBDA)
-- Operands: BB
local function op_lambda(vm: VM)
	local A, B = fetch_BB(vm)

	local new_proc = proc_new(vm, vm.current_callinfo.irep.children[B + 1], "lambda")

	vm:set_register(A, {
		type = "proc",
		value = new_proc,
	})
end

-- R[a] = lambda(Irep[b],L_BLOCK)
-- Operands: BB
local function op_block(vm: VM)
	local A, B = fetch_BB(vm)

	local new_proc = proc_new(vm, vm.current_callinfo.irep.children[B + 1], "block")

	vm:set_register(A, {
		type = "proc",
		value = new_proc,
	})
end

-- R[a] = lambda(Irep[b],L_METHOD)
-- Operands: BB
local function op_method(vm: VM)
	local A, B = fetch_BB(vm)

	-- Currently methods are like lambda
	-- TODO Make them into the Method class
	local new_proc = proc_new(vm, vm.current_callinfo.irep.children[B + 1], "method")

	vm:set_register(A, {
		type = "proc",
		value = new_proc,
	})
end

-- R(a) = range_new(R(a),R(a+1),FALSE)
-- Operands: B
local function op_range_inc(vm: VM)
	local _A = fetch_B(vm)
	error("not implemented")
end

-- R(a) = range_new(R(a),R(a+1),TRUE)
-- Operands: B
local function op_range_exc(vm: VM)
	local _A = fetch_B(vm)
	error("not implemented")
end

-- R(a) = ::Object
-- Operands: B
local function op_oclass(vm: VM)
	local A = fetch_B(vm)

	vm:set_register(A, {
		type = "class",
		value = class.builtins.Object,
	})
end

-- R(a) = newclass(R(a),Syms(b),R(a+1))
-- Operands: BB
local function op_class(vm: VM)
	local A, B = fetch_BB(vm)

	local class_name = vm.current_callinfo.irep.symbols[B + 1]
	local outer = vm:get_register(A)
	local val = vm:get_register(A + 1)
	local super = if val.type == "class" then val.value else class.builtins.Object

	if super.is_singleton then
		exception.raise(vm, exception.TypeError, `can't make subclass of singleton class`)
		return
	end

	local new_class: Class
	if outer.type == "class" then
		new_class = class.define_class_under(vm, outer.value, class_name, super)
	else
		new_class = class.define_class(vm, class_name, super)
	end

	vm:set_register(A, {
		type = "class",
		value = new_class,
	})
end

-- R(a) = newmodule(R(a),Syms(b))
-- Operands: BB
local function op_module(vm: VM)
	local A, B = fetch_BB(vm)

	local module_name = vm.current_callinfo.irep.symbols[B + 1]
	local outer = vm:get_register(A)

	local new_module: Class
	if outer.type == "class" then
		new_module = class.define_class_under(vm, outer.value, module_name, class.builtins.Module)
	else
		new_module = class.define_class(vm, module_name, class.builtins.Module)
	end

	new_module.is_module = true

	vm:set_register(A, {
		type = "class",
		value = new_module,
	})
end

-- R(a) = blockexec(R(a),Irep(b))
-- Operands: BB
local function op_exec(vm: VM)
	local A, B = fetch_BB(vm)

	local val = vm:get_register(A)
	assert(val.type == "class")

	local child_irep = vm.current_callinfo.irep.children[B + 1]
	vm:enter_callinfo(nil, child_irep, val.value, A, 0)
end

-- R(a).newmethod(Syms(b),R(a+1)); R(a) = Syms(b)
-- Operands: BB
local function op_def(vm: VM)
	local A, B = fetch_BB(vm)

	local val1 = vm:get_register(A)
	assert(val1.type == "class")

	local val2 = vm:get_register(A + 1)
	assert(val2.type == "proc")

	local sym = vm.current_callinfo.irep.symbols[B + 1]

	val1.value.definitions[sym] = {
		sym = sym,
		type = "irep",
		value = val2.value.irep,
	}

	vm:set_register(A, value.tosymbol(sym))
	vm:set_register(A + 1, nil :: any)
end

-- alias_method(target_class,Syms(a),Syms(b))
-- Operands: BB
local function op_alias(vm: VM)
	local A, B = fetch_BB(vm)

	local method_sym = vm.current_callinfo.irep.symbols[A + 1]
	local alias_id = vm.current_callinfo.irep.symbols[B + 1]

	local cls = vm.current_callinfo.target_class
	if class.get_method(cls, method_sym) == nil then
		exception.raise(vm, exception.NameError, `undefined method '{method_sym}' for class '{cls.name}'`)
		return
	end

	cls.definitions[alias_id] = cls.definitions[method_sym]
end

-- undef_method(target_class,Syms(a))
-- Operands: B
local function op_undef(vm: VM)
	local A = fetch_B(vm)

	local method_sym = vm.current_callinfo.irep.symbols[A + 1]

	local cls = vm.current_callinfo.target_class
	if class.get_method(cls, method_sym) == nil then
		exception.raise(vm, exception.NameError, `undefined method '{method_sym}' for class '{cls.name}'`)
		return
	end

	class.undefine_method(cls, method_sym)
end

-- R(a) = R(a).singleton_class
-- Operands: B
local function op_sclass(vm: VM)
	local A = fetch_B(vm)
	local obj = vm:get_register(A)

	local sclass = class.get_singleton_class(obj.value)
	vm:set_register(A, {
		type = "class",
		value = sclass,
	})
end

-- R[a] = target_class
-- Operands: B
local function op_tclass(vm: VM)
	local A = fetch_B(vm)
	vm:set_register(A, {
		type = "class",
		value = vm.current_callinfo.target_class,
	})
end

-- print a,b,c
-- Operands: BBB
local function op_debug(vm: VM)
	local A, B, C = fetch_BBB(vm)
	print(A, B, C)
end

-- raise(LocalJumpError, Pool(a))
-- Operands: B
local function op_err(vm: VM)
	local A = fetch_B(vm)

	local message = vm.current_callinfo.irep.pool[A + 1]
	exception.raise(vm, exception.LocalJumpError, tostring(message))
end

local function op_ext1(vm: VM)
	fetch_Z(vm)
end

local function op_ext2(vm: VM)
	fetch_Z(vm)
end

local function op_ext3(vm: VM)
	fetch_Z(vm)
end

local function op_stop(vm: VM)
	fetch_Z(vm)
	vm.should_stop = true
end

local op_functions = {
	[0] = op_nop,
	op_move,
	op_loadl,
	op_loadi,
	op_loadineg,
	op_loadi__1,
	op_loadi_0,
	op_loadi_1,
	op_loadi_2,
	op_loadi_3,
	op_loadi_4,
	op_loadi_5,
	op_loadi_6,
	op_loadi_7,
	op_loadi16,
	op_loadi32,
	op_loadsym,
	op_loadnil,
	op_loadself,
	op_loadt,
	op_loadf,
	op_getgv,
	op_setgv,
	op_getsv,
	op_setsv,
	op_getiv,
	op_setiv,
	op_getcv,
	op_setcv,
	op_getconst,
	op_setconst,
	op_getmcnst,
	op_setmcnst,
	op_getupvar,
	op_setupvar,
	op_getidx,
	op_setidx,
	op_jmp,
	op_jmpif,
	op_jmpnot,
	op_jmpnil,
	op_jmpuw,
	op_except,
	op_rescue,
	op_raiseif,
	op_ssend,
	op_ssendb,
	op_send,
	op_sendb,
	op_call,
	op_super,
	op_argary,
	op_enter,
	op_key_p,
	op_keyend,
	op_karg,
	op_return,
	op_return_blk,
	op_break,
	op_blkpush,
	op_add,
	op_addi,
	op_sub,
	op_subi,
	op_mul,
	op_div,
	op_eq,
	op_lt,
	op_le,
	op_gt,
	op_ge,
	op_array,
	op_array2,
	op_arycat,
	op_arypush,
	op_arydup,
	op_aref,
	op_aset,
	op_apost,
	op_intern,
	op_symbol,
	op_string,
	op_strcat,
	op_hash,
	op_hashadd,
	op_hashcat,
	op_lambda,
	op_block,
	op_method,
	op_range_inc,
	op_range_exc,
	op_oclass,
	op_class,
	op_module,
	op_exec,
	op_def,
	op_alias,
	op_undef,
	op_sclass,
	op_tclass,
	op_debug,
	op_err,
	op_ext1,
	op_ext2,
	op_ext3,
	op_stop,
}

function VM.run(vm: VM)
	while true do
		local inst, _ = string.unpack(">B", vm.inst, vm.pc)

		local opcode = opcodes.opcodes[inst]
		assert(opcode ~= nil, `unknown opcode {inst}`)

		if vm.debug_mode then
			print(`executing opcode: {opcode}`) -- debug
		end

		op_functions[inst](vm)

		if vm.debug_mode then
			print(`registers (after executing): (-> {vm.current_callinfo.self_reg_idx})`)
			for i, v in vm.registers do
				print(`  R[{i}]: {debuglib.obj_rep(v :: any)}`)
			end
			print("")
		end

		if vm.should_stop then
			return
		end

		if vm.ext ~= 0 then
			vm.ext = 0
		end

		if not vm.exception then
			continue
		end

		-- Handle exceptions and catch handlers
		while true do
			-- We should first search for a rescue, if not then an ensure
			local handler = vm:get_catch_handler("rescue") or vm:get_catch_handler("ensure")
			if handler then
				vm.pc = vm.current_callinfo.irep.inst_idx + handler.target
				break
			end

			-- We reached the end and couldn't find a catch handler
			if #vm.callinfo_stack == 0 then
				exception.print(vm.exception)
				error(`An exception occurred while executing; refer to the message above for more information`)
			end

			vm:exit_callinfo()
		end
	end
end

return VM
