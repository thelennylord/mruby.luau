--!strict
local class = require("class")
local types = require("types")
local error = require("error")
local value = require("value")
local symbol = require("symbol")
local objectClass = require("builtins/object")

type VM = types.VM
type Value = types.Value
type State = types.State

local Exception = class.define_class(nil, "Exception", objectClass)

class.define_method(Exception, "new", function(state: State, argc: number)
    local val1 = state.get_register(0)
    assert(val1.type == "class")

    local ret: Value
    if argc == 1 and state.get_register(1).type == "string" then
        local str = state.get_register(1).value
        ret = error.exception_new(state.vm, val1.value, str)
    else
        ret = error.exception_new(state.vm, val1.value, "")
    end

    state.set_register(0, ret)
end)

class.define_method(Exception, "message", function(state: State, argc: number)
    local val1 = state.get_register(0)
    assert(val1.type == "exception")

    local ret: Value
    if val1.value.message ~= nil then
        ret = value.autocast(val1.value.message)
    else
        ret = value.autocast(symbol.symid_to_str(val1.value.class.sym_id))
    end

    state.set_register(0, ret)
end)

local exports = {}

exports.Exception = Exception
exports.NoMemoryError = class.define_class(nil, "NoMemoryError", Exception)
exports.NotImplementedError = class.define_class(nil, "NotImplementedError", Exception)
exports.StandardError = class.define_class(nil, "StandardError", Exception)
exports.ArgumentError = class.define_class(nil, "ArgumentError", exports.StandardError)
exports.IndexError = class.define_class(nil, "IndexError", exports.StandardError)
exports.NameError = class.define_class(nil, "NameError ", exports.StandardError)
exports.NoMethodError = class.define_class(nil, "NoMethodError", exports.NameError)
exports.RangeError = class.define_class(nil, "RangeError", exports.StandardError)
exports.RuntimeError = class.define_class(nil, "RuntimeError", exports.StandardError)
exports.TypeError = class.define_class(nil, "TypeError", exports.StandardError)
exports.LocalJumpError = class.define_class(nil, "LocalJumpError", exports.StandardError)
exports.ZeroDivisionError = class.define_class(nil, "ZeroDivisionError", exports.StandardError)

return exports