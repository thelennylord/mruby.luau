--!strict
-- Separate file containing all the types
-- Made to avoid cyclic dependency

--type class.luau
export type State = {
    get_register: (register: number) -> Value,
    set_register: (register: number, val: Value) -> (),
    send_by_name: (sym_id: number, A: number, C: number, super: boolean) -> (),
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

export type Instance = unknown

export type Class = Object & {
    name: string,
    sym_id: number,
    superclass: Class,
    subclasses: { Class },
    cvar: KeyValue,
    definitions: { [number]: Method }, -- new_obj.methods = definitions when :new is sent

    is_singleton: boolean,
    attached_object: Object?, -- not nil if is_singleton == true

    is_module: boolean -- Interface class
}

export type Object = {
    ivar: KeyValue,
    methods: { [number]: Method },
    class: Class
}

export type String = Object & {
    str: string
}

export type Range = Object & {
    iter_idx: number
} & (
    {
        start: number,
        stop: number?
    } 
    | {
        start: number?,
        stop: number
    }
)

export type Integer = Object & {
    number: number
}

export type Float = Integer

export type Array = Object & {
    array: { Value }
}

type HashKey = string | boolean | number | Value
export type Hash = Object & {
    hash: { [HashKey]: Value }
}

export type Proc = Object & {
    type: "lambda" | "block" | "method",
    caller_callinfo: CallInfo?,
    embracing_callinfo: CallInfo,
    irep: IREP,
}

export type Symbol = Object & {
    sym_id: number,
    sym_str: string
}

export type TrueClass = Object
export type FalseClass = Object
export type NilClass = Object 
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
    irep: IREP,
    inst_cursor_pos: number,
    self_reg_idx: number,
    target_class: Class,
    dead: boolean,
    
    arg_count: number,
    self_class: Class?,
    method_id: number?,
    deleted_kargs: { [Value] : Value },
    super_called: boolean,
}

type VMEnsure = {
    ensuring: boolean,
    target_callinfo: CallInfo,
    return_value: Value
}

export type VM = {
    id: number,
    should_stop: boolean,
    permanence: boolean,
    top_irep: IREP,
    inst: ByteStream, -- pointer to instruction in binary stream
    registers: { Value },
    exception: Value,
    debug_mode: boolean,

    callinfo_stack: { CallInfo },
    current_callinfo: CallInfo,

    ensure_state: VMEnsure,

    -- Methods
    -- Gets the register relative to current_reg (Indexing begins from 1 just like lua)
    get_register: (self: VM, register: number) -> Value,
    set_register: (self: VM, register: number, value: Value) -> (),
    enter_callinfo: (self: VM, method_id: number?, irep: IREP, target_class: Class, self_idx: number, arg_count: number) -> CallInfo,
    exit_callinfo: (self: VM) -> (),
    send_by_name: (self: VM, sym_id: number, A: number, C: number, super_called: boolean?, __wait_until_done: boolean?) -> (), -- __wait_until_done is used internally, do not use!
    get_self: (self: VM) -> Value,
    get_catch_handler: (self: VM, handler_type: string) -> CatchHandler?,
    read_instruction: (self: VM) -> ("continue" | "stop" | "error")
};
--end

--type value.luau
export type Value = {
    type: "integer",
    value: Integer
} | {
    type: "float",
    value: Float
} | {
    type: "symbol",
    value: Symbol
} | {
    type: "true",
    value: TrueClass
} | {
    type: "false",
    value: FalseClass
} | {
    type: "nil",
    value: NilClass
} | {
    type: "object",
    value: Object
} | {
    type: "class",
    value: Class
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
    value: unknown
}
--end

--type keyvalue.luau
type sym_id = number
export type KeyValue = { [sym_id]: Value }
--end

--type error.luau
export type Exception = Object & {
    method_id: sym_id?,
    message: string,
    call_nest: { sym_id }
}
--

--type stream.luau
export type ByteStream = {
    cursor: number,

    read_byte: (self: ByteStream, bytes: number?) -> number,
    read_string: (self: ByteStream, length: number?) -> string,
    skip: (self: ByteStream, bytes: number) -> (),
    length: (self: ByteStream) -> number,
}
--

--type load.luau
export type Instruction = {
    opcode: number,
    operand: { number }
}
--

return {}