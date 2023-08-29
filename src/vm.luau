--!strict
local types = require("types")
local opcodes = require("opcodes")
local value = require("value")
local symbol = require("symbol")
local global = require("global")
local class = require("class")
local keyvalue = require("keyvalue")
local err = require("error")

local _basicobject_class = require("builtins/basicobject")
local object_class = require("builtins/object")
local array_class = require("builtins/array")
local error_class = require("builtins/errors")
local string_class = require("builtins/string")
local proc_class = require("builtins/proc")
local hash_class = require("builtins/hash")
local _class_class = require("builtins/class")
local _symbol_class = require("builtins/symbol")
local _integer_class = require("builtins/integer")
local _float_class = require("builtins/float")
local _nilclass_class = require("builtins/nilclass")
local _trueclass_class = require("builtins/trueclass")
local _falseclass_class = require("builtins/falseclass")
local module_class = require("builtins/module")

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

local function free_idx(tbl: { any }): number
    for i = 1, #tbl do
        if tbl[i] == nil then
            return i
        end
    end

    return #tbl + 1
end

local function signed_int16(num: number): number
    if num >= 2^15 then
        return num - 2^16
    end

    return num
end

local function proc_new(vm: VM, irep: IREP, proc_type: "block" | "lambda" | "method"): Proc
    local val = class.instance_new(proc_class)
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

local vm_map = {}

-- VM Class
local VM = {}
VM.__index = VM

function VM.new(debug_mode: boolean?): VM
    debug_mode = if debug_mode == nil then false else debug_mode

    local self = {
        id = -1,
        debug_mode = debug_mode or false,
        permanence = false,
        should_stop = false,
        ensure_state = {
            ensuring = false
        },
        exception = value.autocast(nil),
        callinfo_stack = {},
        registers = {}
    }

    return setmetatable(self, VM) :: any
end

function VM.open(vm: VM)
    local id = free_idx(vm_map)
    vm_map[id] = vm

    vm.id = id
end

function VM.load(vm: VM, stream: ByteStream, irep: IREP)
    assert(stream ~= nil)
    assert(irep ~= nil)

    vm.registers[1] = class.instance_new(object_class)
    vm.top_irep = irep
    vm.inst = stream
    
    vm.current_callinfo = {
        irep = irep,
        inst_cursor_pos = irep.inst_idx,
        self_reg_idx = 1,
        target_class = object_class,
        self_class = nil,
        arg_count = 0,
        super_called = false,
        method_id = nil,
        deleted_kargs = {},
        dead = false
    }
    
    stream.cursor = irep.inst_idx
end

function VM.close(vm: VM)
    vm_map[vm.id] = nil
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
    
    local inst_rel = vm.inst.cursor - vm.current_callinfo.irep.inst_idx
    for _, handler in vm.current_callinfo.irep.catch_handlers do
        if handler.type == handler_type 
        and handler.beginning < inst_rel
        and inst_rel <= handler.ending 
        then
            return handler
        end
    end

    return nil
end

local CALL_MAXARGS = 15
function VM.send_by_name(vm: VM, sym_id: number, A: number, C: number, call_super: boolean)
    assert(sym_id ~= nil)
    assert(A ~= nil)
    assert(C ~= nil)

    call_super = if call_super == nil then false else call_super
    -- OP_SEND:
    --     R[a] = R[a].send(Syms[b], R[a+1].., R[a+n+1]:R[a+n+2]..) (c = n|k<<4)

    local current_self_idx = vm.current_callinfo.self_reg_idx
    local num_args = bit32.band(C, 0x0f)
    local num_kwargs = bit32.band(bit32.rshift(C, 4), 0x0f)
    local block_given = bit32.rshift(C, 8) ~= 0

    local args = {}

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
            local hash_val = class.instance_new(hash_class)
            local kw_hash = hash_val.value :: Hash

            for i = 0, num_kwargs * 2 - 1, 2 do
                local key = vm.registers[kw_start + i]
                local val = vm.registers[kw_start + i + 1]
                
                vm.registers[kw_start + i] = nil
                vm.registers[kw_start + i + 1] = nil

                kw_hash.hash[value.autocast(key.value.sym_id, "symbol")] = val
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

    local method = if call_super then class.get_super_method(obj, sym_id) else class.get_method(obj, sym_id)
    if not method then
        if call_super then
            err.raise(vm, error_class.NoMethodError, `no superclass method for {symbol.symid_to_str(sym_id)}`)
        else
            err.raise(vm, error_class.NoMethodError, `undefined local variable or method '{symbol.symid_to_str(sym_id)}' for {cls.name}`)
        end
        
        if #vm.callinfo_stack > 0 then
            (vm.exception.value :: Exception).method_id = vm.callinfo_stack[#vm.callinfo_stack].method_id
        end
        
        return
    end

    if method.type == "luafunc" then
        --local old_idx = vm.current_self_idx
        local curr_idx = current_self_idx + A
        local statefunc = {
            get_register = function(register: number): Value
                assert(register >= 0)
                return vm.registers[curr_idx + register]
            end,

            set_register = function(register: number, val: Value)
                assert(register >= 0)
                assert(val ~= nil)
                vm.registers[curr_idx + register] = val
            end,

            send_by_name = function(sym_id: number, A: number, C: number, super: boolean?)
                vm:send_by_name(sym_id, curr_idx + A, C)
            end,

            vm = vm,
            current_self_idx = curr_idx
        }

        method.value(statefunc, #args)

        if vm.exception and vm.exception.type == "exception" and vm.exception.value.method_id == nil then
            vm.exception.value.method_id = sym_id    
        end

        -- Clear registers
        for i = A + 1, A + #args + 1 do
            vm:set_register(i, nil :: any)
        end

        return
    end

    local callinfo = vm:enter_callinfo(
        method.sym_id, 
        method.value, 
        vm.current_callinfo.target_class, 
        A, 
        if not block_given then #args else #args - 1
    )
    callinfo.self_class = cls
    callinfo.super_called = call_super
end

function VM.enter_callinfo(vm: VM, method_id: number?, irep: IREP, target_class: Class, self_idx: number, arg_count: number): CallInfo
    local callinfo: CallInfo = {
        irep = irep,
        inst_cursor_pos = irep.inst_idx,
        self_reg_idx = vm.current_callinfo.self_reg_idx + self_idx,
        target_class = target_class,
        self_class = nil,
        arg_count = arg_count,
        super_called = false,
        method_id = method_id,
        deleted_kargs = {},
        dead = false
    }
    
    -- Push current_callinfo to callinfo_stack
    vm.current_callinfo.inst_cursor_pos = vm.inst.cursor
    table.insert(vm.callinfo_stack, vm.current_callinfo)

    vm.current_callinfo = callinfo
    vm.inst.cursor = callinfo.inst_cursor_pos

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
    vm.inst.cursor = prev_callinfo.inst_cursor_pos
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

local execute = {}

function execute.op_nop(vm: VM, ext: number)
    -- blehhh :P
end

-- R[a] = R[b]
-- Operands: BB
function execute.op_move(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    vm:set_register(A, vm:get_register(B))
end

-- R[a] = Pool[b]
-- Operands: BB
function execute.op_loadl(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local pool_val = vm.current_callinfo.irep.pool[B + 1]
    local val: Value= if type(pool_val) == "number" then
        if math.floor(pool_val) == pool_val then
            value.autocast(vm.current_callinfo.irep.pool[B + 1], "integer")
        else
            value.autocast(vm.current_callinfo.irep.pool[B + 1], "float")
    else
        value.autocast(vm.current_callinfo.irep.pool[B + 1])

    vm:set_register(A, val)
end

-- R[a] = mrb_int(b)
-- Operands: BB
function execute.op_loadi(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    vm:set_register(A, value.autocast(B, "integer"))
end

-- R[a] = mrb_int(-b)
-- Operands: BB
function execute.op_loadineg(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    vm:set_register(A, value.autocast(-B, "integer"))
end

-- R[a] = mrb_int(-1)
-- Operands: B
function execute.op_loadi__1(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    vm:set_register(A, value.autocast(-1, "integer"))
end

-- R[a] = mrb_int(n)
-- Operands: B
function execute.op_loadi_0(vm: VM, ext: number, n: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    vm:set_register(A, value.autocast(0, "integer"))
end

-- R[a] = mrb_int(n)
-- Operands: B
function execute.op_loadi_1(vm: VM, ext: number, n: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    vm:set_register(A, value.autocast(1, "integer"))
end

-- R[a] = mrb_int(n)
-- Operands: B
function execute.op_loadi_2(vm: VM, ext: number, n: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    vm:set_register(A, value.autocast(2, "integer"))
end

-- R[a] = mrb_int(n)
-- Operands: B
function execute.op_loadi_3(vm: VM, ext: number, n: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    vm:set_register(A, value.autocast(3, "integer"))
end

-- R[a] = mrb_int(n)
-- Operands: B
function execute.op_loadi_4(vm: VM, ext: number, n: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    vm:set_register(A, value.autocast(4, "integer"))
end

-- R[a] = mrb_int(n)
-- Operands: B
function execute.op_loadi_5(vm: VM, ext: number, n: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    vm:set_register(A, value.autocast(5, "integer"))
end

-- R[a] = mrb_int(n)
-- Operands: B
function execute.op_loadi_6(vm: VM, ext: number, n: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    vm:set_register(A, value.autocast(6, "integer"))
end

-- R[a] = mrb_int(n)
-- Operands: B
function execute.op_loadi_7(vm: VM, ext: number, n: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    vm:set_register(A, value.autocast(7, "integer"))
end

-- R[a] = mrb_int16(b)
-- Operands: BS
function execute.op_loadi16(vm: VM, ext: number)
    local A, B = opcodes.fetch_BS(vm.inst, ext)

    vm:set_register(A, value.autocast(B, "integer"))
end

-- R[a] = mrb_int32( (b << 16) + c )
-- Operands: BSS
function execute.op_loadi32(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BSS(vm.inst, ext)

    local num = bit32.lshift(B, 16) + C
    vm:set_register(A, value.autocast(num, "integer"))
end

-- R[a] = Syms[b]
-- Operands: BB
function execute.op_loadsym(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    vm:set_register(A, value.autocast(sym_id, "symbol"))
end

-- R[a] = nil
-- Operands: B
function execute.op_loadnil(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    vm:set_register(A, value.autocast(nil))
end

-- R[a] = self
-- Operands: B
function execute.op_loadself(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    vm:set_register(A, vm:get_self())
end

-- R[a] = true
-- Operands: B
function execute.op_loadt(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    vm:set_register(A, value.autocast(true))
end

-- R[a] = false
-- Operands: B
function execute.op_loadf(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    vm:set_register(A, value.autocast(false))
end

-- R[a] = getglobal(Syms[b])
-- Operands: BB
function execute.op_getgv(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    local val = global.globals.get(sym_id)
    if val ~= nil then
        vm:set_register(A, val)
    else
        vm:set_register(A, value.autocast(nil))
    end
end

-- setglobal(Syms[b], R[a])
-- Operands: BB
function execute.op_setgv(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    global.globals.set(sym_id, vm:get_register(A))
end

-- R[a] = Special[Syms[b]]
-- Operands: BB
function execute.op_getsv(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)
    error("not implemented")
end

-- Special[Syms[b]] = R[a]
-- Operands: BB
function execute.op_setsv(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)
    error("not implemented")
end

-- R[a] = ivget(Syms[b])
-- Operands: BB
function execute.op_getiv(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    local self = vm:get_self()

    vm:set_register(A, self.value.ivar[sym_id])
end

-- ivset(Syms[b], R[a])
-- Operands: BB
function execute.op_setiv(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    local self = vm:get_self()

    self.value.ivar[sym_id] = vm:get_register(A)
end

-- R[a] = cvget(Syms[b])
-- Operands: BB
function execute.op_getcv(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    local self = vm:get_self()

    vm:set_register(A, self.value.class.cvar[sym_id])

end

-- cvset(Syms[b], R[a])
-- Operands: BB
function execute.op_setcv(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    local self = vm:get_self()

    self.value.class.cvar[sym_id] = vm:get_register(A)
end

-- R[a] = constget(Syms[b])
-- Operands: BB
function execute.op_getconst(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    
    local cls: Class = if vm.current_callinfo.self_class ~= nil then
        vm.current_callinfo.self_class
    else
        vm.current_callinfo.target_class
    
    local val = global.consts.get_class_const(cls, sym_id) or global.consts.get(sym_id)
    if val == nil then
        err.raise(vm, error_class.NameError, `uninitialized constant {symbol.symid_to_str(sym_id)}`)
        return
    end

    vm:set_register(A, val)
end

-- constset(Syms[b], R[a])
-- Operands: BB
function execute.op_setconst(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local value = vm:get_register(A)
    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    local self = vm:get_register(0)

    if self.type == "class" then
        global.consts.set_class_const(self.value, sym_id, value)
    else
        global.consts.set(sym_id, vm:get_register(A))
    end
end

-- R[a] = R[a]::Syms[b]
-- Operands: BB
function execute.op_getmcnst(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local val = vm:get_register(A)
    if val.type ~= "class" then
        -- TODO use val.to_s
        err.raise(vm, error_class.TypeError, `object is not a class/module`)
        return
    end

    local sym_id = vm.current_callinfo.irep.syms[B + 1]

    local obj = global.consts.get_class_const(val.value, sym_id)
    if obj == nil then
        err.raise(vm, error_class.NameError, `uninitialized constant {symbol.symid_to_str(val.value.sym_id)}::{symbol.symid_to_str(sym_id)}`)
        return
    end

    vm:set_register(A, obj)
end

-- R[a+1]::Syms[b] = R[a]
-- Operands: BB
function execute.op_setmcnst(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local val1 = vm:get_register(A)
    
    local val2 = vm:get_register(A + 1)
    if val2.type ~= "class" then
        -- TODO use val1.to_s
        err.raise(vm, error_class.TypeError, `object is not a class/module`)
        return
    end

    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    global.consts.set_class_const(val2.value, sym_id, val1)
end

-- R[a] = uvget(b,c)
-- Operands: BBB
function execute.op_getupvar(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)
    
    local proc = vm:get_register(0)
    assert(proc.type == "proc")

    local callinfo = vm.callinfo_stack[#vm.callinfo_stack - C]
    assert(callinfo ~= nil)

    local val = vm.registers[callinfo.self_reg_idx + B]
    vm:set_register(A, val)
end

-- uvset(b,c,R[a])
-- Operands: BBB
function execute.op_setupvar(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)
    
    local proc = vm:get_register(0)
    assert(proc.type == "proc")

    local callinfo = vm.callinfo_stack[#vm.callinfo_stack - C]
    assert(callinfo ~= nil)

    vm.registers[callinfo.self_reg_idx + B] = vm:get_register(A)
end

-- R[a] = R[a][R[a+1]]
-- Operands: B
function execute.op_getidx(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    vm:send_by_name(symbol.str_to_symid("[]"), A, 1)
end

-- R[a][R[a+1]] = R[a+2]
-- Operands: B
function execute.op_setidx(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    vm:send_by_name(symbol.str_to_symid("[]="), A, 2)
end

-- pc += a
-- Operands: S
function execute.op_jmp(vm: VM, ext: number)
    local A = opcodes.fetch_S(vm.inst, ext)
    vm.inst:skip(signed_int16(A))
end

-- if R[a] pc+=b
-- Operands: BS
function execute.op_jmpif(vm: VM, ext: number)
    local A, B = opcodes.fetch_BS(vm.inst, ext)

    local val = vm:get_register(A)
    if val.type ~= "false" then
        vm.inst:skip(signed_int16(B))
    end
end

-- if !R[a] pc+=b
-- Operands: BS
function execute.op_jmpnot(vm: VM, ext: number)
    local A, B = opcodes.fetch_BS(vm.inst, ext)

    local val = vm:get_register(A)
    if val.type == "false" or val.type == "nil" then
        vm.inst:skip(signed_int16(B))
    end
end

-- if R[a] == nil pc+=b
-- Operands: BS
function execute.op_jmpnil(vm: VM, ext: number)
    local A, B = opcodes.fetch_BS(vm.inst, ext)

    local val = vm:get_register(A)
    if val.type == "nil" then
        vm.inst:skip(signed_int16(B))
    end
end

-- unwind_and_jump_to(a)
-- Operands: S
function execute.op_jmpuw(vm: VM, ext: number)
    local A = opcodes.fetch_S(vm.inst, ext)

    local jump_inst_idx = vm.inst.cursor + signed_int16(A)

    local handler = vm:get_catch_handler("ensure")
    if not handler then
        vm.inst.cursor = jump_inst_idx
        return
    end

    vm.inst.cursor = vm.current_callinfo.irep.inst_idx + handler.target
end

-- R[a] = exc
-- Operands: B
function execute.op_except(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    
    vm:set_register(A, vm.exception)
    vm.exception = value.autocast(nil)
end

-- R[b] = R[a].is_a?(R[b])
-- Operands: BB
function execute.op_rescue(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local val1 = vm:get_register(A)
    local val2 = vm:get_register(B)

    assert(val1.type == "exception")
    assert(val2.type == "class")

    local ret = class.obj_kind_of(val1.value, val2.value)
    vm:set_register(B, value.autocast(ret))
end

-- raise(R[a]) if R[a]
-- Operands: B
function execute.op_raiseif(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    
    local val = vm:get_register(A)
    if val.type == "nil" then
        return
    end

    assert(val.type == "exception")
    vm.exception = val
end

-- R[a] = self.send(Syms[b],R[a+1]..,R[a+n+1]:R[a+n+2]..) (c=n|k<<4)
-- Operands: BBB
function execute.op_ssend(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)

    vm:set_register(A, vm:get_self())
    local sym_id = vm.current_callinfo.irep.syms[B + 1]

    vm:send_by_name(sym_id, A, C)
end

-- R[a] = self.send(Syms[b],R[a+1]..,R[a+n+1]:R[a+n+2]..,&R[a+n+2k+1])
-- Operands: BBB
function execute.op_ssendb(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)

    vm:set_register(A, vm:get_self())
    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    
    vm:send_by_name(sym_id, A, bit32.bor(C, 0x100))
end

-- R[a] = R[a].send(Syms[b],R[a+1]..,R[a+n+1]:R[a+n+2]..) (c=n|k<<4)
-- Operands: BBB
function execute.op_send(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)

    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    vm:send_by_name(sym_id, A, C)
end

-- R[a] = R[a].send(Syms[b],R[a+1]..,R[a+n+1]:R[a+n+2]..,&R[a+n+2k+1])
-- Operands: BBB
function execute.op_sendb(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)

    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    vm:send_by_name(sym_id, A, bit32.bor(C, 0x100))
end

-- R[0] = self.call(frame.argc, frame.argv)
-- Operands: Z
function execute.op_call(vm: VM, ext: number)
    error("not implemented")
end

-- R[a] = super(R[a+1],... ,R[a+b+1])
-- Operands: BB
function execute.op_super(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)
    
    local callinfo = vm.current_callinfo
    if callinfo == nil or callinfo.target_class == nil or callinfo.method_id == nil then
        err.raise(vm, error_class.NoMethodError, "super called outside of method")
        return
    end

    local self = vm:get_register(0)
    vm:set_register(A, self)
    vm:send_by_name(callinfo.method_id, A, bit32.bor(B, 0x100), true)
end

-- R[a] = argument array (16=m5:r1:m5:d1:lv4)
-- Operands: BS
function execute.op_argary(vm: VM, ext: number)
    local A, B = opcodes.fetch_BS(vm.inst, ext)
    local m1_count = bit32.rshift(B, 11)
    local should_rest = bit32.band(bit32.rshift(B, 10), 0x01) ~= 0
    local m2_count = bit32.band(bit32.rshift(B, 5), 0x1f)
    local dict = bit32.band(bit32.rshift(B, 4), 0x01) ~= 0
    local lv = bit32.band(B, 4)

    if vm.current_callinfo.method_id == nil then
        err.raise(vm, error_class.NoMethodError, `super called outside of method`)
        return
    end

    local reg_idx = if lv == 0 then
        vm.current_callinfo.self_reg_idx + 1
    else
        vm.callinfo_stack[#vm.callinfo_stack - lv - 1].self_reg_idx + 1

    -- Move all values of m1, *args and m2 arguments into a single array
    local ary_val = class.instance_new(array_class)
    local new_ary = ary_val.value :: Array
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
        local dup_hash = class.instance_new(hash_class)
        for k, v in pairs(hash.value.hash) do
            (dup_hash.value :: Hash).hash[k] = v
        end

        for k, v in pairs(vm.current_callinfo.deleted_kargs) do
            (dup_hash.value :: Hash).hash[k] = v
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
function execute.op_enter(vm: VM, ext: number)
    local A = opcodes.fetch_W(vm.inst, ext)
    local m1_count = bit32.rshift(A, 18)
    local optional_count = bit32.extract(bit32.rshift(A, 13), 0x1f)
    local should_rest = bit32.btest(A, 0x1000)
    local m2_count = bit32.band(bit32.rshift(A, 7), 0x1f)
    local kwargs_count = bit32.band(bit32.rshift(A, 2), 0x1f)
    local should_dict = bit32.btest(A, 0x02)
    local check_block = bit32.btest(A, 0x01)

    assert(#vm.callinfo_stack > 0)
    
    local args_given = vm.current_callinfo.arg_count
    local reg_idx = m1_count + optional_count + 1

    if args_given < m1_count then
        -- TODO make it better
        err.raise(vm, error_class.ArgumentError, `wrong number of arguments (given {args_given}, expected {m1_count}+)`)
        return
    end

    -- Save proc or nil
    local proc = vm:get_register(args_given + 1)
    if proc == nil then
        proc = value.autocast(nil)    
    end

    if should_rest then
        -- Collect remaining values and put them in an array,
        -- until we reach a Hash, Proc or NilClass
        local new_arr_val = class.instance_new(array_class)
        local new_arr = new_arr_val.value :: Array

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
        vm:set_register(reg_idx, value.autocast(nil))
    end
    reg_idx += 1
    
    -- Clear remaining unused values
    for i = reg_idx, reg_idx + args_given + 1 do
        vm:set_register(reg_idx, nil :: any)
    end

    -- Set new number of arguments (don't include proc)
    vm.current_callinfo.arg_count = reg_idx - 2

    -- Jump depending on the amount of optional arguments
    local jump_offset = args_given - m1_count
    if jump_offset > 0 then
        if jump_offset > optional_count then
            jump_offset = optional_count
            
            -- TODO understand this
            if not should_rest and (vm:get_register(0).type ~= "proc" or vm:get_register(0).value.type ~= "block") then
                err.raise(vm, error_class.ArgumentError, `wrong number of arguments`)
                return
            end
        end

        vm.inst:skip(jump_offset * 3)
    end
end

-- R[a] = kdict.key?(Syms[b])
-- Operands: BB
function execute.op_key_p(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)
    
    assert(#vm.callinfo_stack > 0)

    local kdict = vm:get_register(vm.current_callinfo.arg_count)
    assert(kdict.type == "hash")

    local sym_id = vm.current_callinfo.irep.syms[B + 1]

    for _, v in kdict.value.hash do
        if v.type == "symbol" and v.value.sym_id == sym_id then
            vm:set_register(A, value.autocast(true))
            return
        end
    end

    vm:set_register(A, value.autocast(false))
end

-- raise unless kdict.empty?
-- Operands: Z
function execute.op_keyend(vm: VM, ext: number)
    assert(#vm.callinfo_stack > 0)

    local kdict = vm:get_register(vm.current_callinfo.arg_count)
    assert(kdict.type == "hash")

    if #kdict.value.hash > 0 then
        -- TODO I'll probably have to change how hash is implemented lol
        err.raise(vm, error_class.ArgumentError, `unknown keyword: ???`)
    end
end

-- R[a] = kdict[Syms[b]]; kdict.delete(Syms[b])
-- Operands: BB
function execute.op_karg(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    assert(#vm.callinfo_stack > 0)

    local kdict = vm:get_register(vm.current_callinfo.arg_count)
    assert(kdict.type == "hash")
    
    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    local sym = value.autocast(sym_id, "symbol")
    local ret = kdict.value.hash[sym]

    if ret == nil then
        err.raise(vm, error_class.ArgumentError, `missing keyword: {symbol.symid_to_str(sym_id)}`)
        return
    end

    kdict.value.hash[sym_id] = nil
    vm.current_callinfo.deleted_kargs[sym] = ret

    vm:set_register(A, ret)
end

-- return R[a] (normal)
-- Operands: B
function execute.op_return(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    -- Jump to ensure if exists
    do
        local handler = vm:get_catch_handler("ensure")
        if handler then
            vm.inst.cursor = vm.current_callinfo.irep.inst_idx + handler.target
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
        if vm.inst.cursor == callinfo.irep.num_instructions then
            -- Implicit return
            while vm.ensure_state.target_callinfo ~= vm.current_callinfo do
                vm:exit_callinfo()
                
                local handler = vm:get_catch_handler("ensure")
                if handler then
                    vm.inst.cursor = vm.current_callinfo.irep.inst_idx + handler.target
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
    if callinfo.method_id ~= symbol.str_to_symid("initialize") then
        local ret = vm:get_register(A)
        vm:set_register(0, ret)
    end
    
    vm:exit_callinfo()
end

-- return R[a] (in-block return)
-- Operands: B
function execute.op_return_blk(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
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
        err.raise(vm, error_class.LocalJumpError, `unexpected return`)
        return
    end

    -- Go back to the level where the proc was generated
    while proc.embracing_callinfo ~= vm.current_callinfo do
        -- Be sure to jump to ensures
        local handler = vm:get_catch_handler("ensure")
        if handler then
            vm.inst.cursor = vm.current_callinfo.irep.inst_idx + handler.target

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
function execute.op_break(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    local ret = vm:get_register(A)

    local self = vm:get_register(0)
    if self.type ~= "proc" then
        -- TODO verify
        err.raise(vm, error_class.LocalJumpError, "unexpected break")
        return
    end

    local proc = self.value
    assert(proc.caller_callinfo ~= nil)

    if proc.type ~= "lambda" and proc.caller_callinfo.dead then
        err.raise(vm, error_class.LocalJumpError, `break from proc-closure`)
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
            vm.inst.cursor = vm.current_callinfo.irep.inst_idx + handler.target
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
            vm.inst.cursor = vm.current_callinfo.irep.inst_idx + handler.target

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
function execute.op_blkpush(vm: VM, ext: number)
    local A, B = opcodes.fetch_BS(vm.inst, ext)

    local m1_count = bit32.band(bit32.rshift(B, 11), 0x3f)
    local rest = bit32.band(bit32.rshift(B, 10), 0x01)
    local m2_count = bit32.band(bit32.rshift(B, 5), 0x1f)
    local kd = bit32.band(bit32.rshift(B, 4), 0x01)
    local lv = bit32.band(B, 0x0f)

    local offset = m1_count + rest + m2_count + kd + 1

    local block: Value
    if lv == 0 then
        block = vm:get_register(offset)
    else
        local proc = vm:get_register(0)
        if proc.type ~= "proc" or proc.value.embracing_callinfo == nil or proc.value.embracing_callinfo.irep.num_regs <= offset then
            err.raise(vm, error_class.LocalJumpError, `unexpected yield`)
            return
        end

        local callinfo = proc.value.embracing_callinfo
        block = vm.registers[callinfo.self_reg_idx + offset]
    end

    if block.type ~= "proc" then
        err.raise(vm, error_class.LocalJumpError, `unexpected yield`)
        return
    end

    vm:set_register(A, block)
end

-- R[a] = R[a] + R[a+1]
-- Operands: B
function execute.op_add(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    
    local val1 = vm:get_register(A)
    local val2 = vm:get_register(A + 1)

    if val1.type == "integer" then 
        if val2.type == "integer" then
            vm:set_register(A, value.autocast(val1.value.number + val2.value.number, "integer"))
            return

        elseif val2.type == "float" then
            vm:set_register(A, value.autocast(val1.value.number + val2.value.number, "float"))
            return
        end
        
    elseif val1.type == "float" and (val2.type == "integer" or val2.type == "float") then
        vm:set_register(A, value.autocast(val1.value.number + val2.value.number, "float"))
        return
    end

    vm:send_by_name(symbol.str_to_symid("+"), A, 1)
end

-- R[a] = R[a] + mrb_int(b)
-- Operands: BB
function execute.op_addi(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)
    
    local val1 = vm:get_register(A)

    if val1.type == "integer" or val1.type == "float" then 
        vm:set_register(A, value.autocast(val1.value.number + B, val1.type))
        return
    end

    local value_type = if val1.type == "object" then val1.value.class.name else val1.type:gsub("^%l", string.upper)
    err.raise(vm, error_class.TypeError, `no implicit conversion of {value_type} to Integer`)
end

-- R[a] = R[a] - R[a+1]
-- Operands: B
function execute.op_sub(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    
    local val1 = vm:get_register(A)
    local val2 = vm:get_register(A + 1)

    if val1.type == "integer" then 
        if val2.type == "integer" then
            vm:set_register(A, value.autocast(val1.value.number - val2.value.number, "integer"))
            return

        elseif val2.type == "float" then
            vm:set_register(A, value.autocast(val1.value.number - val2.value.number, "float"))
            return
        end
        
    elseif val1.type == "float" and (val2.type == "integer" or val2.type == "float") then
        vm:set_register(A, value.autocast(val1.value.number - val2.value.number, "float"))
        return
    end

    vm:send_by_name(symbol.str_to_symid("-"), A, 1)
end

-- R[a] = R[a] - mrb_int(b)
-- Operands: BB
function execute.op_subi(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)
    
    local val1 = vm:get_register(A)

    if val1.type == "integer" or val1.type == "float" then 
        vm:set_register(A, value.autocast(val1.value.number - B, val1.type))
        return
    end

    local value_type = if val1.type == "object" then val1.value.class.name else val1.type:gsub("^%l", string.upper)
    err.raise(vm, error_class.TypeError, `no implicit conversion of {value_type} to Integer`)
end

-- R[a] = R[a] * R[a+1]
-- Operands: B
function execute.op_mul(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    
    local val1 = vm:get_register(A)
    local val2 = vm:get_register(A + 1)

    if val1.type == "integer" then 
        if val2.type == "integer" then
            vm:set_register(A, value.autocast(val1.value.number * val2.value.number, "integer"))
            return

        elseif val2.type == "float" then
            vm:set_register(A, value.autocast(val1.value.number * val2.value.number, "float"))
            return
        end
        
    elseif val1.type == "float" and (val2.type == "integer" or val2.type == "float") then
        vm:set_register(A, value.autocast(val1.value.number * val2.value.number, "float"))
        return
    end

    vm:send_by_name(symbol.str_to_symid("*"), A, 1)
end

-- R[a] = R[a] / R[a+1]
-- Operands: B
function execute.op_div(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    
    local val1 = vm:get_register(A)
    local val2 = vm:get_register(A + 1)

    if (val2.type == "integer" or val2.type == "float") and val2.value.number == 0 then
        err.raise(vm, error_class.ZeroDivisionError, `divided by 0`)
        return
    end

    if val1.type == "integer" then 
        if val2.type == "integer" then
            vm:set_register(A, value.autocast(val1.value.number / val2.value.number, "integer"))
            return

        elseif val2.type == "float" then
            vm:set_register(A, value.autocast(val1.value.number / val2.value.number, "float"))
            return
        end
        
    elseif val1.type == "float" and (val2.type == "integer" or val2.type == "float") then
        vm:set_register(A, value.autocast(val1.value.number / val2.value.number, "float"))
        return
    end

    vm:send_by_name(symbol.str_to_symid("/"), A, 1)
end

-- R[a] = R[a] == R[a+1]
-- Operands: B
function execute.op_eq(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    local val1 = vm:get_register(A)
    
    if val1.type == "object" then
        vm:send_by_name(symbol.str_to_symid("=="), A, 1)
        return
    end

    local res = value.compare(val1, vm:get_register(A + 1))
    vm:set_register(A, value.autocast(res == 0))
end

-- R[a] = R[a] < R[a+1]
-- Operands: B
function execute.op_lt(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    local val1 = vm:get_register(A)
    
    if val1.type == "object" then
        vm:send_by_name(symbol.str_to_symid("<"), A, 1)
        return
    end

    local res = value.compare(val1, vm:get_register(A + 1))
    vm:set_register(A, value.autocast(res < 0))
end

-- R[a] = R[a] <= R[a+1]
-- Operands: B
function execute.op_le(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    local val1 = vm:get_register(A)
    
    if val1.type == "object" then
        vm:send_by_name(symbol.str_to_symid("<="), A, 1)
        return
    end

    local res = value.compare(val1, vm:get_register(A + 1))
    vm:set_register(A, value.autocast(res <= 0))
end

-- R[a] = R[a] > R[a+1]
-- Operands: B
function execute.op_gt(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    local val1 = vm:get_register(A)
    
    if val1.type == "object" then
        vm:send_by_name(symbol.str_to_symid(">"), A, 1)
        return
    end

    local res = value.compare(val1, vm:get_register(A + 1))
    vm:set_register(A, value.autocast(res > 0))
end

-- R[a] = R[a] >= R[a+1]
-- Operands: B
function execute.op_ge(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    local val1 = vm:get_register(A)
    
    if val1.type == "object" then
        vm:send_by_name(symbol.str_to_symid(">="), A, 1)
        return
    end

    local res = value.compare(val1, vm:get_register(A + 1))
    vm:set_register(A, value.autocast(res >= 0))
end

-- R[a] = ary_new(R[a],R[a+1]..R[a+b])
-- Operands: BB
function execute.op_array(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local new_arr_val = class.instance_new(array_class)
    local new_arr = new_arr_val.value :: Array

    for i = A, A + B do
        table.insert(new_arr.array, vm:get_register(i))
        vm:set_register(i, nil :: any)
    end

    vm:set_register(A, new_arr_val)
end

-- R[a] = ary_new(R[b],R[b+1]..R[b+c])
-- Operands: BBB
function execute.op_array2(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)

    local new_arr_val = class.instance_new(array_class)
    local new_arr = new_arr_val.value :: Array

    for i = B, B + C do
        table.insert(new_arr.array, vm:get_register(i))
        vm:set_register(i, nil :: any)
    end

    vm:set_register(A, new_arr_val)
end

-- ary_cat(R[a],R[a+1])
-- Operands: B
function execute.op_arycat(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    local val1 = vm:get_register(A)
    assert(val1.type == "array")

    local val2 = vm:get_register(A + 1)
    assert(val2.type == "array")

    table.move(val2.value.array, 1, #val2.value.array, #val1.value.array + 1, val1.value.array)
end

-- ary_push(R[a],R[a+1]..R[a+b])
-- Operands: BB
function execute.op_arypush(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local val1 = vm:get_register(A)
    assert(val1.type == "array")

    for i = A + 1, B do
        table.insert(val1.value.array, vm:get_register(i))
        vm:set_register(i, nil :: any)
    end
end

-- R[a] = ary_dup(R[a])
-- Operands: B
function execute.op_arydup(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    local val1 = vm:get_register(A)
    assert(val1.type == "array")

    local new_arr_val = class.instance_new(array_class)
    local new_arr = new_arr_val.value :: Array
    new_arr.array = table.clone(val1.value.array)

    return vm:set_register(A, new_arr_val)
end

-- R[a] = R[b][c]
-- Operands: BBB
function execute.op_aref(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)

    local val1 = vm:get_register(B)

    if val1.type == "array" then
        vm:set_register(A, val1.value.array[C + 1])
    
    else
        if C == 0 then
            vm:set_register(A, vm:get_register(B))
            return
        end

        -- TODO: do we call .[] ?
        vm:set_register(A, value.autocast(nil))
    end
end

-- R[b][c] = R[a]
-- Operands: BBB
function execute.op_aset(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)

    local val1 = vm:get_register(B)
    assert(val1.type == "array")

    val1.value.array[C + 1] = vm:get_register(A)
end

-- *R[a],R[a+1]..R[a+c] = R[a][b..]
-- Operands: BBB
function execute.op_apost(vm: VM, ext: number)
    -- TODO what does this opcode even do?
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)

    local val1 = vm:get_register(A)
    if val1.type ~= "array" then
        val1 = {
            type = "array",
            value = {
                class = array_class,
                ivar = keyvalue.new(),
                array = table.clone(val1.value.array)
            } :: Array
        }
    end

    local pre = B
    local post = C
    

    assert(val1.type == "array") -- for the typechecker
    if #val1.value.array > pre + post then
        local ary_size = #val1.value.array - pre - post
        table.move(val1.value.array, pre + 1, pre + ary_size, 1, vm:get_register(A).value.array)
    
    else
        vm:set_register(A, {
            type = "array",
            value = {
                class = array_class,
                ivar = keyvalue.new(),
                array = table.clone(val1.value.array)
            } :: Array
        })
    end

end

-- R[a] = intern(R[a])
-- Operands: B
function execute.op_intern(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    local val = vm:get_register(A)
    assert(val.type == "string")

    local sym_id = symbol.str_to_symid(val.value.str)
    vm:set_register(A, value.autocast(sym_id, "symbol"))
end

-- R[a] = intern(Pool[b])
-- Operands: BB
function execute.op_symbol(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_str = vm.current_callinfo.irep.pool[B + 1]
    assert(type(sym_str) == "string")

    local sym_id = symbol.str_to_symid(sym_str)
    vm:set_register(A, value.autocast(sym_id, "symbol"))
end

-- R[a] = str_dup(Pool[b])
-- Operands: BB
function execute.op_string(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local str = vm.current_callinfo.irep.pool[B + 1]
    assert(type(str) == "string")

    local new_str_val = class.instance_new(string_class)
    local new_str = new_str_val.value :: String
    new_str.str = str

    vm:set_register(A, new_str_val)
end

-- str_cat(R[a], R[a+1])
-- Operands: B
function execute.op_strcat(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

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
function execute.op_hash(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local new_hash_val = class.instance_new(hash_class)
    local new_hash = new_hash_val.value :: Hash

    for i = A, A + 2*B - 1, 2 do
        local key = vm:get_register(i)
        local value = vm:get_register(i + 1)

        -- TODO
        new_hash.hash[key] = value
    end

    vm:set_register(A, new_hash_val)
end

-- hash_push(R[a],R[a+1]..R[a+b*2])
-- Operands: BB
function execute.op_hashadd(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)
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
function execute.op_hashcat(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    local hash1 = vm:get_register(A)
    assert(hash1.type == "hash")

    local hash2 = vm:get_register(A + 1)
    assert(hash1.type == "hash")

    local new_hash_val = class.instance_new(hash_class)
    local new_hash = new_hash_val.value :: Hash

    new_hash.hash = table.clone(hash1.value.hash)

    for k, v in hash2.value.hash do
        new_hash.hash[k] = v
    end

    vm:set_register(A, new_hash_val)
end

-- R[a] = lambda(Irep[b],L_LAMBDA)
-- Operands: BB
function execute.op_lambda(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local new_proc = proc_new(vm, vm.current_callinfo.irep.children[B + 1], "lambda")
    
    vm:set_register(A, {
        type = "proc",
        value = new_proc
    })
end

-- R[a] = lambda(Irep[b],L_BLOCK)
-- Operands: BB
function execute.op_block(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local new_proc = proc_new(vm, vm.current_callinfo.irep.children[B + 1], "block")
    
    vm:set_register(A, {
        type = "proc",
        value = new_proc
    })
end

-- R[a] = lambda(Irep[b],L_METHOD)
-- Operands: BB
function execute.op_method(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    -- Currently methods are like lambda
    -- TODO Make them into the Method class
    local new_proc = proc_new(vm, vm.current_callinfo.irep.children[B + 1], "method")
    
    vm:set_register(A, {
        type = "proc",
        value = new_proc
    })
end

-- R(a) = range_new(R(a),R(a+1),FALSE)
-- Operands: B
function execute.op_range_inc(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    error("not implemented")
end

-- R(a) = range_new(R(a),R(a+1),TRUE)
-- Operands: B
function execute.op_range_exc(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    error("not implemented")
end

-- R(a) = ::Object
-- Operands: B
function execute.op_oclass(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    
    vm:set_register(A, {
        type = "class",
        value = object_class
    })
end

-- R(a) = newclass(R(a),Syms(b),R(a+1))
-- Operands: BB
function execute.op_class(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)
    
    local class_name = symbol.symid_to_str(vm.current_callinfo.irep.syms[B + 1]) :: string
    local outer = vm:get_register(A)
    local val = vm:get_register(A + 1)
    local super = if val.type == "class" then val.value else object_class

    if super.is_singleton then
        err.raise(vm, error_class.TypeError, `can't make subclass of singleton class`)
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
        value = new_class
    })
end

-- R(a) = newmodule(R(a),Syms(b))
-- Operands: BB
function execute.op_module(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)
    
    local module_name = symbol.symid_to_str(vm.current_callinfo.irep.syms[B + 1]) :: string
    local outer = vm:get_register(A)

    local new_module: Class
    if outer.type == "class" then
        new_module = class.define_class_under(vm, outer.value, module_name, module_class)
    else
        new_module = class.define_class(vm, module_name, module_class)
    end

    new_module.is_module = true

    vm:set_register(A, {
        type = "class",
        value = new_module
    })
end

-- R(a) = blockexec(R(a),Irep(b))
-- Operands: BB
function execute.op_exec(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local val = vm:get_register(A)
    assert(val.type == "class")

    local child_irep = vm.current_callinfo.irep.children[B + 1]
    vm:enter_callinfo(nil, child_irep, val.value, A, 0)
end

-- R(a).newmethod(Syms(b),R(a+1)); R(a) = Syms(b)
-- Operands: BB
function execute.op_def(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local val1 = vm:get_register(A)
    assert(val1.type == "class") -- TODO Support Module
    
    local val2 = vm:get_register(A + 1)
    assert(val2.type == "proc")
    
    local sym_id = vm.current_callinfo.irep.syms[B + 1]
    
    val1.value.definitions[sym_id] = {
        sym_id = sym_id,
        type = "irep",
        value = val2.value.irep
    }

    vm:set_register(A, value.autocast(sym_id, "symbol"))
    vm:set_register(A + 1, nil :: any)
end

-- alias_method(target_class,Syms(a),Syms(b))
-- Operands: BB
function execute.op_alias(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local method_id = vm.current_callinfo.irep.syms[A + 1]
    local alias_id = vm.current_callinfo.irep.syms[B + 1]

    local cls = vm.current_callinfo.target_class
    if class.get_method(cls, method_id) == nil then
        err.raise(vm, error_class.NameError, `undefined method '{symbol.symid_to_str(method_id)}' for class '{cls.name}'`)
        return
    end

    cls.definitions[alias_id] = cls.definitions[method_id]
end

-- undef_method(target_class,Syms(a))
-- Operands: B
function execute.op_undef(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    local method_id = vm.current_callinfo.irep.syms[A + 1]

    local cls = vm.current_callinfo.target_class
    if class.get_method(cls, method_id) == nil then
        err.raise(vm, error_class.NameError, `undefined method '{symbol.symid_to_str(method_id)}' for class '{cls.name}'`)
        return
    end

    class.undefine_method(cls, method_id)
end

-- R(a) = R(a).singleton_class
-- Operands: B
function execute.op_sclass(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    local obj = vm:get_register(A)

    local sclass = class.get_singleton_class(obj.value)
    vm:set_register(A, {
        type = "class",
        value = sclass
    })
end

-- R[a] = target_class
-- Operands: B
function execute.op_tclass(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    vm:set_register(A, {
        type = "class",
        value = vm.current_callinfo.target_class
    })
end

-- print a,b,c
-- Operands: BBB
function execute.op_debug(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)
    print(A, B, C)
end

-- raise(LocalJumpError, Pool(a))
-- Operands: B
function execute.op_err(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    
    local message = vm.current_callinfo.irep.pool[A + 1]
    err.raise(vm, error_class.LocalJumpError, tostring(message))
end

function VM.run(vm: VM)
    local ext = 0
    while true do
        local inst = vm.inst:read_byte()
        local opcode = opcodes.opcodes[inst]
        assert(opcode ~= nil, `unknown opcode {inst}`)
        
        if opcode == "OP_EXT1" then
            ext = 1
            continue
        elseif opcode == "OP_EXT2" then
            ext = 2
            continue
        elseif opcode == "OP_EXT3" then
            ext = 3
            continue
        elseif opcode == "OP_STOP" then
            return
        end
    
        local func: ((vm: VM, ext: number) -> ())? = execute[ opcode:lower() ]
        assert(func ~= nil, `unknown or not implemented opcode: {inst} {opcode}`)
        
        if vm.debug_mode then
            print(`executing opcode: {tostring(opcode)}`) -- debug
        end
        func(vm, ext)
    
        if vm.debug_mode then
            print(`registers (after executing): (-> {vm.current_callinfo.self_reg_idx})`)
            for i, v in vm.registers do
                print(`  {i} = {if v.type == "object" then `#<{v.value.class.name}:{tostring(v.value):sub(#("table: ") + 1)}>` elseif v.type == "class" then v.value.name elseif v.type == "integer" then `int({v.value})` else v.type}`)
            end
            print("")
        end
    
        if ext ~= 0 then
            ext = 0
        end
    
        if vm.should_stop then
            return
        end
    
        if vm.exception.type == "nil" then
            continue
        end
        
        -- Handle exceptions and catch handlers
        while true do
            -- We should first search for a rescue, if not then an ensure
            local handler = vm:get_catch_handler("rescue") or vm:get_catch_handler("ensure")
            if handler then
                vm.inst.cursor = vm.current_callinfo.irep.inst_idx + handler.target
                break
            end
    
            -- We reached the end and couldn't find a catch handler
            if #vm.callinfo_stack == 0 then
                local ex = vm.exception.value :: Exception
                local msg = `in '{ex.method_id}': {ex.message} ({ex.class.name})`
    
                for i = #ex.call_nest, 1, -1 do
                    msg ..= `\n    in '{symbol.symid_to_str(ex.call_nest[i])}'`
                end
    
                error(msg)
            end
    
            vm:exit_callinfo()
        end
    end
end

return VM