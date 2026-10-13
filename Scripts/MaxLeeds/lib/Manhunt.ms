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

global MLMhFrames, MLReadManhunt
fn MLMhFrames reader pointer frames visited conversion =
(
    if pointer == 0 do return frames
    if (findItem visited pointer) != 0 do throw "The Manhunt bone hierarchy contains a cycle."
    append visited pointer
    if visited.count > 2048 do throw "Too many Manhunt bones."
    reader.check pointer 192
    local sourceMatrix = reader.matrix (pointer + 128)
    local world = inverse conversion * sourceMatrix * conversion
    local frame = MLFrame pointer:pointer parentPointer:(reader.atLong (pointer + 8)) name:(reader.text (pointer + 24) 40) worldMatrix:world
    append frames frame
    local child = reader.atLong (pointer + 16)
    local sibling = reader.atLong (pointer + 4)
    if child != 0 do MLMhFrames reader child frames visited conversion
    if sibling != 0 do MLMhFrames reader sibling frames visited conversion
    frames
)
fn MLReadManhunt path =
(
    local reader = MLReader()
    local model = MLModel game:"MH2" platform:"PC" sourcePath:path
    try
    (
        reader.openFile path
        if (reader.text 0 4) != "PMLC" do throw "This native build reads uncompressed retail PC PMLC models."
        local firstEntry = reader.atLong 0x20
        reader.check firstEntry 16
        local entry = reader.atLong (firstEntry + 8)
        reader.check entry 28
        local rootBone = reader.atLong entry
        local binding = reader.atLong (entry + 8)
        local objectInfo = reader.atLong (entry + 20)
        local lastInfo = reader.atLong (entry + 24)
        local conversion = rotateXMatrix 90
        if rootBone != 0 do model.frames = MLMhFrames reader rootBone #() #() conversion
        local palette = #()
        if binding != 0 do
        (
            reader.check binding 24
            local count = reader.atLong binding
            local table = reader.atLong (binding + 12)
            if count < 1 or count > 2048 do throw "The Manhunt bone palette is invalid."
            reader.check table (count * 8)
            for index = 0 to count - 1 do
            (
                local boneID = reader.atShort (table + index * 8)
                local bonePointer = reader.atLong (table + index * 8 + 4)
                local frameIndex = 0
                for candidate = 1 to model.frames.count where model.frames[candidate].pointer == bonePointer do
                (
                    frameIndex = candidate
                    model.frames[candidate].boneID = boneID
                )
                append palette frameIndex
            )
        )
        local visited = #()
        while objectInfo != 0 do
        (
            if (findItem visited objectInfo) != 0 do throw "The Manhunt mesh list contains a cycle."
            append visited objectInfo
            if visited.count > 2048 do throw "Too many Manhunt mesh parts."
            reader.check objectInfo 28
            local header = reader.atLong (objectInfo + 12)
            local parentBone = reader.atLong (objectInfo + 8)
            reader.check header 180
            local materialTable = reader.atLong header
            local materialCount = reader.atLong (header + 4)
            local materialIDs = reader.atLong (header + 0x2C)
            local faceIndices = reader.atLong (header + 0x30)
            local vertexCount = reader.atLong (header + 0x50)
            local stride = reader.atLong (header + 0x60)
            local vertexType = reader.atLong (header + 0x90)
            local expectedStride = case vertexType of (0x52: 24; 0x152: 32; 0x115E: 52; default: 0)
            if expectedStride == 0 or stride != expectedStride do throw "This Manhunt vertex layout has not been ported."
            if vertexCount < 1 or vertexCount > 65535 or faceIndices < 3 or (mod faceIndices 3) != 0 or materialIDs > 2048 or materialCount > 2048 do throw "The Manhunt mesh counts are invalid."
            local facesPointer = header + 180 + materialIDs * 44
            local verticesPointer = facesPointer + faceIndices * 2
            reader.check facesPointer (faceIndices * 2 + vertexCount * stride)
            local part = MLPart name:(getFilenameFile path + "_part" + visited.count as string) framePointer:parentBone
            local faceCount = faceIndices / 3
            reader.seek facesPointer
            for index = 1 to faceCount do
            (
                local face = [reader.short() + 1,reader.short() + 1,reader.short() + 1]
                if face.x > vertexCount or face.y > vertexCount or face.z > vertexCount do throw "A Manhunt triangle refers to a missing vertex."
                append part.faces face
                append part.faceIDs (model.materials.count + 1)
            )
            for materialIndex = 0 to materialIDs - 1 do
            (
                local row = header + 180 + materialIndex * 44
                local count = reader.atShort (row + 24)
                local slot = reader.atShort (row + 26)
                local first = reader.atShort (row + 28)
                if (mod count 3) != 0 or (mod first 3) != 0 or first + count > faceIndices or slot >= materialCount do throw "The Manhunt material face ranges are invalid."
                for face = first / 3 + 1 to (first + count) / 3 do part.faceIDs[face] = model.materials.count + slot + 1
            )
            for index = 0 to vertexCount - 1 do
            (
                local vertex = verticesPointer + index * stride
                append part.vertices ((reader.atPoint vertex) * conversion)
                local normalOffset = if vertexType == 0x115E then 32 else 12
                reader.seek (vertex + normalOffset)
                local normal = [reader.signedShort(),reader.signedShort(),reader.signedShort()] / 32768.0
                append part.normals (normalize (normal * conversion))
                local colorOffset = if vertexType == 0x115E then 40 else 20
                reader.seek (vertex + colorOffset)
                local blue = reader.byte()
                local green = reader.byte()
                local red = reader.byte()
                local alpha = reader.byte()
                append part.colors (color red green blue alpha)
                if vertexType != 0x52 do
                (
                    local offset = if vertexType == 0x115E then 44 else 24
                    append part.uv [reader.atFloat (vertex + offset), 1.0 - reader.atFloat (vertex + offset + 4), 0]
                )
                if vertexType == 0x115E do
                (
                    if palette.count == 0 do throw "A skinned Manhunt mesh has no bone binding table."
                    local weights = #()
                    reader.seek (vertex + 12)
                    for component = 1 to 4 do append weights (reader.float())
                    reader.seek (vertex + 28)
                    local influences = #()
                    for component = 1 to 4 do
                    (
                        local boneIndex = reader.byte() + 1
                        if weights[component] > 0 do
                        (
                            if boneIndex > palette.count or palette[boneIndex] == 0 do throw "A Manhunt skin weight refers to a missing bone."
                            append influences #(palette[boneIndex], weights[component])
                        )
                    )
                    append part.weights influences
                )
            )
            reader.check materialTable (materialCount * 12)
            for index = 0 to materialCount - 1 do
            (
                local row = materialTable + index * 12
                local namePointer = reader.atLong row
                local name = if namePointer != 0 then reader.text namePointer (amin 128 (reader.length - namePointer)) else "default"
                reader.seek (row + 5)
                append model.materials (MLMaterial name:name rgba:(color (reader.byte()) (reader.byte()) (reader.byte()) (reader.byte())))
            )
            append model.parts part
            if objectInfo == lastInfo then objectInfo = 0 else objectInfo = reader.atLong objectInfo
        )
        if model.parts.count == 0 do throw "No retail PC Manhunt mesh was found."
        reader.closeFile()
        model
    )
    catch
    (
        local reason = getCurrentException()
        reader.closeFile()
        throw()
    )
)
