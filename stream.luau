local ByteStream = {}
ByteStream.__index = ByteStream

function ByteStream.new(source: string)
    local self = {
        _source = source,
        cursor = 0
    }

    return setmetatable(self, ByteStream)
end

function ByteStream:read_byte(bytes: number?): number
    bytes = bytes or 1

    local res = 0
    for i, byte in { self._source:byte(self.cursor + 1, self.cursor + bytes) } do
        res = bit32.bor(bit32.lshift(byte, (bytes - i) * 8), res)
    end

    self.cursor += bytes

    return res
end

function ByteStream:read_string(length: number?): string
    
    if length == nil then
        local str = ""
        while true do
            local byte: number = self:read_byte()
            if byte == nil then
                -- incomplete!
                error("incomplete string")
            end

            if byte == 0x0 then
                return str
            end

            str ..= tostring(byte)
        end
    end

    local endIdx = self.cursor + length
    local str = self._source:sub(self.cursor + 1, endIdx)
    self.cursor = endIdx

    return str
end


function ByteStream:skip(bytes: number)
    self.cursor += bytes
end

function ByteStream:length(): number
    return #self._source
end

table.freeze(ByteStream)
return ByteStream