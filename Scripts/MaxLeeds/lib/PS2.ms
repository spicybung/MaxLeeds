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

global MLReadPs2Geometry, MLCommitPs2Strip

fn MLCommitPs2Strip part vertices uv colors normals weights =
(
    local count = vertices.count
    if count == 0 do return 0
    if count < 3 do throw "The PS2 mesh contains a triangle strip with fewer than three vertices."
    if uv.count != 0 and uv.count != count do throw "A PS2 strip has an incomplete UV stream."
    if colors.count != 0 and colors.count != count do throw "A PS2 strip has an incomplete color stream."
    if normals.count != 0 and normals.count != count do throw "A PS2 strip has an incomplete normal stream."
    if weights.count != 0 and weights.count != count do throw "A PS2 strip has an incomplete skin weight stream."
    if part.vertices.count > 0 do
    (
        if (part.uv.count > 0) != (uv.count > 0) do throw "The PS2 geometry mixes textured and untextured strips."
        if (part.colors.count > 0) != (colors.count > 0) do throw "The PS2 geometry mixes colored and uncolored strips."
        if (part.normals.count > 0) != (normals.count > 0) do throw "The PS2 geometry mixes strips with and without normals."
        if (part.weights.count > 0) != (weights.count > 0) do throw "The PS2 geometry mixes skinned and unskinned strips."
    )
    join part.faces (MLStripFaces count part.vertices.count)
    join part.vertices vertices
    join part.uv uv
    join part.colors colors
    join part.normals normals
    join part.weights weights
    count
)

fn MLReadPs2Geometry reader geometry atomicName framePointer mh2:false mobile:false =
(
    local positionFactor = if mobile then 0.00003051820313464149 else (1.0 / 32768.0)
    local normalDivisor = if mobile or mh2 then 128.0 else 127.0
    local descriptorBase = if mh2 then 0x50 else 0x40
    local globalHeader = geometry + 0x20
    reader.check globalHeader 0x40
    local packed = reader.atLong (globalHeader + 0x10)
    local partCount = MLBits packed 20 12
    local size = bit.and packed 0xFFFFF
    local firstPacket = reader.atShort (globalHeader + 0x1A)
    if partCount < 1 or partCount > 4095 or size < descriptorBase + partCount * 0x30 or firstPacket < descriptorBase + partCount * 0x30 do throw "The PS2 geometry header is invalid."
    reader.check globalHeader size
    local scale = reader.atPoint (globalHeader + 0x28)
    local position = reader.atPoint (globalHeader + 0x34)
    local parts = #()
    local cycleLength = 1
    local writeLength = 1
    local rowValues = #(0,0,0,0)
    local mask = 0
    local mode = 0
    local vifState = MLVifState()
    vifState.clearMemory()
    for partIndex = 0 to partCount - 1 do
    (
        local descriptor = globalHeader + descriptorBase + partIndex * 0x30
        reader.check descriptor 0x30
        local relative = reader.atLong (descriptor + 0x1C)
        local materialID = reader.atShort (descriptor + 0x22) + 1
        local uvScale = [reader.atFloat (descriptor + 16), reader.atFloat (descriptor + 20), 1]
        local cursor = globalHeader + firstPacket + relative
        local partEnd = globalHeader + size
        if partIndex + 1 < partCount do partEnd = globalHeader + firstPacket + reader.atLong (descriptor + 0x30 + 0x1C)
        if cursor < globalHeader or cursor >= partEnd or partEnd > globalHeader + size do throw "The PS2 mesh packet range is invalid."
        local part = MLPart name:(atomicName + "_part" + (partIndex + 1) as string) materialID:materialID framePointer:framePointer
        while cursor + 16 <= partEnd do
        (
            local tag = reader.atLong cursor
            if (bit.and tag 0x70000000) != 0x60000000 do throw "The PS2 mesh contains an unknown DMA packet."
            local packetEnd = cursor + 16 + (bit.and tag 65535) * 16
            if packetEnd > partEnd do throw "The PS2 mesh DMA packet is truncated."
            local resourceEnd = reader.length
            reader.length = packetEnd
            reader.seek (cursor + 16)
            local vertices = #()
            local uv = #()
            local colors = #()
            local normals = #()
            local weights = #()
            try
            (
            while reader.tell() + 4 <= packetEnd do
            (
                local word = reader.long()
                local command = MLBits word 24 7
                local unpackCommand = if (bit.and command 0x60) == 0x60 then (bit.and command 0x6F) else command
                local count = MLBits word 16 8
                if count == 0 do count = 256
                local outputCount = count
                local positionStream = vertices.count == 0
                if (bit.and command 0x60) == 0x60 then
                (
                    vifState.row = rowValues
                    vifState.mask = mask; vifState.mode = mode
                    vifState.cycle = cycleLength; vifState.writes = writeLength
                    local vectors = MLVifReadUnpack reader word vifState
                    rowValues = vifState.row
                    for vector in vectors do
                    (
                        case unpackCommand of
                        (
                            0x69:
                            (
                                MLVifRequire vector 3
                                append vertices [vector[1] * scale.x * positionFactor + position.x,vector[2] * scale.y * positionFactor + position.y,vector[3] * scale.z * positionFactor + position.z]
                            )
                            0x68:
                            (
                                MLVifRequire vector 3
                                local value = [MLVifFloat vector[1],MLVifFloat vector[2],MLVifFloat vector[3]]
                                if positionStream then append vertices [value.x * scale.x + position.x,value.y * scale.y + position.y,value.z * scale.z + position.z]
                                else append normals value
                            )
                            0x66: (MLVifRequire vector 2; append uv [vector[1] * uvScale.x / (if mh2 then 128.0 else 127.5),1.0 - vector[2] * uvScale.y / (if mh2 then 128.0 else 127.5),0])
                            0x65: (MLVifRequire vector 2; append uv [vector[1] * uvScale.x / 32767.5,1.0 - vector[2] * uvScale.y / 32767.5,0])
                            0x64: (MLVifRequire vector 2; append uv [(MLVifFloat vector[1]) * uvScale.x,1.0 - (MLVifFloat vector[2]) * uvScale.y,0])
                            0x6A: (MLVifRequire vector 3; append normals ([vector[1],vector[2],vector[3]] / normalDivisor))
                            0x6E: (MLVifRequire vector 4; append colors (color vector[1] vector[2] vector[3] (if mh2 then amin 255 (floor (vector[4] * 255.0 / 128.0)) else vector[4])))
                            0x6F: (MLVifRequire vector 4; append colors (color (vector[1] * 255.0 / 248.0) (vector[2] * 255.0 / 248.0) (vector[3] * 255.0 / 248.0) (vector[4] * 255.0 / 128.0)))
                            0x6C:
                            (
                                if vertices.count > 0 and outputCount == vertices.count and (mh2 or (bit.and word 1023) == 127) do
                                (
                                    MLVifRequire vector 4
                                    local influences = #()
                                    local total = 0.0
                                    for value in vector do
                                    (
                                        local weight = bit.intAsFloat (bit.and value (bit.not 255))
                                        local offset = bit.and value 255
                                        if weight > 0 do
                                        (
                                            if (mod offset 4) != 0 or weight > 1.01 do throw "Invalid arithmetic VIF skin value."
                                            append influences #(((offset / 4) as integer) + 1,weight)
                                            total += weight
                                        )
                                    )
                                    if total < 0.01 or total > 1.05 do throw "Invalid arithmetic VIF skin weights."
                                    append weights influences
                                )
                            )
                        )
                    )
                )
                else
                case unpackCommand of
                (
                    0x00: ()
                    0x01:
                    (
                        cycleLength = bit.and word 255
                        writeLength = MLBits word 8 8
                        if writeLength == 0 do writeLength = 256
                    )
                    0x02: (vifState.setOffset word)
                    0x03: (vifState.baseAddress = bit.and word 1023)
                    0x04: ()
                    0x05: (mode = bit.and word 3)
                    0x06: ()
                    0x07: ()
                    0x10: ()
                    0x11: ()
                    0x13: ()
                    0x14:
                    (
                        vifState.launch()
                        MLCommitPs2Strip part vertices uv colors normals weights
                        vertices = #()
                        uv = #()
                        colors = #()
                        normals = #()
                        weights = #()
                    )
                    0x15:
                    (
                        vifState.launch()
                        MLCommitPs2Strip part vertices uv colors normals weights
                        vertices = #()
                        uv = #()
                        colors = #()
                        normals = #()
                        weights = #()
                    )
                    0x17:
                    (
                        vifState.launch()
                        MLCommitPs2Strip part vertices uv colors normals weights
                        vertices = #(); uv = #(); colors = #(); normals = #(); weights = #()
                    )
                    0x20: (mask = reader.long())
                    0x30: (rowValues = #(reader.long(),reader.long(),reader.long(),reader.long()))
                    0x31: (vifState.column = #(reader.long(),reader.long(),reader.long(),reader.long()))
                    default: throw ("Unknown PS2 VIF vertex command: " + command as string)
                )
                if reader.tell() > packetEnd do throw "A PS2 vertex attribute extends past its DMA packet."
            )
            )
            catch (reader.length = resourceEnd; throw())
            reader.length = resourceEnd
            MLCommitPs2Strip part vertices uv colors normals weights
            cursor = packetEnd
        )
        if part.vertices.count == 0 do throw "The PS2 geometry part has no vertices."
        append parts part
    )
    parts
)
