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

global MLReadWorldblock
fn MLReadWorldblock path =
(
    local reader = MLReader()
    local created = #()
    try
    (
        reader.openFile path
        reader.check 0 0x28
        reader.seek 0x14
        local origin = [reader.signedLong(),reader.signedLong(),reader.signedLong()] / 4096.0
        local sector = 0x28
        local meshPointers = #()
        for sectorIndex = 1 to 4 do
        (
            reader.check sector 12
            local instanceCount = reader.atShort (sector + 2)
            local shadowCount = reader.atShort (sector + 4)
            local levelCount = reader.atShort (sector + 6)
            local lightCount = reader.atShort (sector + 8)
            local textureCount = reader.atShort (sector + 10)
            if instanceCount > 32767 or shadowCount > 32767 or levelCount > 32767 or lightCount > 32767 or textureCount > 32767 do throw "Worldblock counts are invalid."
            local instances = sector + 12 + levelCount * 16
            reader.check instances (instanceCount * 16 + shadowCount * 20 + lightCount * 20 + textureCount * 2)
            for index = 0 to instanceCount - 1 do
            (
                local pointer = reader.atLong (instances + index * 16 + 8)
                if pointer != 0 and (findItem meshPointers pointer) == 0 do append meshPointers pointer
            )
            local lights = instances + instanceCount * 16 + shadowCount * 20
            for index = 0 to lightCount - 1 do
            (
                local row = lights + index * 20
                reader.seek row
                local position = [reader.signedLong(),reader.signedLong(),reader.signedLong()] / 4096.0
                local radius = reader.short() / 4096.0
                local id = reader.byte()
                reader.seek (row + 16)
                local lightColor = color (reader.byte()) (reader.byte()) (reader.byte())
                local node = omniLight name:(getFilenameFile path + "_light" + index as string) pos:position rgb:lightColor
                append created node
                setUserProp node "MaxLeedsLightID" id
                setUserProp node "MaxLeedsLightRadius" radius
            )
            sector = instances + instanceCount * 16 + shadowCount * 20 + lightCount * 20 + textureCount * 2
        )
        for pointer in meshPointers do
        (
            reader.check pointer 48
            reader.seek (pointer + 5)
            local materialCount = reader.byte()
            local vertexCount = reader.short()
            local uvOffset = reader.atFloat (pointer + 40)
            local scale = reader.atFloat (pointer + 44)
            if (abs scale) < 1.0e-12 or vertexCount < 3 do throw "A worldblock model has invalid scale or vertex counts."
            reader.check (pointer + 48) (vertexCount * 16 + materialCount * 12)
            local allVertices = #()
            local allNormals = #()
            local allUV = #()
            reader.seek (pointer + 48)
            for index = 1 to vertexCount do
            (
                append allVertices ([reader.signedShort(),reader.signedShort(),reader.signedShort()] / scale + origin)
                append allNormals ([reader.signedShort(),reader.signedShort(),reader.signedShort()] / 32768.0)
                append allUV [reader.signedShort() / 2048.0 + uvOffset * 2, 1.0 - reader.signedShort() / 2048.0, 0]
            )
            local first = 1
            for materialIndex = 0 to materialCount - 1 do
            (
                local row = pointer + 48 + vertexCount * 16 + materialIndex * 12
                local textureID = reader.atShort row
                local count = reader.atShort (row + 2)
                reader.seek (row + 4)
                local flags = reader.byte()
                if first + count - 1 > vertexCount or count < 3 do throw "The worldblock mesh ranges are invalid."
                local part = MLPart name:(getFilenameFile path + "_mesh" + pointer as string + "_part" + materialIndex as string)
                local uvMultiplier = if flags == 4 then 3.0 else 2.0
                for index = first to first + count - 1 do
                (
                    append part.vertices allVertices[index]
                    append part.normals allNormals[index]
                    append part.uv (allUV[index] + [uvOffset * uvMultiplier,0,0])
                )
                part.faces = MLStripFaces count 0
                local node = MLCreateMesh part #(MLMaterial name:("texture" + textureID as string))
                append created node
                setUserProp node "MaxLeedsTextureID" textureID
                setUserProp node "MaxLeedsWorldblockMesh" pointer
                first += count
            )
            if first - 1 != vertexCount do throw "Worldblock material ranges do not cover the vertex buffer."
        )
        if created.count == 0 do throw "No worldblock geometry or lights were found."
        reader.closeFile()
        select created
        created.count
    )
    catch
    (
        local reason = getCurrentException()
        reader.closeFile()
        for node in created where isValidNode node do delete node
        throw()
    )
)
