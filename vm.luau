--!strict
local types = require("types")
local opcodes = require("opcodes")
local value = require("value")
local symbol = require("symbol")
local global = require("global")
local class = require("class")
local keyvalue = require("keyvalue")
local hash_class = require("builtins/hash")
local array_class = require("builtins/array")
local err = require("error")
local error_class = require("builtins/errors")
local string_class = require("builtins/string")
local object_class = require("builtins/object")
local proc_class = require("builtins/proc")

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
type BinaryStream = types.BinaryStream

local function free_idx(tbl)
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

local function proc_new(vm: VM, irep: IREP, proc_type: string): Proc
    local proc = {
        type = proc_type,
        irep = irep,
        callinfo = vm.callinfo_tail,
        class = proc_class
    }

    if proc_type == "block" and vm:get_register(0).type == "proc" then
        proc.callinfo_self = vm:get_register(0).value.callinfo_self
    else
        proc.callinfo_self = vm.callinfo_tail
    end

    return proc :: any
end

local vm_map = {}

-- VM Class
local VM = {}
VM.__index = VM

function VM.new(debug_mode: boolean)
    local self = {
        id = -1,
        debug_mode = debug_mode or false,
        should_stop = false,
        exception = value.autocast(nil),
        current_self_idx = 1
    }

    return setmetatable(self, VM)
end

function VM.open(vm: VM)
    local id = free_idx(vm_map)
    vm_map[id] = vm

    vm.id = id
end

function VM.load(vm: VM, stream: BinaryStream, irep: IREP)
    assert(stream ~= nil)
    assert(irep ~= nil)

    vm.should_stop = false
    vm.permanence = false
    vm.top_irep = irep
    vm.current_irep = irep
    vm.target_class = object_class
    vm.registers = { { type = "class", value = object_class } }
    vm.current_self_idx = 1
    vm.exception = value.autocast(nil)
    vm.inst = stream

    stream.cursor = irep.inst_idx
end

function VM.close(vm: VM)
    vm_map[vm.id] = nil
end

function VM.get_self(vm: VM): Value
    local self = vm:get_register(0)
    if self.type == "proc" then
        local callinfo = self.value.callinfo_self
        if callinfo ~= nil then
            self = vm.registers[callinfo.current_self_idx + callinfo.reg_offset]
        else
            self = vm.registers[1]
        end
        
        assert(self.type ~= "proc")
    end
    
    return self
end

function VM.get_catch_handler(vm: VM, handler_type: string?): CatchHandler?
    if #vm.current_irep.catch_handlers then
        return nil
    end

    local inst_rel = vm.inst.cursor - vm.current_irep.inst_idx
    for _, handler in vm.current_irep.catch_handlers do
        if handler.type == handler_type 
            and handler.beginning <= inst_rel
            and inst_rel < handler.ending 
        then
            return handler
        end
    end

    return nil
end

function VM.handle_ensure(vm: VM, till: Proc)
    while true do
        local handler = vm:get_catch_handler("ensure")
        if handler then
            vm.inst.cursor = vm.current_irep.inst_idx + handler.target
            break
        end

        if vm.callinfo_tail == till then
            break
        end

        vm:pop_callinfo()
    end
end

local CALL_MAXARGS = 15
function VM.send_by_name(vm: VM, sym_id: number, A: number, C: number, call_super: boolean)
    assert(sym_id ~= nil)
    call_super = call_super or false
    -- OP_SEND:
    --     R[a] = R[a].send(Syms[b], R[a+1].., R[a+n+1]:R[a+n+2]..) (c = n|k<<4)

    local num_args = bit32.band(C, 0x0f)
    local num_kwargs = bit32.band(bit32.rshift(C, 4), 0x0f)
    local block_given = bit32.rshift(C, 8) ~= 0

    local args = {}

    -- Arguments are packed into an array, so unpack them
    if num_args == CALL_MAXARGS then
        local arg_array = vm:get_register(A + 1)
        assert(arg_array.type == "array")

        table.move(arg_array.value.array, 1, #arg_array.value.array, 1, args)
    elseif num_args > 0 then
        table.move(vm.registers, vm.current_self_idx + A + 1, vm.current_self_idx + A + num_args, 1, args)
    end

    -- Convert keyword arguments into hash
    local kw_start = if num_args == CALL_MAXARGS then vm.current_self_idx + A + 2 else vm.current_self_idx + A + num_args + 1
    if num_kwargs > 0 then
        if num_kwargs ~= CALL_MAXARGS then
            local kw_hash: Hash = {
                class = hash_class,
                ivar = keyvalue.new(),
                hash = {}
            }

            for i = 1, num_kwargs do
                local key = vm.registers[kw_start + i - 1]
                local val = vm.registers[kw_start + i]

                vm.registers[kw_start + i - 1] = nil
                vm.registers[kw_start + i] = nil

                if key.type == "string" then
                    kw_hash.hash[key.value.str] = val
                else
                    kw_hash.hash[key.value] = val
                end
            end

            table.insert(args, {
                type = "hash",
                value = kw_hash
            })
        else
            table.insert(args, vm.registers[kw_start])
        end
    end

    local proc_start = if num_kwargs == CALL_MAXARGS then kw_start + 1 else kw_start + num_kwargs 
    if block_given then
        table.insert(args, vm.registers[proc_start])
    end

    -- Clear all arguments
    for i = A + 1, A + #args do
        vm:set_register(i, nil :: any)
    end

    table.move(args, 1, #args, vm.current_self_idx + A + 1, vm.registers)

    local obj = vm:get_register(A)
    local cls = class.find_class_by_object(obj)
    
    if call_super then
        cls = cls.super
        --assert(cls ~= nil)
        if cls == nil then
            -- Normally this shouldn't happen
            err.raise(vm, error_class.NoMethodError, `no superclass method for {symbol.symid_to_str(sym_id)}`)
            return
        end
    end

    local method = class.find_method(cls, sym_id)
    if not method then
        err.raise(vm, error_class.NoMethodError, `undefined local variable or method '{symbol.symid_to_str(sym_id)}' for {cls.name}`)
        
        if vm.callinfo_tail ~= nil then
            (vm.exception.value :: Exception).method_id = vm.callinfo_tail.method_id
        end
        
        return
    end

    if method.type == "luafunc" then
        --local old_idx = vm.current_self_idx
        local curr_idx = vm.current_self_idx + A
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

    local callinfo = vm:push_callinfo(method.sym_id, A, if block_given then #args - 1 else #args)
    callinfo.own_class = cls
    callinfo.super_called = call_super

    vm.current_irep = method.value
    vm.inst.cursor = method.value.inst_idx
    vm.current_self_idx += A
end

function VM.push_callinfo(vm: VM, method_id: number?, reg_offset: number, num_args: number): CallInfo
    local callinfo: CallInfo = {
        current_irep = vm.current_irep,
        inst_idx = vm.inst.cursor,
        current_self_idx = vm.current_self_idx,
        target_class = vm.target_class,
        own_class = nil,
        method_id = method_id,
        reg_offset = reg_offset,
        num_args = num_args,
        prev = vm.callinfo_tail,
        super_called = false,
        kdict = nil
    }

    callinfo.prev = vm.callinfo_tail
    vm.callinfo_tail = callinfo

    return callinfo
end

function VM.pop_callinfo(vm: VM)
    assert(vm.callinfo_tail ~= nil)

    -- Clear used registers
    for i = vm.current_self_idx + 1, vm.current_irep.num_regs do
        vm.registers[i] = nil
    end
    
    local callinfo = vm.callinfo_tail
    callinfo.kdict = nil

    -- Restore VM to its state based on CallInfo
    vm.inst.cursor = callinfo.inst_idx
    vm.current_self_idx = callinfo.current_self_idx
    vm.current_irep = callinfo.current_irep
    vm.target_class = callinfo.target_class
    vm.callinfo_tail = callinfo.prev
end

function VM.get_register(vm: VM, register: number)
    assert(register ~= nil)
    assert(register >= 0)

    return vm.registers[vm.current_self_idx + register]
end

function VM.set_register(vm: VM, register: number, value: Value)
    assert(register ~= nil)
    assert(register >= 0)

    vm.registers[vm.current_self_idx + register] = value
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

    local val = value.autocast(vm.current_irep.pool[B + 1])
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
function execute.op_load32(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BSS(vm.inst, ext)

    local num = bit32.lshift(B, 16) + C
    vm:set_register(A, value.autocast(num, "integer"))
end

-- R[a] = Syms[b]
-- Operands: BB
function execute.op_loadsym(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_id = vm.current_irep.syms[B + 1]
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

    local sym_id = vm.current_irep.syms[B + 1]
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

    local sym_id = vm.current_irep.syms[B + 1]
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

    local sym_id = vm.current_irep.syms[B + 1]
    local self = vm:get_self()

    assert(self.type == "object")
    vm:set_register(A, self.value.ivar[sym_id])
end

-- ivset(Syms[b], R[a])
-- Operands: BB
function execute.op_setiv(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_id = vm.current_irep.syms[B + 1]
    local self = vm:get_self()

    assert(self.type == "object")
    self.value.ivar[sym_id] = vm:get_register(A)
end

-- R[a] = cvget(Syms[b])
-- Operands: BB
function execute.op_getcv(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_id = vm.current_irep.syms[B + 1]
    local self = vm:get_self()

    assert(self.type == "object")
    vm:set_register(A, self.value.class.cvar[sym_id])

end

-- cvset(Syms[b], R[a])
-- Operands: BB
function execute.op_setcv(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_id = vm.current_irep.syms[B + 1]
    local self = vm:get_self()

    assert(self.type == "object")
    self.value.class.cvar[sym_id] = vm:get_register(A)
end

-- R[a] = constget(Syms[b])
-- Operands: BB
function execute.op_getconst(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_id = vm.current_irep.syms[B + 1]

    vm:set_register(A, global.consts.get(sym_id))
end

-- constset(Syms[b], R[a])
-- Operands: BB
function execute.op_setconst(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local sym_id = vm.current_irep.syms[B + 1]

    global.consts.set(sym_id, vm:get_register(A))
end

-- R[a] = R[a]::Syms[b]
-- Operands: BB
function execute.op_getmcnst(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    error("not implemented")
end

-- R[a+1]::Syms[b] = R[a]
-- Operands: BB
function execute.op_setmcnst(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    error("not implemented")
end

-- R[a] = uvget(b,c)
-- Operands: BBB
function execute.op_getupvar(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)
    
    local proc = vm:get_register(0)
    assert(proc.type == "proc")

    local callinfo = proc.value.callinfo
    for _ = 1, C do
        assert(callinfo ~= nil)
        local val = vm.registers[callinfo.current_self_idx + callinfo.reg_offset]
        if val.type ~= "proc" then
            break -- TODO what to do?
        end

        callinfo = (val.value :: Proc).callinfo
    end

    local val: Value 
    if callinfo == nil then
        val = vm:get_register(B)
    else
        val = vm.registers[callinfo.current_self_idx + callinfo.reg_offset + B]
    end

    vm:set_register(A, val)
end

-- uvset(b,c,R[a])
-- Operands: BBB
function execute.op_setupvar(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)
    
    local proc = vm:get_register(0)
    assert(proc.type == "proc")

    local callinfo = proc.value.callinfo
    for _ = 1, C do
        assert(callinfo ~= nil)

        local val = vm.registers[callinfo.current_self_idx + callinfo.reg_offset]
        assert(val.type == "proc")
        
        callinfo = (val.value :: Proc).callinfo
    end

    if callinfo == nil then
        vm:set_register(B, vm:get_register(A))
    else
        vm.registers[callinfo.current_self_idx + callinfo.reg_offset + B] = vm:get_register(A)
    end
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

    vm.inst.cursor = vm.current_irep.inst_idx + handler.target
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

    local ret = class.obj_kind_of(val1, val2.value)
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
    local sym_id = vm.current_irep.syms[B + 1]

    vm:send_by_name(sym_id, A, C)
end

-- R[a] = self.send(Syms[b],R[a+1]..,R[a+n+1]:R[a+n+2]..,&R[a+n+2k+1])
-- Operands: BBB
function execute.op_ssendb(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)

    vm:set_register(A, vm:get_self())
    local sym_id = vm.current_irep.syms[B + 1]
    
    vm:send_by_name(sym_id, A, bit32.bor(C, 0x100))
end

-- R[a] = R[a].send(Syms[b],R[a+1]..,R[a+n+1]:R[a+n+2]..) (c=n|k<<4)
-- Operands: BBB
function execute.op_send(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)

    local sym_id = vm.current_irep.syms[B + 1]
    vm:send_by_name(sym_id, A, C)
end

-- R[a] = R[a].send(Syms[b],R[a+1]..,R[a+n+1]:R[a+n+2]..,&R[a+n+2k+1])
-- Operands: BBB
function execute.op_sendb(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)

    local sym_id = vm.current_irep.syms[B + 1]
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
    
    local callinfo = vm.callinfo_tail
    if callinfo == nil or callinfo.target_class == nil or callinfo.method_id == nil then
        err.raise(vm, error_class.NoMethodError, "super called outside of method")
        return
    end

    -- TODO When module is implemented, check if its a class or a module
    vm:send_by_name(callinfo.method_id, A, B, true)
    error("not implemented")    
end

-- R[a] = argument array (16=m5:r1:m5:d1:lv4)
-- Operands: BS
function execute.op_argary(vm: VM, ext: number)
    local A, B = opcodes.fetch_BS(vm.inst, ext)

    local callinfo = vm.callinfo_tail
    if callinfo == nil or callinfo.target_class == nil or callinfo.method_id == nil then
        err.raise(vm, error_class.NoMethodError, "super called outside of method")
        return
    end

    local m1_count = bit32.band(bit32.rshift(B, 11), 0x3f)
    local rest = bit32.band(bit32.rshift(B, 10), 0x01) ~= 0
    local m2_count = bit32.band(bit32.rshift(B, 5), 0x1f)
    local kd = bit32.band(bit32.rshift(B, 4), 0x01) ~= 0
    local lv_count = bit32.band(B, 0x0f)

    error("not implemented")
end

-- arg setup according to flags (23=m5:o5:r1:m5:k5:d1:b1)
-- Operands: W
function execute.op_enter(vm: VM, ext: number)
    local A = opcodes.fetch_W(vm.inst, ext)
    local m1_count = bit32.rshift(A, 18)
    local optional_count = bit32.band(bit32.rshift(A, 13), 0x1f)
    local should_rest = bit32.band(bit32.rshift(A, 12), 0x01) ~= 0
    local m2_count = bit32.band(bit32.rshift(A, 7), 0x1f)
    local kwargs_count = bit32.band(bit32.rshift(A, 2), 0x1f)
    local should_dict = bit32.band(bit32.rshift(A, 1), 0x01) ~= 0
    local check_block = bit32.band(A, 0x01) ~= 0

    assert(vm.callinfo_tail ~= nil)

    local args_given = vm.callinfo_tail.num_args
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
        local new_arr: Array = {
            class = array_class,
            ivar = keyvalue.new(),
            array = {}
        }

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

        vm:set_register(reg_idx, {
            type = "array",
            value = new_arr
        })
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

        vm.callinfo_tail.kdict = hash.value

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
    vm.callinfo_tail.num_args = reg_idx - 1

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
    
    assert(vm.callinfo_tail ~= nil)

    local kdict = vm:get_register(vm.callinfo_tail.num_args)
    assert(kdict.type == "hash")

    local sym_id = vm.current_irep.syms[B + 1]

    for _, v in kdict.value.hash do
        if v.type == "symbol" and v.value == sym_id then
            vm:set_register(A, value.autocast(true))
            return
        end
    end

    vm:set_register(A, value.autocast(false))
end

-- raise unless kdict.empty?
-- Operands: Z
function execute.op_keyend(vm: VM, ext: number)
    assert(vm.callinfo_tail ~= nil)

    local kdict = vm:get_register(vm.callinfo_tail.num_args)
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

    assert(vm.callinfo_tail ~= nil)

    local kdict = vm:get_register(vm.callinfo_tail.num_args)
    assert(kdict.type == "hash")
    
    local sym_id = vm.current_irep.syms[B + 1]
    local ret: Value?
    for k, v in kdict.value.hash do
        if v.type == "symbol" and v.value == sym_id then
            ret = v
            kdict.value.hash[k] = nil
            break
        end
    end

    if ret == nil then
        err.raise(vm, error_class.ArgumentError, `missing keyword: {sym_id}`)
        return
    end

    vm:set_register(A, ret)
end

-- return R[a] (normal)
-- Operands: B
function execute.op_return(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    -- Jump to ensure if exists
    local handler = vm:get_catch_handler("ensure")
    if handler then
        vm.inst.cursor = vm.current_irep.inst_idx + handler.target
        return
    end

    -- Ignore and stop the VM if it's a top level return
    local callinfo = vm.callinfo_tail

    if vm.target_callinfo ~= nil then
        -- There is a saved return value from OP_RETURN_BLK (we can assume we are here due to an ensure)
        -- As you can explicitly return in an ensure, we need to make sure whether the ensure has a return or not
        -- If this return is the last instruction then we can assume that the ensure doesn't have an explicit return
        if vm.inst.cursor == vm.current_irep.inst_idx + vm.current_irep.num_instructions - 1 then
            vm:pop_callinfo()
            return
        end

        -- ensure has an explicit return, so we discard the return value (CRuby seems to do this)
        vm.target_callinfo = nil
        vm.return_value = nil
    end
    
    if callinfo == nil then
        print("warning: argument of top-level return is ignored")
        vm.should_stop = true
        return
    end
    
    -- Ignore initialize method's return as that always returns a new object of a Class (internally done via a lua function)
    if callinfo.method_id ~= symbol.str_to_symid("initialize") then
        local ret = vm:get_register(A)
        vm:set_register(0, ret)
    end
    
    vm:pop_callinfo()
end

-- return R[a] (in-block return)
-- Operands: B
function execute.op_return_blk(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    local ret = vm:get_register(A)
    
    local self = vm:get_register(0)

    assert(self.type == "proc")
    local proc = self.value
    
    -- Go back to the level where the proc was generated
    while vm.callinfo_tail ~= nil or vm.callinfo_tail ~= proc.callinfo_self do
        -- Be sure to jump to ensures
        local handler = vm:get_catch_handler("ensure")
        if handler then
            vm.inst.cursor = vm.current_irep.inst_idx + handler.target
            vm.return_value = ret
            vm.target_callinfo = proc.callinfo_self
            return
        end

        vm:pop_callinfo()
    end

    -- TODO check this lol
    if vm.callinfo_tail == nil then
        err.raise(vm, error_class.LocalJumpError, "unexpected return")
        return
    end

    vm:set_register(0, ret)
    vm:pop_callinfo()
end

-- break R[a]
-- Operands: B
function execute.op_break(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    local ret = vm:get_register(A)

    local self = vm:get_register(0)
    local callinfo = vm.callinfo_tail
    if self.type ~= "proc" or callinfo == nil then
        -- TODO verify
        err.raise(vm, error_class.LocalJumpError, "unexpected break")
        return
    end

    assert(self.type == "proc")
    local proc = self.value
    
    if vm.callinfo_tail == nil then
        err.raise(vm, error_class.LocalJumpError, "unexpected break")
        return
    end
    
    -- If it's lambda, treat break as return
    local handler = vm:get_catch_handler("ensure")
    if proc.type == "lambda" then
        if handler then
            vm.inst.cursor = vm.current_irep.inst_idx + handler.target
        else
            vm:set_register(0, ret)
            vm:pop_callinfo()
        end

        return
    end

    -- Break returns the block and the caller calling the block (verify)
    local target_callinfo = proc.callinfo.prev
    if target_callinfo == nil then
        err.raise(vm, error_class.LocalJumpError, "unexpected break")
        return
    end

    -- Loop for handling ensure
    while vm.callinfo_tail ~= nil or vm.callinfo_tail ~= target_callinfo do
        if handler then
            vm.inst.cursor = vm.current_irep.inst_idx + handler.target
            vm.return_value = ret
            vm.target_callinfo = proc.callinfo_self
            return
        end

        vm:pop_callinfo()
    end

    err.raise(vm, error_class.LocalJumpError, "unexpected break")
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
        if proc.type ~= "proc" or proc.value.callinfo_self == nil or proc.value.callinfo_self.current_irep.num_regs <= offset then
            err.raise(vm, error_class.LocalJumpError, `unexpected yield`)
            return
        end

        local callinfo = proc.value.callinfo_self
        block = vm.registers[callinfo.current_self_idx + callinfo.reg_offset + offset]
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
            val1.value += val2.value
            return

        elseif val2.type == "float" then
            val1.value += val2.value
            val1.type = "float"
            return
        end
        
    elseif val1.type == "float" and (val2.type == "integer" or val2.type == "float") then
        val1.value += val2.value
        return
    end

    vm:send_by_name(symbol.str_to_symid("+"), A, 1)
end

-- R[a] = R[a] + mrb_int(b)
-- Operands: BB
function execute.op_addi(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)
    
    local val1 = vm:get_register(A)
    local val2 = value.autocast(B, "integer")

    if val1.type == "integer" or val1.type == "float" then 
        val1.value += val2.value
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
            val1.value -= val2.value
            return

        elseif val2.type == "float" then
            val1.value -= val2.value
            val1.type = "float"
            return
        end
        
    elseif val1.type == "float" and (val2.type == "integer" or val2.type == "float") then
        val1.value -= val2.value
        return
    end

    vm:send_by_name(symbol.str_to_symid("-"), A, 1)
end

-- R[a] = R[a] - mrb_int(b)
-- Operands: BB
function execute.op_subi(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)
    
    local val1 = vm:get_register(A)
    local val2 = value.autocast(B, "integer")

    if val1.type == "integer" or val1.type == "float" then 
        val1.value -= val2.value
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
            val1.value *= val2.value
            return

        elseif val2.type == "float" then
            val1.value *= val2.value
            val1.type = "float"
            return
        end
        
    elseif val1.type == "float" and (val2.type == "integer" or val2.type == "float") then
        val1.value *= val2.value
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

    if (val2.type == "integer" or val2.type == "float") and val2.value == 0 then
        err.raise(vm, error_class.ZeroDivisionError, `divided by 0`)
        return
    end

    if val1.type == "integer" then 
        if val2.type == "integer" then
            val1.value /= val2.value
            return

        elseif val2.type == "float" then
            val1.value /= val2.value
            val1.type = "float"
            return
        end
        
    elseif val1.type == "float" and (val2.type == "integer" or val2.type == "float") then
        val1.value /= val2.value
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

    local new_arr: Array = {
        class = array_class,
        ivar = keyvalue.new(),
        array = {}
    }

    for i = A, A + B do
        table.insert(new_arr.array, vm:get_register(i))
        vm:set_register(i, nil :: any)
    end

    vm:set_register(A, {
        type = "array",
        value = new_arr
    })
end

-- R[a] = ary_new(R[b],R[b+1]..R[b+c])
-- Operands: BBB
function execute.op_array2(vm: VM, ext: number)
    local A, B, C = opcodes.fetch_BBB(vm.inst, ext)

    local new_arr: Array = {
        class = array_class,
        ivar = keyvalue.new(),
        array = {}
    }

    for i = B, C do
        table.insert(new_arr.array, vm:get_register(i))
        vm:set_register(i, nil :: any)
    end

    vm:set_register(A, {
        type = "array",
        value = new_arr
    })
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

    local new_arr: Array = {
        class = array_class,
        ivar = keyvalue.new(),
        array = table.clone(val1.value.array)
    }

    return vm:set_register(A, {
        type = "array",
        value = new_arr
    })
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

    local sym_str = vm.current_irep.pool[B + 1]
    assert(type(sym_str) == "string")

    local sym_id = symbol.str_to_symid(sym_str)
    vm:set_register(A, value.autocast(sym_id, "symbol"))
end

-- R[a] = str_dup(Pool[b])
-- Operands: BB
function execute.op_string(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local str = vm.current_irep.pool[B + 1]
    assert(type(str) == "string")

    local new_str: String = {
        class = string_class,
        ivar = keyvalue.new(),
        str = str
    }
    vm:set_register(A, {
        type = "string",
        value = new_str
    })
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
    local new_hash: Hash = {
        class = hash_class,
        ivar = keyvalue.new(),
        hash = {}
    }

    for i = A, A + 2*B - 1, 2 do
        local key = vm:get_register(i)
        local value = vm:get_register(i + 1)

        -- TODO
        new_hash.hash[key] = value
    end

    vm:set_register(A, {
        type = "hash",
        value = new_hash
    })
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

    local new_hash: Hash = {
        class = hash_class,
        ivar = keyvalue.new(),
        hash = table.clone(hash1.value.hash)
    }

    for k, v in hash2.value.hash do
        new_hash.hash[k] = v
    end

    vm:set_register(A, {
        type = "hash",
        value = new_hash
    })
end

-- R[a] = lambda(Irep[b],L_LAMBDA)
-- Operands: BB
function execute.op_lambda(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local new_proc = proc_new(vm, vm.current_irep.children[B + 1], "lambda")
    
    vm:set_register(A, {
        type = "proc",
        value = new_proc
    })
end

-- R[a] = lambda(Irep[b],L_BLOCK)
-- Operands: BB
function execute.op_block(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local new_proc = proc_new(vm, vm.current_irep.children[B + 1], "block")
    
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
    local new_proc = proc_new(vm, vm.current_irep.children[B + 1], "method")
    
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
    
    local class_name = symbol.symid_to_str(vm.current_irep.syms[B + 1]) :: string
    local outer = vm:get_register(A)
    local val = vm:get_register(A + 1)
    local super = if val.type == "class" then val.value else object_class

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
    error("not implemented")
end

-- R(a) = blockexec(R(a),Irep(b))
-- Operands: BB
function execute.op_exec(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local val = vm:get_register(A)
    assert(val.type == "class") -- TODO Support Module

    local callinfo = vm:push_callinfo(0, A, 0)

    vm.current_irep = vm.current_irep.children[B + 1]
    vm.inst.cursor = vm.current_irep.inst_idx
    vm.current_self_idx += A
    vm.target_class = val.value
    vm.callinfo_tail = callinfo
end

-- R(a).newmethod(Syms(b),R(a+1)); R(a) = Syms(b)
-- Operands: BB
function execute.op_def(vm: VM, ext: number)
    local A, B = opcodes.fetch_BB(vm.inst, ext)

    local val1 = vm:get_register(A)
    assert(val1.type == "class") -- TODO Support Module
    
    local val2 = vm:get_register(A + 1)
    assert(val2.type == "proc")
    
    local sym_id = vm.current_irep.syms[B + 1]
    
    val1.value.methods[sym_id] = {
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

    local method_id = vm.current_irep.syms[A + 1]
    local alias_id = vm.current_irep.syms[B + 1]

    local cls = vm.target_class
    if class.find_method(cls, method_id) == nil then
        err.raise(vm, error_class.NameError, `undefined method '{symbol.symid_to_str(method_id)}' for class '{cls.name}'`)
        return
    end

    cls.methods[alias_id] = cls.methods[method_id]
end

-- undef_method(target_class,Syms(a))
-- Operands: B
function execute.op_undef(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)

    local method_id = vm.current_irep.syms[A + 1]

    local cls = vm.target_class
    if class.find_method(cls, method_id) == nil then
        err.raise(vm, error_class.NameError, `undefined method '{symbol.symid_to_str(method_id)}' for class '{cls.name}'`)
        return
    end

    class.undefine_method(cls, method_id)
end

-- R(a) = R(a).singleton_class
-- Operands: B
function execute.op_sclass(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    error("not implemented")
end

-- R[a] = target_class
-- Operands: B
function execute.op_tclass(vm: VM, ext: number)
    local A = opcodes.fetch_B(vm.inst, ext)
    vm:set_register(A, {
        type = "class",
        value = vm.target_class
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
    
    local message = vm.current_irep.pool[A + 1]
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
            break
        end

        local func: ((vm: VM, ext: number) -> ())? = execute[ opcode:lower() ]
        assert(func ~= nil, `unknown or not implemented opcode: {inst} {opcode}`)
        
        if vm.debug_mode then
            print(`executing opcode: {tostring(opcode)}`) -- debug
        end
        func(vm, ext)

        if vm.debug_mode then
            print(`registers (after executing): (-> {vm.current_self_idx})`)
            for i, v in vm.registers do
                print(`  {i} = {if v.type == "object" then v.value.class.name else v.type}`)
            end
            print("")
        end

        if ext ~= 0 then
            ext = 0
        end

        if vm.should_stop then
            break
        end

        if vm.exception.type == "nil" then
            continue
        end
        
        -- Handle exceptions and catch handlers
        while true do
            -- We should first search for a rescue, if not then an ensure
            local handler = vm:get_catch_handler("rescue") or vm:get_catch_handler("ensure")
            if handler then
                vm.inst.cursor = vm.current_irep.inst_idx + handler.target
                break
            end

            -- We reached the end and couldn't find a catch handler
            if not vm.callinfo_tail then
                local ex = vm.exception.value :: Exception
                local msg = `{ex.message} ({ex.class.name})`

                for i = #ex.call_nest, 1, -1 do
                    msg ..= `\n    in '{symbol.symid_to_str(ex.call_nest[i])}'`
                end

                error(msg)
                return
            end

            vm:pop_callinfo()
        end
    end
end

return VM