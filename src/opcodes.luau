--!strict

local types = require("types")

type ByteStream = types.ByteStream

local opcodes = {
    [0] = "OP_NOP",
    [1] = "OP_MOVE",
    [2] = "OP_LOADL",
    [3] = "OP_LOADI",
    [4] = "OP_LOADINEG",
    [5] = "OP_LOADI__1",
    [6] = "OP_LOADI_0",
    [7] = "OP_LOADI_1",
    [8] = "OP_LOADI_2",
    [9] = "OP_LOADI_3",
    [10] = "OP_LOADI_4",
    [11] = "OP_LOADI_5",
    [12] = "OP_LOADI_6",
    [13] = "OP_LOADI_7",
    [14] = "OP_LOADI16",
    [15] = "OP_LOADI32",
    [16] = "OP_LOADSYM",
    [17] = "OP_LOADNIL",
    [18] = "OP_LOADSELF",
    [19] = "OP_LOADT",
    [20] = "OP_LOADF",
    [21] = "OP_GETGV",
    [22] = "OP_SETGV",
    [23] = "OP_GETSV",
    [24] = "OP_SETSV",
    [25] = "OP_GETIV",
    [26] = "OP_SETIV",
    [27] = "OP_GETCV",
    [28] = "OP_SETCV",
    [29] = "OP_GETCONST",
    [30] = "OP_SETCONST",
    [31] = "OP_GETMCNST",
    [32] = "OP_SETMCNST",
    [33] = "OP_GETUPVAR",
    [34] = "OP_SETUPVAR",
    [35] = "OP_GETIDX",
    [36] = "OP_SETIDX",
    [37] = "OP_JMP",
    [38] = "OP_JMPIF",
    [39] = "OP_JMPNOT",
    [40] = "OP_JMPNIL",
    [41] = "OP_JMPUW",
    [42] = "OP_EXCEPT",
    [43] = "OP_RESCUE",
    [44] = "OP_RAISEIF",
    [45] = "OP_SSEND",
    [46] = "OP_SSENDB",
    [47] = "OP_SEND",
    [48] = "OP_SENDB",
    [49] = "OP_CALL",
    [50] = "OP_SUPER",
    [51] = "OP_ARGARY",
    [52] = "OP_ENTER",
    [53] = "OP_KEY_P",
    [54] = "OP_KEYEND",
    [55] = "OP_KARG",
    [56] = "OP_RETURN",
    [57] = "OP_RETURN_BLK",
    [58] = "OP_BREAK",
    [59] = "OP_BLKPUSH",
    [60] = "OP_ADD",
    [61] = "OP_ADDI",
    [62] = "OP_SUB",
    [63] = "OP_SUBI",
    [64] = "OP_MUL",
    [65] = "OP_DIV",
    [66] = "OP_EQ",
    [67] = "OP_LT",
    [68] = "OP_LE",
    [69] = "OP_GT",
    [70] = "OP_GE",
    [71] = "OP_ARRAY",
    [72] = "OP_ARRAY2",
    [73] = "OP_ARYCAT",
    [74] = "OP_ARYPUSH",
    [75] = "OP_ARYDUP",
    [76] = "OP_AREF",
    [77] = "OP_ASET",
    [78] = "OP_APOST",
    [79] = "OP_INTERN",
    [80] = "OP_SYMBOL",
    [81] = "OP_STRING",
    [82] = "OP_STRCAT",
    [83] = "OP_HASH",
    [84] = "OP_HASHADD",
    [85] = "OP_HASHCAT",
    [86] = "OP_LAMBDA",
    [87] = "OP_BLOCK",
    [88] = "OP_METHOD",
    [89] = "OP_RANGE_INC",
    [90] = "OP_RANGE_EXC",
    [91] = "OP_OCLASS",
    [92] = "OP_CLASS",
    [93] = "OP_MODULE",
    [94] = "OP_EXEC",
    [95] = "OP_DEF",
    [96] = "OP_ALIAS",
    [97] = "OP_UNDEF",
    [98] = "OP_SCLASS",
    [99] = "OP_TCLASS",
    [100] = "OP_DEBUG",
    [101] = "OP_ERR",
    [102] = "OP_EXT1",
    [103] = "OP_EXT2",
    [104] = "OP_EXT3",
    [105] = "OP_STOP",
}

--[[
    List of operands of each opcode
    - Z = No operand
    - B = 8 bit
    - S = 16 bit
    - W = 24 bit
]]
local operands = {
    [0] = {},
    [1] = {"B", "B"},
    [2] = {"B", "B"},
    [3] = {"B", "B"},
    [4] = {"B", "B"},
    [5] = {"B"},
    [6] = {"B"},
    [7] = {"B"},
    [8] = {"B"},
    [9] = {"B"},
    [10] = {"B"},
    [11] = {"B"},
    [12] = {"B"},
    [13] = {"B"},
    [14] = {"B", "S"},
    [15] = {"B", "S", "S"},
    [16] = {"B", "B"},
    [17] = {"B"},
    [18] = {"B"},
    [19] = {"B"},
    [20] = {"B"},
    [21] = {"B", "B"},
    [22] = {"B", "B"},
    [23] = {"B", "B"},
    [24] = {"B", "B"},
    [25] = {"B", "B"},
    [26] = {"B", "B"},
    [27] = {"B", "B"},
    [28] = {"B", "B"},
    [29] = {"B", "B"},
    [30] = {"B", "B"},
    [31] = {"B", "B"},
    [32] = {"B", "B"},
    [33] = {"B", "B", "B"},
    [34] = {"B", "B", "B"},
    [35] = {"B"},
    [36] = {"B"},
    [37] = {"S"},
    [38] = {"B", "S"},
    [39] = {"B", "S"},
    [40] = {"B", "S"},
    [41] = {"S"},
    [42] = {"B"},
    [43] = {"B", "B"},
    [44] = {"B"},
    [45] = {"B", "B", "B"},
    [46] = {"B", "B", "B"},
    [47] = {"B", "B", "B"},
    [48] = {"B", "B", "B"},
    [49] = {},
    [50] = {"B", "B"},
    [51] = {"B", "S"},
    [52] = {"W"},
    [53] = {"B", "B"},
    [54] = {},
    [55] = {"B", "B"},
    [56] = {"B"},
    [57] = {"B"},
    [58] = {"B"},
    [59] = {"B", "S"},
    [60] = {"B"},
    [61] = {"B", "B"},
    [62] = {"B"},
    [63] = {"B", "B"},
    [64] = {"B"},
    [65] = {"B"},
    [66] = {"B"},
    [67] = {"B"},
    [68] = {"B"},
    [69] = {"B"},
    [70] = {"B"},
    [71] = {"B", "B"},
    [72] = {"B", "B", "B"},
    [73] = {"B"},
    [74] = {"B", "B"},
    [75] = {"B"},
    [76] = {"B", "B", "B"},
    [77] = {"B", "B", "B"},
    [78] = {"B", "B", "B"},
    [79] = {"B"},
    [80] = {"B", "B"},
    [81] = {"B", "B"},
    [82] = {"B"},
    [83] = {"B", "B"},
    [84] = {"B", "B"},
    [85] = {"B"},
    [86] = {"B", "B"},
    [87] = {"B", "B"},
    [88] = {"B", "B"},
    [89] = {"B"},
    [90] = {"B"},
    [91] = {"B"},
    [92] = {"B", "B"},
    [93] = {"B", "B"},
    [94] = {"B", "B"},
    [95] = {"B", "B"},
    [96] = {"B", "B"},
    [97] = {"B"},
    [98] = {"B"},
    [99] = {"B"},
    [100] = {"B", "B", "B"},
    [101] = {"B"},
    [102] = {},
    [103] = {},
    [104] = {},
    [105] = {},
}

local function fetch_BB(reader: ByteStream, ext: number): (number, number)
    local A = reader:read_byte()
    if bit32.band(1, ext) ~= 0 then
        A = bit32.bor(bit32.lshift(A, 8), reader:read_byte())
    end

    local B = reader:read_byte()
    if bit32.band(2, ext) ~= 0 then
        B = bit32.bor(bit32.lshift(B, 8), reader:read_byte())
    end

    return A, B
end

local function fetch_B(reader: ByteStream, ext: number): number
    local A = reader:read_byte()
    if bit32.band(1, ext) ~= 0 then
        A = bit32.bor(bit32.lshift(A, 8), reader:read_byte())
    end

    return A
end

local function fetch_BBB(reader: ByteStream, ext: number): (number, number, number)
    local A = reader:read_byte()
    if bit32.band(1, ext) ~= 0 then
        A = bit32.bor(bit32.lshift(A, 8), reader:read_byte())
    end

    local B = reader:read_byte()
    if bit32.band(2, ext) ~= 0 then
        B = bit32.bor(bit32.lshift(B, 8), reader:read_byte())
    end

    local C = reader:read_byte()

    return A, B, C
end

local function fetch_BS(reader: ByteStream, ext: number): (number, number)
    local A = reader:read_byte()
    if bit32.band(1, ext) ~= 0 then
        A = bit32.bor(bit32.lshift(A, 8), reader:read_byte())
    end

    local B = reader:read_byte(2)

    return A, B
end

local function fetch_BSS(reader: ByteStream, ext: number): (number, number, number)
    local A = reader:read_byte()
    if bit32.band(1, ext) ~= 0 then
        A = bit32.bor(bit32.lshift(A, 8), reader:read_byte())
    end

    local B = reader:read_byte(2)
    local C = reader:read_byte(2)

    return A, B, C
end

local function fetch_S(reader: ByteStream, ext: number): number
    return reader:read_byte(2)
end

local function fetch_W(reader: ByteStream, ext: number): number
    return reader:read_byte(3)
end

return {
    opcodes = opcodes,
    operands = operands,
    fetch_B = fetch_B,
    fetch_BB = fetch_BB,
    fetch_BBB = fetch_BBB,
    fetch_BS = fetch_BS,
    fetch_BSS = fetch_BSS,
    fetch_S = fetch_S,
    fetch_W = fetch_W
}

