--!strict
local class = require("class")
local types = require("types")
local value = require("value")
local symbol = require("symbol")
local object_class = require("builtins/object")

type VM = types.VM
type Value = types.Value
type State = types.State
type Class = types.Class

local Exception = class.define_class(nil, "Exception", object_class)

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
        -- TODO Make use of string class
        ret = class.instance_new(class.get_class_from_name("String") :: Class)
        ret.value.str = val1.value.message
    else
        ret = value.autocast(symbol.symid_to_str(class.get_class(val1.value).sym_id), "symbol")
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
exports.NameError = class.define_class(nil, "NameError", exports.StandardError)
exports.NoMethodError = class.define_class(nil, "NoMethodError", exports.NameError)
exports.RangeError = class.define_class(nil, "RangeError", exports.StandardError)
exports.RuntimeError = class.define_class(nil, "RuntimeError", exports.StandardError)
exports.TypeError = class.define_class(nil, "TypeError", exports.StandardError)
exports.LocalJumpError = class.define_class(nil, "LocalJumpError", exports.StandardError)
exports.ZeroDivisionError = class.define_class(nil, "ZeroDivisionError", exports.StandardError)

return exports