-- MaxLeeds - spicybung
-- GPL-3.0-or-later

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

fn MLReadPs2Geometry reader geometry atomicName framePointer =
(
    local globalHeader = geometry + 0x20
    reader.check globalHeader 0x40
    local packed = reader.atLong (globalHeader + 0x10)
    local partCount = MLBits packed 20 12
    local size = bit.and packed 0xFFFFF
    local firstPacket = reader.atShort (globalHeader + 0x1A)
    if partCount < 1 or partCount > 512 or size < 0x40 or firstPacket < 0x40 do throw "The PS2 geometry header is invalid."
    reader.check globalHeader size
    local scale = reader.atPoint (globalHeader + 0x28)
    local position = reader.atPoint (globalHeader + 0x34)
    local parts = #()
    for partIndex = 0 to partCount - 1 do
    (
        local descriptor = globalHeader + 0x40 + partIndex * 0x30
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
            reader.seek (cursor + 16)
            local vertices = #()
            local uv = #()
            local colors = #()
            local normals = #()
            local weights = #()
            while reader.tell() + 4 <= packetEnd do
            (
                local word = reader.long()
                local command = MLBits word 24 7
                local count = MLBits word 16 8
                if count == 0 do count = 256
                case command of
                (
                    0x00: ()
                    0x01:
                    (
                        local cycleLength = bit.and word 255
                        local writeLength = MLBits word 8 8
                        if cycleLength != writeLength do throw "The PS2 vertex cycle is not a contiguous stream."
                    )
                    0x02: ()
                    0x03: ()
                    0x04: ()
                    0x05: ()
                    0x06: ()
                    0x07: ()
                    0x10: ()
                    0x11: ()
                    0x13: ()
                    0x14:
                    (
                        MLCommitPs2Strip part vertices uv colors normals weights
                        vertices = #()
                        uv = #()
                        colors = #()
                        normals = #()
                        weights = #()
                    )
                    0x15:
                    (
                        MLCommitPs2Strip part vertices uv colors normals weights
                        vertices = #()
                        uv = #()
                        colors = #()
                        normals = #()
                        weights = #()
                    )
                    0x17: ()
                    0x20: (reader.check (reader.tell()) 4; reader.seek (reader.tell() + 4))
                    0x30: (reader.check (reader.tell()) 16; reader.seek (reader.tell() + 16))
                    0x31: (reader.check (reader.tell()) 16; reader.seek (reader.tell() + 16))
                    0x79:
                    (
                        if vertices.count != 0 do throw "The PS2 geometry starts another vertex strip before completing the previous one."
                        reader.check (reader.tell()) (count * 6)
                        for index = 1 to count do
                        (
                            local raw = [reader.signedShort(), reader.signedShort(), reader.signedShort()]
                            append vertices [raw.x * scale.x / 32768.0 + position.x, raw.y * scale.y / 32768.0 + position.y, raw.z * scale.z / 32768.0 + position.z]
                        )
                        reader.seek (MLAlign (reader.tell()) 4)
                    )
                    0x76:
                    (
                        reader.check (reader.tell()) (count * 2)
                        for index = 1 to count do append uv [reader.byte() / 127.5 * uvScale.x, 1.0 - reader.byte() / 127.5 * uvScale.y, 0]
                        reader.seek (MLAlign (reader.tell()) 4)
                    )
                    0x6F:
                    (
                        reader.check (reader.tell()) (count * 2)
                        for index = 1 to count do
                        (
                            local packedColor = reader.short()
                            append colors (color ((MLBits packedColor 0 5) * 255 / 31) ((MLBits packedColor 5 5) * 255 / 31) ((MLBits packedColor 10 5) * 255 / 31) (if (bit.and packedColor 0x8000) != 0 then 255 else 0))
                        )
                        reader.seek (MLAlign (reader.tell()) 4)
                    )
                    0x6A:
                    (
                        reader.check (reader.tell()) (count * 3)
                        for index = 1 to count do append normals ([reader.signedByte(), reader.signedByte(), reader.signedByte()] / 127.0)
                        reader.seek (MLAlign (reader.tell()) 4)
                    )
                    0x6C:
                    (
                        reader.check (reader.tell()) (count * 16)
                        local address = bit.and word 0x3FF
                        if vertices.count > 0 and count == vertices.count and address == 0x7F then
                        (
                            for vertexIndex = 1 to count do
                            (
                                local influences = #()
                                local total = 0.0
                                for channel = 1 to 4 do
                                (
                                    local value = reader.long()
                                    local weight = bit.intAsFloat (bit.and value (bit.not 255))
                                    local boneOffset = bit.and value 255
                                    if weight > 0.0 do
                                    (
                                        if (mod boneOffset 4) != 0 do throw "The PS2 character contains an invalid skin bone offset."
                                        if weight > 1.01 do throw "The PS2 character contains an invalid skin weight."
                                        append influences #(((boneOffset / 4) as integer) + 1, weight)
                                        total += weight
                                    )
                                )
                                if total < 0.01 or total > 1.05 do throw "The PS2 character contains invalid vertex skin weights."
                                append weights influences
                            )
                        )
                        else reader.seek (reader.tell() + count * 16)
                    )
                    default: throw ("Unknown PS2 VIF vertex command: " + command as string)
                )
                if reader.tell() > packetEnd do throw "A PS2 vertex attribute extends past its DMA packet."
            )
            MLCommitPs2Strip part vertices uv colors normals weights
            cursor = packetEnd
        )
        if part.vertices.count == 0 do throw "The PS2 geometry part has no vertices."
        append parts part
    )
    parts
)
