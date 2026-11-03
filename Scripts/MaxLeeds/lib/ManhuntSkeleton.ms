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

global MLMhWriteSkeleton
fn MLMhWriteSkeleton source nodes root destination =
(
    local models = MLReadManhuntModels source
    if models.count != 1 or models[1].platform != "PC" do throw "Skeleton creation currently requires a single-clump PC source."
    local bones = for node in nodes where node != root and ((classof node) == BoneGeometry or (getUserProp node "MaxLeedsFrame") != undefined) collect node
    if bones.count < 1 or bones.count > 256 do throw "Create a hierarchy with 1 to 256 bones/frames beneath the model root."
    local names = #()
    local ids = #()
    local parents = #()
    local originals = #()
    local sourcePointers = for frame in models[1].frames collect frame.pointer
    for bone in bones do
    (
        local original = getUserProp bone "MaxLeedsFrame"
        if original != undefined then
        (
            original = original as integer
            if original == undefined or original <= 0 or (findItem sourcePointers original) == 0 do throw "A frame refers to a different source skeleton. Remove its MaxLeedsFrame property to create a new bone."
            if (findItem originals original) > 0 do throw "Two scene frames refer to the same source frame. Remove the cloned frame's MaxLeedsFrame property."
        )
        else original = 0
        append originals original
        local name = getUserProp bone "MaxLeedsFrameName"
        if name == undefined do name = bone.name
        if name.count < 1 or name.count > 39 do throw "Native bone names must contain 1 to 39 ASCII characters."
        for index = 1 to name.count do if (bit.charAsInt name[index]) < 32 or (bit.charAsInt name[index]) > 126 do throw "Native bone names must use ASCII characters."
        if (findItem names name) > 0 do throw "Native bone names must be unique."
        append names name
        local id = getUserProp bone "MaxLeedsBoneID"
        if id == undefined then id = MLMhBoneID name else id = id as integer
        if id < -32768 or id > 32767 do throw "Bone IDs must fit signed 16-bit values."
        if id < 0 and (getUserProp bone "MaxLeedsFrame") == undefined do throw "Assign MaxLeedsBoneID to each custom bone before rebuilding the skeleton."
        if id >= 0 and (findItem ids id) > 0 do throw "Bone IDs must be unique in the rebuilt palette."
        append ids id
        local parent = findItem bones bone.parent
        if parent == 0 and bone.parent != root do throw "Every skeleton frame must belong directly to another frame or the selected model root."
        append parents parent
    )
    local roots = for index = 1 to bones.count where parents[index] == 0 collect index
    if roots.count != 1 do throw "The native skeleton must have exactly one root frame."
    local reader = MLReader()
    local writer = MLWriter()
    local temporary = MLTemporaryFile destination
    try
    (
        reader.openFile source
        local payloadEnd = reader.atLong 16
        local count = reader.atLong 20
        local fields = for index = 0 to count - 1 collect (reader.atLong (payloadEnd + index * 4))
        reader.length = payloadEnd
        local oldBindings = #()
        for frame in models[1].frames do
        (
            local binding = reader.atLong (frame.pointer + 20)
            if binding != 0 and (findItem oldBindings binding) == 0 do append oldBindings binding
        )
        if oldBindings.count > 1 do throw "Multiple native binding records require a per-object skeleton rebuild."
        if oldBindings.count == 1 do
        (
            reader.check oldBindings[1] 24
            if (reader.atLong (oldBindings[1] + 16)) != 0 or (reader.atLong (oldBindings[1] + 20)) != 0 do throw "This binding has additional native data whose layout must be preserved by a dedicated rebuild."
        )
        MLCopyFileRange source 0 payloadEnd temporary
        writer.stream = fopen temporary "r+b"
        if writer.stream == undefined do throw "Cannot stage the new skeleton."
        writer.seek payloadEnd; writer.align 16
        local frameBase = writer.tell()
        writer.zeros (bones.count * 192)
        local binding = writer.tell()
        if oldBindings.count == 1 then MLMhCopyGeometryBytes reader writer oldBindings[1] 24 else writer.zeros 24
        writer.align 4
        local palette = writer.tell()
        writer.zeros (bones.count * 8)
        local finish = writer.tell()
        local rootPointer = frameBase + (roots[1] - 1) * 192
        if abs (dot (cross root.transform.row1 root.transform.row2) root.transform.row3) < 0.000001 do throw "The model root has a singular transform."
        local rootInverse = inverse root.transform
        local conversion = rotateXMatrix 90
        for index = 1 to bones.count do
        (
            local pointer = frameBase + (index - 1) * 192
            -- Retain opaque source frame words only when they are scalar data.
            -- Unknown pointer-bearing fields need a dedicated relocation layout.
            if originals[index] > 0 do for offset in #(0,12) do
            (
                if (findItem fields (originals[index] + offset)) > 0 do throw "A source frame has an unsupported pointer-bearing extension."
                writer.patchLong (pointer + offset) (reader.atLong (originals[index] + offset))
            )
            local parent = parents[index]
            local siblings = for candidate = 1 to bones.count where parents[candidate] == parent collect candidate
            local siblingIndex = findItem siblings index
            local children = for candidate = 1 to bones.count where parents[candidate] == index collect candidate
            writer.pointer (pointer + 4) (if siblingIndex < siblings.count then frameBase + (siblings[siblingIndex + 1] - 1) * 192 else 0)
            writer.pointer (pointer + 8) (if parent > 0 then frameBase + (parent - 1) * 192 else 0)
            writer.pointer (pointer + 16) (if children.count > 0 then frameBase + (children[1] - 1) * 192 else 0)
            writer.pointer (pointer + 20) binding
            writer.seek (pointer + 24); writer.text names[index]
            local world = bones[index].transform * rootInverse
            local localTransform = if parent > 0 then bones[index].transform * inverse bones[parent].transform else world
            if abs (dot (cross world.row1 world.row2) world.row3) < 0.000001 do throw "A bone has a singular transform."
            writer.seek (pointer + 64); writer.matrix (conversion * localTransform * inverse conversion)
            writer.seek (pointer + 128); writer.matrix (conversion * world * inverse conversion)
            writer.patchLong (pointer + 124) 0x3F800000
            writer.patchLong (pointer + 188) 0x3F800000
            writer.seek (palette + (index - 1) * 8); writer.signedShort ids[index]; writer.short 0
            writer.pointer (palette + (index - 1) * 8 + 4) pointer
        )
        writer.patchLong binding bones.count
        writer.pointer (binding + 8) rootPointer
        writer.pointer (binding + 12) palette
        -- Redirect surviving source references to corresponding new frames.
        for field in fields do
        (
            local target = reader.atLong field
            local mapped = 0
            for index = 1 to bones.count do
            (
                if originals[index] > 0 and originals[index] == target do mapped = frameBase + (index - 1) * 192
            )
            if (findItem oldBindings target) > 0 do mapped = binding
            if mapped != 0 do writer.patchLong field mapped
        )
        local entry = reader.atLong 32
        local body = reader.atLong (entry + 8)
        writer.pointer body rootPointer
        for part in models[1].parts do
        (
            local matches = for node in nodes where (getUserProp node "MaxLeedsAtomic") != undefined and ((getUserProp node "MaxLeedsAtomic") as integer) == part.atomicPointer collect node
            if matches.count != 1 do throw "Every source object must have exactly one scene mesh when rebuilding its skeleton."
            local parent = findItem bones matches[1].parent
            writer.pointer (part.atomicPointer + 8) (if parent > 0 then frameBase + (parent - 1) * 192 else rootPointer)
        )
        writer.seek finish; writer.align 4
        for field in writer.relocations where (findItem fields field) == 0 do append fields field
        sort fields
        local table = writer.tell()
        for field in fields do writer.long field
        writer.patchLong 8 (writer.tell())
        writer.patchLong 12 table; writer.patchLong 16 table; writer.patchLong 20 fields.count
        writer.closeFile(); reader.closeFile()
        local checked = MLReadManhuntModels temporary
        if checked.count != 1 or checked[1].frames.count != bones.count do throw "The new skeleton failed structural read-back validation."
        for id in ids where id >= 0 do
        (
            local matches = for frame in checked[1].frames where frame.boneID == id collect frame
            if matches.count != 1 do throw "The new palette did not preserve a bone ID."
        )
        MLFinishFile temporary destination
        bones.count
    )
    catch
    (
        reader.closeFile(); writer.closeFile()
        if doesFileExist temporary do deleteFile temporary
        throw()
    )
)
