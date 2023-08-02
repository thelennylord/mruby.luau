--!strict
-- Separate file containing all the types
-- Made to avoid cyclic dependency

--type class.luau
export type State = {
    get_register: (register: number) -> Value,
    set_register: (register: number, val: Value) -> (),
    vm: VM,
    current_self_idx: number
}
export type LuaMethod = (state: State, argc: number) -> ()

export type Method = { 
    sym_id: number, 
    type: "irep", 
    value: IREP 
} | { 
    sym_id: number,
    type: "luafunc", 
    value: LuaMethod 
}

export type Class = {
    name: string,
    sym_id: number,
    super: Class,
    cvar: KeyValue,
    methods: { [number]: Method }
}

export type Instance = {
    class: Class,
    ivar: KeyValue
}

export type String = Instance & {
    str: string
}

export type Range = Instance & {
    start: number,
    stop: number,
    iter_idx: number
}

export type Integer = Instance & {
    num: number
}

export type Float = Integer

export type Array = Instance & {
    array: { Value }
}

type HashKey = string | boolean | number | Value
export type Hash = Instance & {
    hash: { [HashKey]: Value }
}

export type Proc = {
    type: "lambda" | "block" | "method",
    callinfo: CallInfo,
    callinfo_self: CallInfo,
    irep: IREP,
    ret_val: Value?,
    class: Class
}
--end

--types vm.luau
export type CatchHandler = {
    type: "rescue" | "ensure",
    beginning: number,
    ending: number,
    target: number
}

export type IREP = {
    num_locals: number,
    num_regs: number,
    inst_idx: number,
    num_instructions: number,
    catch_handlers: { CatchHandler },
    pool: { boolean | string | number },
    debug_instructions: { Instruction }, -- Debug only
    syms: { number },
    children: { IREP }
}

export type CallInfo = {
    prev: CallInfo?,
    current_irep: IREP,
    inst_idx: number,
    current_self_idx: number,
    target_class: Class,

    own_class: Class?,
    method_id: number?,
    reg_offset: number,
    num_args: number,
    kdict: Hash?,
    super_called: boolean
}

export type VM = {
    id: number,
    should_stop: boolean,
    permanence: boolean,

    top_irep: IREP,
    current_irep: IREP,
    callinfo_tail: CallInfo?,
    inst: BinaryStream, -- pointer to instruction in binary stream
    target_class: Class,
    reg_size: number,
    current_self_idx: number,
    registers: { Value },
    return_value: Value?,
    target_callinfo: CallInfo?,
    exception: Value,
    debug_mode: boolean,

    -- Methods
    -- Gets the register relative to current_reg (Indexing begins from 1 just like lua)
    get_register: (self: VM, register: number) -> Value,
    set_register: (self: VM, register: number, value: Value) -> (),
    push_callinfo: (self: VM, method_id: number, reg_offset: number, num_args: number) -> CallInfo,
    pop_callinfo: (self: VM) -> (),
    send_by_name: (self: VM, sym_id: number, A: number, C: number, super_called: boolean?) -> (),
    get_self: (self: VM) -> Value,
    get_catch_handler: (self: VM, handler_type: string) -> CatchHandler?,
}
--end

--type value.luau
export type Value = {
    type: "integer" | "float" | "symbol",
    value: number
} | {
    type: "true" | "false",
    value: boolean
} | {
    type: "nil",
    value: nil
} | {
    type: "object",
    value: Instance
} | {
    type: "class",
    value: Class
} | {
    type: "instance",
    value: Instance
} | {
    type: "proc",
    value: Proc
} | {
    type: "array",
    value: Array
} | {
    type: "string",
    value: String
} | {
    type: "range",
    value: any
} |  {
    type: "hash",
    value: Hash
} | {
    type: "exception",
    value: Exception
} | {
    type: "empty",
    value: nil
}
--end

--type symbol.luau
export type Symbol = string
--end

--type keyvalue.luau
type sym_id = number
export type KeyValue = { [sym_id]: Value }
--end

--type error.luau
export type Exception = Instance & {
    method_id: sym_id?,
    message: string,
    call_nest: { sym_id }
}
--

--type stream.luau
export type BinaryStream = {
    cursor: number,

    read_byte: (self: BinaryStream, bytes: number?) -> number,
    read_string: (self: BinaryStream, length: number?) -> string,
    skip: (self: BinaryStream, bytes: number) -> (),
    length: (self: BinaryStream) -> number,
}
--

--type load.luau
export type Instruction = {
    opcode: number,
    operand: { number }
}
--

return {}