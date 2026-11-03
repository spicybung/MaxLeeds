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

global MLDffChunk, MLReadMobileDff
struct MLDffChunk (kind, version, start, data, finish, children = #())
fn MLDffReadChunk reader offset expected depth =
(
    if depth > 64 do throw "The DFF chunk hierarchy is too deep."
    reader.check offset 12
    local kind = reader.atLong offset
    local size = reader.atLong (offset + 4)
    local version = reader.atLong (offset + 8)
    if expected != 0 and kind != expected do throw "The Mobile DFF contains an unexpected chunk."
    local start = offset + 12
    local cursor = start
    local children = #()
    local sequence = #()
    if (findItem #(0x10,0xE,0x1A,0x14,8,7,6) kind) > 0 then
    (
        local structure = MLDffReadChunk reader cursor 1 (depth + 1)
        append children structure
        cursor = structure.finish
        if structure.finish - structure.data < 4 do throw "A DFF structure is truncated."
        local count = reader.atLong structure.data
        case kind of
        (
            0x10:
            (
                if count > 2048 do throw "Too many DFF atomics."
                local frames = MLDffReadChunk reader cursor 0xE (depth + 1)
                append children frames; cursor = frames.finish
                if cursor <= reader.length - 4 and (reader.atLong cursor) == 0x1A do
                (
                    local geometries = MLDffReadChunk reader cursor 0x1A (depth + 1)
                    append children geometries; cursor = geometries.finish
                )
                for index = 1 to count do append sequence 0x14
                append sequence 3
            )
            0xE:
            (
                if count > 2048 or structure.finish - structure.data != 4 + count * 56 do throw "Invalid DFF frame table."
                for index = 1 to count do append sequence 3
            )
            0x1A:
            (
                if count > 2048 do throw "Too many DFF geometries."
                for index = 1 to count do append sequence 0xF
            )
            0x14:
            (
                if structure.finish - structure.data < 16 do throw "Invalid DFF atomic."
                if cursor <= reader.length - 4 and (reader.atLong cursor) == 0xF do append sequence 0xF
                append sequence 3
            )
            8:
            (
                if count > 4096 or structure.finish - structure.data != 4 + count * 4 do throw "Invalid DFF material table."
                for index = 0 to count - 1 do
                (
                    reader.seek (structure.data + 4 + index * 4)
                    local reference = reader.signedLong()
                    if reference == -1 then append sequence 7
                    else if reference < 0 or reference >= index do throw "Invalid shared DFF material."
                )
            )
            7:
            (
                if structure.finish - structure.data < 16 do throw "Invalid DFF material."
                if (reader.atLong (structure.data + 12)) != 0 do append sequence 6
                append sequence 3
            )
            6: sequence = #(2,2,3)
        )
        for childKind in sequence do
        (
            local child = MLDffReadChunk reader cursor childKind (depth + 1)
            append children child
            cursor = child.finish
        )
    )
    else if kind == 0xF and version == 0xF00D then
    (
        reader.check start 64
        local geometrySize = bit.and (reader.atLong (start + 16)) 0xFFFFF
        if geometrySize < 64 do throw "Invalid Leeds Mobile geometry size."
        reader.check start geometrySize
        cursor = start + geometrySize
        for childKind in #(8,3) do
        (
            local child = MLDffReadChunk reader cursor childKind (depth + 1)
            append children child; cursor = child.finish
        )
    )
    else if kind == 3 or kind == 0xF then
    (
        reader.check start size
        local finish = start + size
        while cursor < finish do
        (
            local child = MLDffReadChunk reader cursor 0 (depth + 1)
            append children child; cursor = child.finish
        )
        if kind == 0xF and cursor != finish do throw "Invalid standard DFF geometry extent."
    )
    else
    (
        local actualSize = (size as integer64) + (if kind == 0x120 then 4 else 0)
        reader.check start actualSize
        cursor = start + actualSize
    )
    MLDffChunk kind:kind version:version start:offset data:start finish:cursor children:children
)
fn MLDffFind chunk kind =
(
    for child in chunk.children where child.kind == kind do return child
    undefined
)
fn MLDffMaterials reader geometry =
(
    local list = MLDffFind geometry 8
    if list == undefined do throw "DFF geometry has no material list."
    local structure = MLDffFind list 1
    local count = reader.atLong structure.data
    local entries = for child in list.children where child.kind == 7 collect child
    local materials = #()
    local next = 1
    for index = 0 to count - 1 do
    (
        reader.seek (structure.data + 4 + index * 4)
        local reference = reader.signedLong()
        if reference >= 0 then append materials materials[reference + 1]
        else
        (
            local material = entries[next]; next += 1
            local data = MLDffFind material 1
            reader.seek (data.data + 4)
            local rgba = color (reader.byte()) (reader.byte()) (reader.byte()) (reader.byte())
            local name = "material_" + (index + 1) as string
            local texture = MLDffFind material 6
            if texture != undefined do
            (
                local textChunk = MLDffFind texture 2
                name = reader.text textChunk.data (textChunk.finish - textChunk.data)
            )
            append materials (MLMaterial name:name rgba:rgba)
        )
    )
    materials
)
fn MLDffFrames reader list =
(
    local structure = MLDffFind list 1
    local count = reader.atLong structure.data
    local extensions = for child in list.children where child.kind == 3 collect child
    local frames = #()
    local skinMap = #()
    for index = 1 to count do
    (
        reader.seek (structure.data + 4 + (index - 1) * 56)
        local localTransform = matrix3 (reader.point()) (reader.point()) (reader.point()) (reader.point())
        local parent = reader.signedLong()
        if parent < -1 or parent >= count or parent == index - 1 do throw "Invalid DFF frame parent."
        local frame = MLFrame pointer:index parentPointer:(parent + 1) name:("frame_" + index as string) localMatrix:localTransform
        for plugin in extensions[index].children do
        (
            if plugin.kind == 0x253F2FE do frame.name = reader.text plugin.data (plugin.finish - plugin.data)
            if plugin.kind == 0x11E do
            (
                if plugin.finish - plugin.data < 12 do throw "Truncated DFF HAnim plugin."
                reader.seek (plugin.data + 4); frame.boneID = reader.signedLong()
                local bones = reader.atLong (plugin.data + 8)
                if bones > 0 do
                (
                    if bones > 256 or plugin.finish - plugin.data != 20 + bones * 12 do throw "Invalid DFF HAnim palette."
                    for bone = 0 to bones - 1 do
                    (
                        local id = reader.atLong (plugin.data + 20 + bone * 12)
                        local slot = reader.atLong (plugin.data + 24 + bone * 12)
                        if slot > 255 do throw "DFF skin index exceeds its byte range."
                        append skinMap #(id,slot + 1)
                    )
                )
            )
        )
        append frames frame
    )
    for frame in frames do
    (
        local world = frame.localMatrix
        local parent = frame.parentPointer
        local visited = #(frame.pointer)
        while parent != 0 do
        (
            if (findItem visited parent) != 0 do throw "DFF frame hierarchy contains a cycle."
            append visited parent
            world = world * frames[parent].localMatrix
            parent = frames[parent].parentPointer
        )
        frame.worldMatrix = world
    )
    local palette = for index = 1 to 256 collect 0
    for item in skinMap do
    (
        local matches = for frame in frames where frame.boneID == item[1] collect frame.pointer
        if matches.count != 1 do throw "DFF skin bone does not resolve to one frame."
        if palette[item[2]] != 0 and palette[item[2]] != matches[1] do throw "Conflicting DFF skin palette entries."
        palette[item[2]] = matches[1]
    )
    #(frames,palette)
)
fn MLDffStandardGeometry reader geometry name framePointer =
(
    local data = MLDffFind geometry 1
    if data == undefined do throw "DFF geometry has no structure."
    local originalEnd = reader.length
    local part = MLPart name:name framePointer:framePointer
    try
    (
        reader.length = data.finish
        reader.seek data.data
        local flags = reader.long()
        local faces = reader.long()
        local vertices = reader.long()
        local morphs = reader.long()
        if (bit.and flags 0x01000000) != 0 do throw "This native RenderWare platform is not a Leeds Mobile geometry."
        if vertices < 1 or vertices > 65535 or faces > 1000000 or morphs != 1 do throw "DFF import requires one morph target and at most 65535 vertices."
        local version = if (bit.and data.version 0xFFFF0000) != 0 then bit.or ((bit.and (bit.shift data.version -14) 0x3FF00) + 0x30000) (MLBits data.version 16 6) else bit.shift data.version 8
        if version < 0x34000 do reader.seek (reader.tell() + 12)
        if (bit.and flags 8) != 0 do for index = 1 to vertices do append part.colors (color (reader.byte()) (reader.byte()) (reader.byte()) (reader.byte()))
        local uvCount = MLBits flags 16 8
        if uvCount == 0 do uvCount = if (bit.and flags 128) != 0 then 2 else if (bit.and flags 4) != 0 then 1 else 0
        if uvCount > 8 do throw "DFF has too many UV channels."
        for channel = 1 to uvCount do
        (
            local values = for index = 1 to vertices collect [reader.float(),1.0 - reader.float(),0]
            if channel == 1 then part.uv = values else append part.extraUV values
        )
        for index = 1 to faces do
        (
            local second = reader.short() + 1
            local first = reader.short() + 1
            local material = reader.short() + 1
            local third = reader.short() + 1
            if first > vertices or second > vertices or third > vertices do throw "DFF face references a missing vertex."
            append part.faces [first,second,third]; append part.faceIDs material
        )
        reader.point(); reader.float()
        local positions = reader.long()
        local normals = reader.long()
        if positions != 1 do throw "DFF morph target has no positions."
        part.vertices = for index = 1 to vertices collect reader.point()
        if normals != 0 do part.normals = for index = 1 to vertices collect reader.point()
        if reader.tell() != data.finish do throw "DFF geometry structure has an unexpected size."
        reader.length = originalEnd
        local extension = MLDffFind geometry 3
        if extension != undefined and (MLDffFind extension 0x116) != undefined do throw "Standard RenderWare Skin is not supported by this Mobile importer."
        #(part)
    )
    catch (reader.length = originalEnd; throw())
)
fn MLReadMobileDff path =
(
    local reader = MLReader()
    local models = #()
    try
    (
        reader.openFile path
        local cursor = 0
        while cursor < reader.length do
        (
            if reader.length - cursor < 12 then
            (
                reader.seek cursor
                while reader.tell() < reader.length do if reader.byte() != 0 do throw "Trailing or truncated DFF data."
                cursor = reader.length
            )
            else if (reader.atLong cursor) == 0 then
            (
                reader.seek cursor
                while reader.tell() < reader.length do if reader.byte() != 0 do throw "Unexpected data after the DFF clumps."
                cursor = reader.length
            )
            else
            (
                local clump = MLDffReadChunk reader cursor 0x10 0
                local frameList = MLDffFind clump 0xE
                local hierarchy = MLDffFrames reader frameList
                local model = MLModel name:(getFilenameFile path) game:"LCS" platform:"Mobile" sourcePath:path frames:hierarchy[1]
                local geometryList = MLDffFind clump 0x1A
                local shared = if geometryList == undefined then #() else for child in geometryList.children where child.kind == 0xF collect child
                for atomic in clump.children where atomic.kind == 0x14 do
                (
                    local data = MLDffFind atomic 1
                    local frame = (reader.atLong data.data) + 1
                    if frame > model.frames.count do throw "DFF atomic references a missing frame."
                    local geometry = MLDffFind atomic 0xF
                    if geometry == undefined do
                    (
                        local index = (reader.atLong (data.data + 4)) + 1
                        if index > shared.count do throw "DFF atomic references a missing geometry."
                        geometry = shared[index]
                    )
                    local materials = MLDffMaterials reader geometry
                    local parts = if geometry.version == 0xF00D then MLReadPs2Geometry reader (geometry.data - 32) model.name frame mobile:true else MLDffStandardGeometry reader geometry model.name frame
                    local base = model.materials.count
                    for part in parts do
                    (
                        part.atomicPointer = atomic.start
                        if part.faceIDs.count == 0 then
                        (
                            if part.materialID > materials.count do throw "Mobile geometry references a missing material."
                        )
                        else for id in part.faceIDs do if id > materials.count do throw "DFF face references a missing material."
                        part.materialID += base
                        for index = 1 to part.faceIDs.count do part.faceIDs[index] += base
                        for influences in part.weights do
                        (
                            local total = 0.0
                            for influence in influences do
                            (
                                if influence[1] < 1 or influence[1] > 256 or hierarchy[2][influence[1]] == 0 do throw "Mobile geometry refers to an unresolved HAnim skin index."
                                influence[1] = hierarchy[2][influence[1]]
                                total += influence[2]
                            )
                            if total <= 0 do throw "Mobile vertex has no positive skin weights."
                            for influence in influences do influence[2] /= total
                        )
                        append model.parts part
                    )
                    join model.materials materials
                )
                if model.parts.count == 0 do throw "The DFF clump has no geometry."
                append models model
                cursor = clump.finish
            )
        )
        if models.count == 0 do throw "Choose an LCS Mobile DFF file."
        reader.closeFile()
        models
    )
    catch (reader.closeFile(); throw())
)

fn MLImportMobileImages path nodes =
(
    local images = #()
    local folder = getFilenamePath path
    for extension in #("png","tga","dds","bmp") do for image in (getFiles (folder + "*." + extension)) do
        append images #((getFilenameFile image),image)
    local dictionary = folder + (getFilenameFile path) + ".txd"
    if doesFileExist dictionary do
    (
        local decoded = MLReadMobileTextures dictionary (folder + (getFilenameFile path) + "_textures")
        join images decoded
    )
    #(images.count,MLApplyTextures images nodes onlyMissing:true)
)
