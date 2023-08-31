--!strict
-- Separate file containing all the types
-- Made to avoid cyclic dependency

--type class.luau
export type symbol = string

export type State = {
	get_register: (register: number) -> Value,
	set_register: (register: number, val: Value) -> (),
	send_by_name: (sym: string, A: number, C: number, super: boolean) -> (),
	vm: VM,
	current_self_idx: number,
}

export type LuaMethod = (state: State, argc: number) -> ()

export type Method = {
	sym: string,
	type: "irep",
	value: IREP,
} | {
	sym: string,
	type: "luafunc",
	value: LuaMethod,
}

export type Class = Object & {
	name: string,
	sym: string,
	superclass: Class,
	subclasses: { Class },
	cvar: { [symbol]: Value },
	definitions: { [symbol]: Method }, -- new_obj.methods = definitions when :new is sent

	is_singleton: boolean,
	attached_object: Object?, -- not nil if is_singleton == true

	is_module: boolean, -- Interface class
}

export type Object = {
	ivar: { [symbol]: Value },
	methods: { [symbol]: Method },
	class: Class,
}

export type String = Object & {
	str: string,
}

export type Range = Object & {
	iter_idx: number,
} & ({
	start: number,
	stop: number?,
} | {
	start: number?,
	stop: number,
})

export type Integer = Object & {
	number: number,
}

export type Float = Integer

export type Array = Object & {
	array: { Value },
}

type HashKey = Value
export type Hash = Object & {
	hash: { [HashKey]: Value },
}

export type Proc = Object & {
	type: "lambda" | "block" | "method",
	caller_callinfo: CallInfo?,
	embracing_callinfo: CallInfo,
	irep: IREP,
}

export type Symbol = Object & {
	symbol: string,
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
	target: number,
}

export type IREP = {
	num_locals: number,
	num_regs: number,
	inst_idx: number,
	num_instructions: number,
	catch_handlers: { CatchHandler },
	pool: { boolean | string | number },
	symbols: { symbol },
	children: { IREP },
}

export type CallInfo = {
	irep: IREP,
	inst_cursor_pos: number,
	self_reg_idx: number,
	target_class: Class,
	dead: boolean,

	arg_count: number,
	self_class: Class?,
	method_sym: symbol,
	deleted_kargs: { [Value]: Value },
	super_called: boolean,
}

type VMEnsure = {
	ensuring: boolean,
	target_callinfo: CallInfo,
	return_value: Value,
}

export type VM = {
	should_stop: boolean,
	top_irep: IREP,
	pc: number,
	inst: string,
	ext: number,
	registers: { Value },
	exception: Exception?,
	debug_mode: boolean,

	callinfo_stack: { CallInfo },
	current_callinfo: CallInfo,

	ensure_state: VMEnsure,

	-- Methods
	load: (self: VM, inst: string, irep: IREP) -> (),
	run: (self: VM) -> (),
	
	-- Gets the register relative to current_reg (Indexing begins from 1 just like lua)
	get_register: (self: VM, register: number) -> Value,
	set_register: (self: VM, register: number, value: Value) -> (),
	enter_callinfo: (
		self: VM,
		method_sym: symbol?,
		irep: IREP,
		target_class: Class,
		self_idx: number,
		arg_count: number
	) -> CallInfo,
	exit_callinfo: (self: VM) -> (),
	send_by_name: (
		self: VM,
		sym: string,
		A: number,
		C: number,
		super_called: boolean?,
		__wait_until_done: boolean?
	) -> (), -- __wait_until_done is used internally, do not use!
	get_self: (self: VM) -> Value,
	get_catch_handler: (self: VM, handler_type: string) -> CatchHandler?,
	read_instruction: (self: VM) -> "continue" | "stop" | "error",
}
--end

--type value.luau
export type IntegerValue = {
	type: "integer",
	value: Integer,
}

export type FloatValue = {
	type: "float",
	value: Float,
}

export type SymbolValue = {
	type: "symbol",
	value: Symbol,
}

export type TrueValue = {
	type: "true",
	value: TrueClass,
}

export type FalseValue = {
	type: "false",
	value: FalseClass,
}

export type NilValue = {
	type: "nil",
	value: NilClass,
}

export type ObjectValue = {
	type: "object",
	value: Object,
}

export type ClassValue = {
	type: "class",
	value: Class,
}

export type ProcValue = {
	type: "proc",
	value: Proc,
}

export type ArrayValue = {
	type: "array",
	value: Array,
}

export type StringValue = {
	type: "string",
	value: String,
}

export type RangeValue = {
	type: "range",
	value: Range,
}

export type HashValue = {
	type: "hash",
	value: Hash,
}

export type ExceptionValue = {
	type: "exception",
	value: Exception,
}

export type Value =
	IntegerValue
	| FloatValue
	| SymbolValue
	| TrueValue
	| FalseValue
	| NilValue
	| ObjectValue
	| ClassValue
	| ProcValue
	| ArrayValue
	| StringValue
	| RangeValue
	| HashValue
	| ExceptionValue
--end

--type error.luau
export type Exception = Object & {
	method_sym: symbol,
	message: string,
	call_nest: { symbol },
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

return {}
