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

global MLReadManhunt, MLReadManhuntModels, MLMhFrames, MLMhBoneID, MLMhReadPspGeometry, MLMhReadPcGeometry
fn MLMhBoneID name =
(
    name = toLower (trimLeft (trimRight name))
    name = substituteString (substituteString name " " "_") "-" "_"
    if matchPattern name pattern:"bip01_*" do name = substring name 7 (name.count - 6)
    local names = #("bip01","root","head","l_calf","l_clavicle","l_finger0","l_finger1","l_finger01","l_finger2","l_finger11","l_finger21","l_foot","l_forearm","l_hand","l_thigh","l_toe","l_toe0","l_upperarm","neck","pelvis","r_calf","r_clavicle","r_finger0","r_finger1","r_finger01","r_finger2","r_finger11","r_finger21","r_foot","r_forearm","r_hand","r_thigh","r_toe","r_toe0","r_upperarm","spine","spine1","spine2")
    local ids = #(1000,1000,1001,1002,1003,1004,1005,1006,1008,1011,1013,1019,1020,1021,1023,1024,1024,1039,1040,1045,1056,1057,1058,1059,1060,1062,1065,1067,1073,1074,1075,1077,1078,1078,1093,1094,1095,1096)
    local index = findItem names name
    if index == 0 then -1 else ids[index]
)
fn MLMhFrames reader pointer frames visited conversion =
(
    if pointer == 0 do return frames
    if (findItem visited pointer) != 0 do throw "The Manhunt frame hierarchy contains a cycle or a shared child."
    append visited pointer
    if visited.count > 4096 do throw "The Manhunt hierarchy exceeds 4096 frames."
    reader.check pointer 192
    local localMatrix = inverse conversion * (reader.matrix (pointer + 64)) * conversion
    local worldMatrix = inverse conversion * (reader.matrix (pointer + 128)) * conversion
    local name = reader.text (pointer + 24) 40
    append frames (MLFrame pointer:pointer parentPointer:(reader.atLong (pointer + 8)) name:name localMatrix:localMatrix worldMatrix:worldMatrix boneID:(MLMhBoneID name))
    local child = reader.atLong (pointer + 16)
    local sibling = reader.atLong (pointer + 4)
    if child != 0 do MLMhFrames reader child frames visited conversion
    if sibling != 0 do MLMhFrames reader sibling frames visited conversion
    frames
)
fn MLMhPalette reader frames =
(
    local binding = 0
    for frame in frames while binding == 0 do binding = reader.atLong (frame.pointer + 20)
    if binding == 0 do return #()
    reader.check binding 24
    local count = reader.atLong binding
    local root = reader.atLong (binding + 8)
    local table = reader.atLong (binding + 12)
    if count < 1 or count > 4096 do throw "The Manhunt bone palette count is invalid."
    reader.check table (count * 8)
    local rootIndex = 0
    for index = 1 to frames.count where frames[index].pointer == root do rootIndex = index
    local ordered = rootIndex > 0 and rootIndex + count - 1 <= frames.count
    if ordered do for index = 0 to count - 1 do
    (
        reader.seek (table + index * 8)
        local id = reader.signedShort()
        local target = reader.atLong (table + index * 8 + 4)
        local candidate = frames[rootIndex + index]
        if target != 0 and target != candidate.pointer do ordered = false
        if candidate.boneID >= 0 and candidate.boneID != id do ordered = false
    )
    local palette = #()
    for index = 0 to count - 1 do
    (
        reader.seek (table + index * 8)
        local id = reader.signedShort()
        local target = reader.atLong (table + index * 8 + 4)
        local resolved = 0
        if target != 0 then
        (
            for frameIndex = 1 to frames.count where frames[frameIndex].pointer == target do resolved = frameIndex
        )
        else if ordered then resolved = rootIndex + index
        else if index == 0 and id == 8889 and rootIndex > 0 then resolved = rootIndex
        else
        (
            local matches = for frameIndex = 1 to frames.count where frames[frameIndex].boneID == id collect frameIndex
            if matches.count == 1 do resolved = matches[1]
        )
        if resolved > 0 do frames[resolved].boneID = id
        append palette resolved
    )
    palette
)
fn MLMhMaterials reader header =
(
    local pointer = reader.atLong header
    local count = reader.atLong (header + 4)
    if count > 4096 do throw "The Manhunt material count is invalid."
    reader.check pointer (count * 12)
    local result = #()
    for index = 0 to count - 1 do
    (
        local row = pointer + index * 12
        local textPointer = reader.atLong row
        local name = if textPointer == 0 then "default" else reader.text textPointer (amin 128 (reader.length - textPointer))
        reader.seek (row + 5)
        append result (MLMaterial name:name rgba:(color (reader.byte()) (reader.byte()) (reader.byte()) (reader.byte())))
    )
    result
)
fn MLMhReadPcGeometry reader header name framePointer materialCount =
(
    reader.check header 180
    local materialIDs = reader.atLong (header + 0x2C)
    local faceIndices = reader.atLong (header + 0x30)
    local vertexCount = reader.atLong (header + 0x50)
    local stride = reader.atLong (header + 0x60)
    local vertexType = reader.atLong (header + 0x90)
    local skinned = (bit.and vertexType 0x1000) != 0
    local uvCount = MLBits vertexType 8 4
    local expectedStride = 24 + (if skinned then 20 else 0) + uvCount * 8
    if (findItem #(0x52,0x5E) (bit.and vertexType 255)) == 0 or (bit.and vertexType (bit.not 0x1FFF)) != 0 or uvCount > 8 or stride != expectedStride do throw "Unsupported Manhunt PC vertex layout."
    if vertexCount < 1 or vertexCount > 65535 or faceIndices < 3 or (mod faceIndices 3) != 0 or materialIDs > 4096 do throw "Invalid Manhunt PC mesh counts."
    local facePointer = header + 180 + materialIDs * 44
    local vertexPointer = facePointer + faceIndices * 2
    reader.check facePointer (faceIndices * 2 + vertexCount * stride)
    local part = MLPart name:name framePointer:framePointer
    reader.seek facePointer
    for index = 1 to faceIndices / 3 do
    (
        local face = [reader.short() + 1,reader.short() + 1,reader.short() + 1]
        if face.x > vertexCount or face.y > vertexCount or face.z > vertexCount do throw "Manhunt triangle references a missing vertex."
        append part.faces face
        append part.faceIDs 1
    )
    for index = 0 to materialIDs - 1 do
    (
        local row = header + 180 + index * 44
        local count = reader.atShort (row + 24)
        local slot = reader.atShort (row + 26)
        local first = reader.atShort (row + 28)
        if (mod count 3) != 0 or (mod first 3) != 0 or first + count > faceIndices or slot >= materialCount do throw "Invalid Manhunt material triangle range."
        for face = first / 3 + 1 to (first + count) / 3 do part.faceIDs[face] = slot + 1
    )
    if uvCount > 1 do for channel = 2 to uvCount do append part.extraUV #()
    for index = 0 to vertexCount - 1 do
    (
        local vertex = vertexPointer + index * stride
        append part.vertices (reader.atPoint vertex)
        if skinned do
        (
            reader.seek (vertex + 12)
            local weights = for component = 1 to 4 collect reader.float()
            local influences = #()
            reader.seek (vertex + 28)
            for component = 1 to 4 do
            (
                local token = reader.byte() + 1
                if weights[component] < 0 do throw "The Manhunt skin contains a negative weight."
                if weights[component] > 0 do append influences #(token,weights[component])
            )
            append part.weights influences
        )
        local normalOffset = vertex + (if skinned then 32 else 12)
        reader.seek normalOffset
        append part.normals ([reader.signedShort(),reader.signedShort(),reader.signedShort()] / 32768.0)
        reader.seek (normalOffset + 8)
        local blue = reader.byte()
        local green = reader.byte()
        local red = reader.byte()
        local alpha = reader.byte()
        append part.colors (color red green blue alpha)
        for channel = 1 to uvCount do
        (
            local address = vertex + 24 + (if skinned then 20 else 0) + (channel - 1) * 8
            local uv = [reader.atFloat address,1.0 - reader.atFloat (address + 4),0]
            if channel == 1 then append part.uv uv else append part.extraUV[channel - 1] uv
        )
    )
    #(part)
)
fn MLMhReadPspGeometry reader header name framePointer world:false =
(
    local offset = header + 16
    reader.check offset 80
    local size = reader.atLong offset
    local flags = reader.atLong (offset + 4)
    local strips = reader.atLong (offset + 8)
    local vertexCount = reader.atLong (offset + 44)
    local buffer = reader.atLong (offset + 64)
    local layout = MLPspLayout flags
    if strips < 1 or strips > 4096 or vertexCount < 1 or vertexCount > 1000000 do throw "Invalid Manhunt PSP mesh counts."
    if buffer < 80 + strips * 32 or size < buffer or vertexCount > (size - buffer) / layout[3] do throw "Invalid Manhunt PSP vertex buffer."
    reader.check offset size
    local scale = reader.atPoint (offset + 32)
    local translation = reader.atPoint (offset + 48)
    local parts = #()
    local cursor = 0
    for strip = 0 to strips - 1 do
    (
        local row = offset + 80 + strip * 32
        local count = reader.atShort (row + 16)
        local material = reader.atShort (row + 18) + 1
        local uvScale = reader.atFloat (row + 20)
        if uvScale == 0 do uvScale = 1.0
        local vScale = if world then reader.atFloat (row + 24) else uvScale
        if vScale == 0 do vScale = uvScale
        if world and layout[1][1] != 0 do throw "A Manhunt world vertex layout unexpectedly contains skin weights."
        if cursor + count > vertexCount do throw "Manhunt PSP strip exceeds the vertex buffer."
        local part = MLPart name:(name + "_" + (strip + 1) as string) framePointer:framePointer materialID:material
        local palette = #()
        reader.seek (row + 24)
        for index = 1 to 8 do append palette (reader.byte() + 1)
        for index = 0 to count - 1 do
        (
            local vertex = offset + buffer + (cursor + index) * layout[3]
            local formats = layout[1]
            local fields = layout[2]
            local point = MLReadPspVector reader (vertex + fields[5]) formats[5] 3 false
            append part.vertices [point[1] * scale.x + translation.x,point[2] * scale.y + translation.y,point[3] * scale.z + translation.z]
            if formats[2] != 0 do
            (
                local uv = MLReadPspVector reader (vertex + fields[2]) formats[2] 2 true
                append part.uv [uv[1] * uvScale,1.0 - uv[2] * vScale,0]
            )
            if formats[3] != 0 do
            (
                local format = case formats[3] of (4:512;5:256;6:768;7:0)
                append part.colors (MLTextureColor reader (vertex + fields[3]) (if formats[3] == 7 then 32 else 16) format false)
            )
            if formats[4] != 0 do
            (
                local normal = MLReadPspVector reader (vertex + fields[4]) formats[4] 3 false
                append part.normals [normal[1],normal[2],normal[3]]
            )
            if formats[1] != 0 do
            (
                local weights = MLReadPspVector reader (vertex + fields[1]) formats[1] layout[4] true
                local influences = #()
                for component = 1 to weights.count where weights[component] > 0 do append influences #(palette[component],weights[component])
                append part.weights influences
            )
        )
        part.faces = MLStripFaces count 0
        append parts part
        cursor += count
    )
    if cursor != vertexCount do throw "Manhunt PSP strip counts do not match the vertex count."
    parts
)
fn MLReadManhuntModels path =
(
    local decoded = MLDecodeResource path #("PMLC")
    local reader = MLReader()
    local models = #()
    try
    (
        MLOpenResource reader decoded[1] "PMLC"
        local entry = reader.atLong 32
        local lastEntry = reader.atLong 36
        local visitedEntries = #()
        local conversion = rotateXMatrix 90
        while entry != 0 and entry != 32 do
        (
            if (findItem visitedEntries entry) != 0 do throw "The Manhunt clump entry list contains a cycle."
            append visitedEntries entry
            if visitedEntries.count > 4096 do throw "Too many Manhunt model entries."
            reader.check entry 16
            local body = reader.atLong (entry + 8)
            reader.check body 28
            local model = MLModel game:"MH2" platform:"" sourcePath:path
            local namePointer = reader.atLong (entry + 12)
            model.name = if namePointer == 0 then (getFilenameFile path) else reader.text namePointer (amin 128 (reader.length - namePointer))
            model.frames = MLMhFrames reader (reader.atLong body) #() #() conversion
            local palette = MLMhPalette reader model.frames
            local current = reader.atLong (body + 20)
            local last = reader.atLong (body + 24)
            local visitedObjects = #()
            while current != 0 and current != body + 20 do
            (
                if (findItem visitedObjects current) != 0 do throw "The Manhunt object list contains a cycle."
                append visitedObjects current
                if visitedObjects.count > 8192 do throw "Too many Manhunt model objects."
                reader.check current 28
                local header = reader.atLong (current + 12)
                local parent = reader.atLong (current + 8)
                reader.check header 96
                local materials = MLMhMaterials reader header
                local platform = if (reader.atLong (header + 32)) == 0x0045D454 then "PC" else if (reader.text (header + 80) 4) == "D2SP" then "PS2" else "PSP"
                if model.platform == "" then model.platform = platform
                else if model.platform != platform do throw "A Manhunt clump mixes platform geometry."
                local name = model.name + "_part" + visitedObjects.count as string
                local parts = case platform of
                (
                    "PC": MLMhReadPcGeometry reader header name parent materials.count
                    "PSP": MLMhReadPspGeometry reader header name parent
                    "PS2": MLReadPs2Geometry reader (header - 16) name parent mh2:true
                )
                for part in parts do
                (
                    if part.materialID > materials.count and materials.count > 0 do throw "A Manhunt mesh refers to an invalid material."
                    part.atomicPointer = current
                    part.materialID += model.materials.count
                    for index = 1 to part.faceIDs.count do part.faceIDs[index] += model.materials.count
                    for index = 1 to part.vertices.count do part.vertices[index] *= conversion
                    for index = 1 to part.normals.count do part.normals[index] = normalize (part.normals[index] * conversion)
                    if part.weights.count > 0 do for influences in part.weights do
                    (
                        local total = 0.0
                        for influence in influences do
                        (
                            if influence[1] < 1 or influence[1] > palette.count or palette[influence[1]] == 0 do throw "The Manhunt skin refers to an unresolved bone palette entry."
                            influence[1] = palette[influence[1]]
                            total += influence[2]
                        )
                        if total <= 0 do throw "A Manhunt skinned vertex has no positive bone weights."
                        for influence in influences do influence[2] /= total
                    )
                    append model.parts part
                )
                join model.materials materials
                if current == last then current = 0 else current = reader.atLong current
            )
            if model.parts.count == 0 do throw "The Manhunt clump contains no readable geometry."
            append models model
            if entry == lastEntry then entry = 0 else entry = reader.atLong entry
        )
        reader.closeFile()
        if decoded[2] do deleteFile decoded[1]
        if models.count == 0 do throw "The Manhunt file contains no model entries."
        models
    )
    catch
    (
        reader.closeFile()
        if decoded[2] and doesFileExist decoded[1] do deleteFile decoded[1]
        throw()
    )
)
fn MLReadManhunt path =
(
    local models = MLReadManhuntModels path
    if models.count != 1 do throw "This file contains multiple clumps. Use the model import window to import all entries."
    models[1]
)
