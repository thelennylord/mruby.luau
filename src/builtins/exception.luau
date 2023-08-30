--!strict
local class = require("class")
local types = require("types")
local value = require("value")

type VM = types.VM
type Value = types.Value
type State = types.State
type Class = types.Class
type String = types.String

local Exception = class.define_class(nil, "Exception", nil :: any)

class.define_method(Exception, "initialize", function(state: State, argc: number)
	local val1 = state.get_register(0)
	assert(val1.type == "exception")

	if argc == 1 then
		local msg = state.get_register(1)
		-- TODO call to_str/to_s
		assert(msg.type == "string")

		val1.value.message = msg.value.str
	end
end)

class.define_method(Exception, "message", function(state: State, argc: number)
	local val1 = state.get_register(0)
	assert(val1.type == "exception")

	local ret: Value
	if val1.value.message ~= nil then
		ret = value.tostr(val1.value.message)
	else
		ret = value.tosymbol(class.get_class(val1.value).sym)
	end

	state.set_register(0, ret)
end)

return {}
