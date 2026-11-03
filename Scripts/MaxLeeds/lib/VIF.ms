-- MaxLeeds - Scripts for working with R* Leeds (GTA Stories, Chinatown Wars, Manhunt 2, etc) formats in 3DSMax
-- Author: spicybung
-- Years: 2025 - 2027

-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.

-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.

-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

global MLVifState, MLVifReadUnpack
fn MLVifWord value =
(
    local result = mod (value as integer64) 4294967296L
    if result < 0 do result += 4294967296L
    if result >= 2147483648L do result -= 4294967296L
    result as integer
)
fn MLVifFloat value =
(
    local result = bit.intAsFloat value
    if result != result or abs result > 1.0e30 do throw "A VIF float is not finite or is outside the supported range."
    result
)
struct MLVifState
(
    row = #(0,0,0,0),
    column = #(0,0,0,0),
    mask = 0,
    mode = 0,
    cycle = 1,
    writes = 1,
    memory = #(),
    baseAddress = 0,
    bufferOffset = 0,
    tops = 0,
    secondBuffer = false,
    fn clearMemory = (memory = for index = 1 to 1024 collect #(undefined,undefined,undefined,undefined)),
    fn setOffset value =
    (
        bufferOffset = bit.and value 1023
        tops = baseAddress
        secondBuffer = false
    ),
    fn launch =
    (
        secondBuffer = not secondBuffer
        tops = mod (baseAddress + (if secondBuffer then bufferOffset else 0)) 1024
        clearMemory()
    ),
    fn store address cycleIndex values masked packedColor =
    (
        local target = memory[(mod address 1024) + 1]
        local phase = amin cycleIndex 3
        for component = 1 to 4 do
        (
            local action = if masked then MLBits mask (phase * 8 + (component - 1) * 2) 2 else 0
            case action of
            (
                0:
                (
                    local value = values[component]
                    if not packedColor do
                    (
                        if mode == 1 or mode == 2 do
                        (
                            if value == undefined or row[component] == undefined then value = undefined
                            else value = MLVifWord ((value as integer64) + row[component])
                        )
                        if mode == 2 or mode == 3 do row[component] = value
                    )
                    target[component] = value
                )
                1: target[component] = row[component]
                2: target[component] = column[phase + 1]
                3: ()
            )
            if target[component] != undefined do target[component] = MLVifWord target[component]
        )
        copy target
    )
)
fn MLVifReadUnpack reader word state =
(
    if state.writes < 1 or state.writes > 256 or state.cycle < 0 or state.cycle > 256 do throw "Invalid VIF cycle state."
    if state.mode < 0 or state.mode > 3 do throw "Invalid VIF arithmetic mode."
    local format = bit.and (bit.shift word -24) 15
    local count = MLBits word 16 8
    if count == 0 do count = 256
    local filling = state.writes > state.cycle
    local components = ((format / 4) as integer) + 1
    local width = bit.and format 3
    if width == 3 and format != 15 do throw "Invalid VIF UNPACK format."
    local unsigned = (bit.and word 0x4000) != 0
    local masked = (bit.and word 0x10000000) != 0
    local address = bit.and word 1023
    if (bit.and word 0x8000) != 0 do address += state.tops
    local output = #()
    for index = 0 to count - 1 do
    (
        local phase = mod index state.writes
        local values = #()
        if filling and phase >= state.cycle then
            values = #(undefined,undefined,undefined,undefined)
        else if format == 15 then
        (
            local packed = reader.short()
            values = #((MLBits packed 0 5) * 8,(MLBits packed 5 5) * 8,(MLBits packed 10 5) * 8,(MLBits packed 15 1) * 128)
        )
        else
        (
            for component = 1 to components do
                append values (case width of (0: MLVifWord (reader.long()); 1: (if unsigned then reader.short() else reader.signedShort()); 2: (if unsigned then reader.byte() else reader.signedByte())))
            if components == 1 then values = #(values[1],values[1],values[1],values[1])
            else if components == 2 then values = #(values[1],values[2],values[1],values[2])
            else if components == 3 do append values undefined
        )
        local destination = if filling then address + index else address + ((index / state.writes) as integer) * state.cycle + phase
        append output (state.store (mod destination 1024) phase values masked (format == 15))
    )
    reader.seek (MLAlign (reader.tell()) 4)
    output
)
fn MLVifRequire values count =
(
    for index = 1 to count do if values[index] == undefined do throw "A required VIF component is indeterminate. Use explicit row/column masks for fill cycles; protected components need a known preceding write."
    values
)
