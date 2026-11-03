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

global MLReadManhuntWorld
fn MLReadManhuntWorld path =
(
    local decoded = MLDecodeResource path #("DLRW")
    local reader = MLReader()
    try
    (
        MLOpenResource reader decoded[1] "DLRW"
        reader.check 80 16
        local model = MLModel name:(getFilenameFile path) game:"MH2" sourcePath:path platform:""
        -- The world material table uses the same 12-byte records as model objects.
        model.materials = MLMhMaterials reader 80
        local cursor = 96
        local conversion = rotateXMatrix 90
        while cursor + 80 <= reader.length do
        (
            local platform = ""
            local size = 0
            local parts = undefined
            if (reader.text (cursor + 64) 4) == "D2SP" then
            (
                -- A recognized signature is authoritative: malformed geometry must fail visibly.
                platform = "PS2"
                size = bit.and (reader.atLong (cursor + 16)) 0xFFFFF
                parts = MLReadPs2Geometry reader (cursor - 32) (model.name + "_" + cursor as string) 0 mh2:true
            )
            else
            (
                local flags = reader.atLong (cursor + 4)
                local candidateSize = reader.atLong cursor
                local strips = reader.atLong (cursor + 8)
                local buffer = reader.atLong (cursor + 64)
                if (bit.and flags 0x180) == 0x100 and (bit.and flags (bit.not 0x1DFFF)) == 0 and strips > 0 and strips <= 4096 and candidateSize >= 80 + strips * 32 and candidateSize <= reader.length - cursor and buffer >= 80 + strips * 32 and buffer < candidateSize do
                (
                    platform = "PSP"
                    size = candidateSize
                    parts = MLMhReadPspGeometry reader (cursor - 16) (model.name + "_" + cursor as string) 0 world:true
                )
            )
            if parts != undefined then
            (
                if model.platform == "" then model.platform = platform
                else if model.platform != platform do throw "The Manhunt world mixes platforms."
                for part in parts do
                (
                    if part.materialID < 1 or part.materialID > model.materials.count do throw "A world mesh refers to a missing material."
                    if part.weights.count > 0 do throw "A Manhunt world mesh unexpectedly contains skin weights."
                    part.atomicPointer = cursor
                    for index = 1 to part.vertices.count do part.vertices[index] *= conversion
                    for index = 1 to part.normals.count do part.normals[index] = normalize (part.normals[index] * conversion)
                    append model.parts part
                )
                cursor = MLAlign (cursor + size) 4
            )
            else cursor += 4
        )
        if model.parts.count == 0 do throw "No supported PS2 / PSP geometry was found in the Manhunt world."
        reader.closeFile()
        if decoded[2] do deleteFile decoded[1]
        MLMergeModelParts model
        model
    )
    catch
    (
        reader.closeFile()
        if decoded[2] and doesFileExist decoded[1] do deleteFile decoded[1]
        throw()
    )
)
