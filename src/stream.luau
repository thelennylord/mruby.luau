local ByteStream = {}
ByteStream.__index = ByteStream

function ByteStream.new(source: string)
    local self = {
        _source = source,
        cursor = 1
    }

    return setmetatable(self, ByteStream)
end

function ByteStream:read_byte(bytes: number?): number
    bytes = bytes or 1
    --assert(bytes > 0, `number of bytes must be greater than 0`)

    local res: number, new_pos: number
    if bytes == 1 then
        -- For optimization purposes
        res, new_pos = string.unpack(`>B`, self._source, self.cursor)
    else        
        res, new_pos = string.unpack(`>I{bytes}`, self._source, self.cursor)
    end

    self.cursor = new_pos
    return res
end

function ByteStream:read_string(length: number?): string
    if length then
        local str = self._source:sub(self.cursor, self.cursor + length - 1)
        self.cursor += length
        return str
    end
    
    local str, new_pos = string.unpack(">z", self._source, self.cursor)
    self.cursor = new_pos

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