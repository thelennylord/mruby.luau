local types = require("types")

type KeyValue = types.KeyValue
type Value = types.Value


local function new(): KeyValue
    local real: KeyValue = {}

    local mt = {
        __len = function(self)
            return self.__length
        end,

        __newindex = function(self, key, value)
            if not key then
                return
            end

            if real[key] ~= nil and value == nil then
                self.__length -= 1
            end
            
            if real[key] == nil and value ~= nil then
                self.__length += 1
            end

            real[key] = value
        end,

        __iter = function() 
            return pairs(real) 
        end,

        __index = real
    }


    return (setmetatable({ __iden = "KeyValue", __length = 0, __real = real }, mt) :: any) :: KeyValue
end

local function dup(tbl)
    local copy = new()

    rawset(copy, "__length", rawget(tbl, "__length"))
    rawset(copy, "__real", table.clone(rawget(tbl, "__real")))

    return copy
end

return {
    new = new,
    dup = dup :: (tbl: KeyValue) -> KeyValue
}