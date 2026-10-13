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

global MLPspLayout, MLReadPspVector, MLReadFrames, MLReadMaterials, MLReadPspGeometry, MLReadModel, MLBuildModel, MLWritePspObject, MLFrameBoneTarget, MLCreateFrameBone
fn MLPspLayout flags =
(
    local formats = #(MLBits flags 9 2, MLBits flags 0 2, MLBits flags 2 3, MLBits flags 5 2, MLBits flags 7 2)
    local weights = (MLBits flags 14 3) + 1
    if (bit.and flags (bit.not 0x1DFFF)) != 0 or (MLBits flags 11 2) != 0 do throw "Indexed or morphed PSP vertices are not supported."
    if formats[5] == 0 or (findItem #(0,4,5,6,7) formats[3]) == 0 do throw "The PSP vertex layout is invalid."
    local offsets = #(-1,-1,-1,-1,-1)
    local cursor = 0
    local alignment = 1
    for index = 1 to 5 where formats[index] != 0 do
    (
        local bytes = if index == 3 then (if formats[index] == 7 then 4 else 2) else #(1,2,4)[formats[index]]
        local count = if index == 1 then weights else if index == 2 then 2 else if index == 3 then 1 else 3
        cursor = MLAlign cursor bytes
        offsets[index] = cursor
        cursor += bytes * count
        alignment = amax alignment bytes
    )
    #(formats, offsets, MLAlign cursor alignment, weights)
)
fn MLReadPspVector reader offset format count unsignedValue =
(
    reader.seek offset
    local values = #()
    for index = 1 to count do
    (
        local value = case format of
        (
            1: ((if unsignedValue then reader.byte() else reader.signedByte()) / 128.0)
            2: ((if unsignedValue then reader.short() else reader.signedShort()) / 32768.0)
            3: reader.float()
            default: throw "Invalid PSP vertex component."
        )
        append values value
    )
    values
)
fn MLReadFrames reader pointer platform game frames parentWorld visited =
(
    if pointer == 0 do return frames
    if (findItem visited pointer) != 0 do throw "The frame hierarchy contains a cycle."
    append visited pointer
    if visited.count > 2048 do throw "The frame hierarchy is too large."
    reader.check pointer 0xAC
    local parentPointer = reader.atLong (pointer + 4)
    local localMatrix = reader.matrix (pointer + 0x10)
    local globalMatrix = reader.matrix (pointer + 0x50)
    local world = localMatrix * parentWorld
    if game != "LCS" do
    (
        if (length globalMatrix.row1) >= 1.0e-8 and (length globalMatrix.row2) >= 1.0e-8 and (length globalMatrix.row3) >= 1.0e-8 do world = globalMatrix
    )
    local nameOffset = if platform == "PSP" or game == "VCS" then 0xA8 else 0xA4
    local namePointer = reader.atLong (pointer + nameOffset)
    local name = if namePointer > 0 then reader.text namePointer (amin 128 (reader.length - namePointer)) else "bone" + frames.count as string
    append frames (MLFrame pointer:pointer parentPointer:parentPointer name:name localMatrix:localMatrix worldMatrix:world)
    local child = reader.atLong (pointer + 0x90)
    local sibling = reader.atLong (pointer + 0x94)
    if child != 0 do MLReadFrames reader child platform game frames world visited
    if sibling != 0 do MLReadFrames reader sibling platform game frames parentWorld visited
    frames
)
fn MLReadMaterials reader geometry =
(
    local table = reader.atLong (geometry + 12)
    local count = reader.atLong (geometry + 16)
    if count > 2048 do throw "The material count is invalid."
    reader.check table (count * 4)
    local materials = #()
    for index = 0 to count - 1 do
    (
        local pointer = reader.atLong (table + index * 4)
        reader.check pointer 16
        local namePointer = reader.atLong pointer
        local rgba = MLColor (reader.atLong (pointer + 4))
        local name = if namePointer > 0 then reader.text namePointer (amin 64 (reader.length - namePointer)) else "default"
        append materials (MLMaterial name:name rgba:rgba)
    )
    materials
)
fn MLReadPspGeometry reader geometry atomicName framePointer =
(
    local header = geometry + 0x20
    reader.check header 0x48
    local size = reader.atLong header
    local flags = reader.atLong (header + 4)
    local strips = reader.atLong (header + 8)
    local vertexCount = reader.atLong (header + 0x2C)
    local bufferOffset = reader.atLong (header + 0x40)
    if strips < 1 or strips > 4096 or vertexCount < 1 or vertexCount > 1000000 do throw "The PSP mesh counts are invalid."
    if bufferOffset < 0x48 + strips * 0x30 or bufferOffset > size do throw "The PSP vertex buffer overlaps its mesh table."
    reader.check header size
    local layout = MLPspLayout flags
    if vertexCount * layout[3] > size - bufferOffset do throw "The PSP vertex buffer is truncated."
    local scale = reader.atPoint (header + 0x20)
    local position = reader.atPoint (header + 0x30)
    local parts = #()
    local total = 0
    for stripIndex = 0 to strips - 1 do
    (
        local descriptor = header + 0x48 + stripIndex * 0x30
        local relative = reader.atLong descriptor
        local count = reader.atShort (descriptor + 4) + 2
        local materialID = reader.atShort (descriptor + 6) + 1
        local uvScale = [reader.atFloat (descriptor + 12), reader.atFloat (descriptor + 16), 1]
        reader.check (header + bufferOffset + relative) (count * layout[3])
        if relative + count * layout[3] > size - bufferOffset do throw "A PSP strip extends past the vertex buffer."
        local boneMap = #()
        reader.seek (descriptor + 40)
        for index = 1 to 8 do append boneMap (reader.byte())
        local part = MLPart name:(atomicName + "_part" + (stripIndex + 1) as string) materialID:materialID framePointer:framePointer
        for vertexIndex = 0 to count - 1 do
        (
            local vertex = header + bufferOffset + relative + vertexIndex * layout[3]
            local formats = layout[1]
            local offsets = layout[2]
            local value = MLReadPspVector reader (vertex + offsets[5]) formats[5] 3 false
            append part.vertices [value[1] * scale.x + position.x, value[2] * scale.y + position.y, value[3] * scale.z + position.z]
            if formats[2] != 0 do
            (
                local uv = MLReadPspVector reader (vertex + offsets[2]) formats[2] 2 true
                append part.uv [uv[1] * uvScale.x, 1.0 - uv[2] * uvScale.y, 0]
            )
            if formats[3] != 0 do
            (
                local format = case formats[3] of (4: 512; 5: 256; 6: 768; 7: 0)
                append part.colors (MLTextureColor reader (vertex + offsets[3]) (if formats[3] == 7 then 32 else 16) format false)
            )
            if formats[4] != 0 do
            (
                local normal = MLReadPspVector reader (vertex + offsets[4]) formats[4] 3 false
                append part.normals [normal[1],normal[2],normal[3]]
            )
            if formats[1] != 0 do
            (
                local weights = MLReadPspVector reader (vertex + offsets[1]) formats[1] layout[4] true
                local influences = #()
                for index = 1 to weights.count where weights[index] > 0 do append influences #(boneMap[index] + 1, weights[index])
                append part.weights influences
            )
        )
        part.faces = MLStripFaces count 0
        total += count
        append parts part
    )
    if total != vertexCount do throw "PSP strip counts do not match the geometry header."
    parts
)
fn MLReadModel path game platform =
(
    local reader = MLReader()
    local model = MLModel game:game platform:platform sourcePath:path
    try
    (
        reader.openFile path
        if (reader.text 0 4) != "ldm" do throw "Choose a Stories MDL file."
        local logicalEnd = reader.atLong 8
        reader.check 0 logicalEnd
        local candidates = #(0x20, reader.atLong 0x20, reader.atLong 0x24)
        local top = 0
        local atomics = #()
        local rootFrame = 0
        for candidate in candidates where top == 0 and candidate >= 0x20 and candidate + 0x34 <= logicalEnd do
        (
            local kind = bit.and (reader.atLong candidate) 255
            if kind == 1 then
            (
                local frame = reader.atLong (candidate + 4)
                local geometry = reader.atLong (candidate + 20)
                if frame >= 0x20 and geometry >= 0x20 and geometry + 0x68 <= logicalEnd do (top = candidate; append atomics candidate; rootFrame = frame)
            )
            else if kind == 2 do
            (
                local first = reader.atLong (candidate + 8)
                if first >= 0x3C and first + 24 <= logicalEnd do
                (
                    top = candidate
                    rootFrame = reader.atLong (candidate + 4)
                    local link = first
                    local visited = #()
                    while link != candidate + 8 and link != 0 do
                    (
                        if (findItem visited link) != 0 do throw "The model object list contains a cycle."
                        append visited link
                        if visited.count > 2048 do throw "Too many model objects."
                        local atomic = link - 0x1C
                        reader.check atomic 0x34
                        if (bit.and (reader.atLong atomic) 255) != 1 do throw "The model object list contains an invalid entry."
                        append atomics atomic
                        link = reader.atLong (atomic + 28)
                    )
                )
            )
        )
        if top == 0 or atomics.count == 0 do throw "A supported model root was not found."
        model.frames = MLReadFrames reader rootFrame platform game #() (matrix3 1) #()
        for atomicIndex = 1 to atomics.count do
        (
            local atomic = atomics[atomicIndex]
            local frame = reader.atLong (atomic + 4)
            local geometry = reader.atLong (atomic + 20)
            local hierarchy = reader.atLong (atomic + 44)
            model.modelID = reader.atShort (atomic + 40)
            if hierarchy != 0 do
            (
                reader.check hierarchy 0x38
                if (reader.atLong hierarchy) != 0x3000 do throw "The animation bone table is invalid."
                local count = reader.atLong (hierarchy + 4)
                local table = reader.atLong (hierarchy + 0x30)
                local anchor = reader.atLong (hierarchy + 0x34)
                if count < 1 or count > 512 do throw "The bone count is invalid."
                reader.check table (count * 8)
                local traversal = MLReadFrames reader anchor platform game #() (matrix3 1) #()
                for entryIndex = 0 to count - 1 do
                (
                    local packed = reader.atLong (table + entryIndex * 8)
                    local nodeIndex = (MLBits packed 8 8) + 1
                    if nodeIndex > traversal.count do throw "The bone table refers to a missing frame."
                    local pointer = traversal[nodeIndex].pointer
                    for frameRecord in model.frames where frameRecord.pointer == pointer do frameRecord.boneID = bit.and packed 255
                )
            )
            local materials = MLReadMaterials reader geometry
            local usePspGeometry = platform == "PSP"
            if platform == "PS2" do
            (
                local header = geometry + 0x20
                reader.check header 0x48
                local embeddedSize = reader.atLong header
                local embeddedFlags = reader.atLong (header + 4)
                local embeddedCount = reader.atLong (header + 8)
                local embeddedBuffer = reader.atLong (header + 0x40)
                if embeddedSize >= 0x48 and embeddedSize <= reader.length - header and embeddedCount > 0 and embeddedCount <= 4096 and embeddedBuffer >= 0x48 + embeddedCount * 0x30 and embeddedBuffer <= embeddedSize and (bit.and embeddedFlags (bit.not 0x1DFFF)) == 0 do usePspGeometry = true
            )
            local parts = if usePspGeometry then MLReadPspGeometry reader geometry ((getFilenameFile path) + "_" + atomicIndex as string) frame else MLReadPs2Geometry reader geometry ((getFilenameFile path) + "_" + atomicIndex as string) frame
            for part in parts where part.weights.count > 0 and hierarchy == 0 do throw "The character has no mapped bone hierarchy."
            local materialBase = model.materials.count
            for part in parts do
            (
                part.materialID += materialBase
                if part.weights.count > 0 and hierarchy != 0 do
                (
                    local anchor = reader.atLong (hierarchy + 0x34)
                    local traversal = MLReadFrames reader anchor platform game #() (matrix3 1) #()
                    for influences in part.weights do for influence in influences do
                    (
                        if influence[1] > traversal.count do throw "The mesh refers to a missing bone."
                        local pointer = traversal[influence[1]].pointer
                        local mappedIndex = 0
                        for index = 1 to model.frames.count where model.frames[index].pointer == pointer do mappedIndex = index
                        if mappedIndex == 0 do throw "The mesh bone has no frame."
                        influence[1] = mappedIndex
                    )
                )
                append model.parts part
            )
            join model.materials materials
        )
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
fn MLFrameBoneTarget frame frames =
(
    local startPosition = frame.worldMatrix.row4
    local bestDistance = 0.0
    local bestPosition = undefined
    for child in frames where child.parentPointer == frame.pointer do
    (
        local childPosition = child.worldMatrix.row4
        local childDistance = distance startPosition childPosition
        if childDistance > 0.00001 do
        (
            if bestPosition == undefined or childDistance < bestDistance do
            (
                bestPosition = childPosition
                bestDistance = childDistance
            )
        )
    )
    if bestPosition != undefined then bestPosition
    else
    (
        local direction = frame.worldMatrix.row1
        if (length direction) < 0.00001 then direction = [1,0,0]
        startPosition + (normalize direction) * 0.025
    )
)

fn MLCreateFrameBone frame frames =
(
    local world = frame.worldMatrix
    local startPosition = world.row4
    local endPosition = MLFrameBoneTarget frame frames
    local xAxis = world.row1
    local zAxis = world.row3
    if (length xAxis) < 0.000001 or (length zAxis) < 0.000001 do
        throw "A model bone has an invalid orientation."
    xAxis = normalize xAxis
    zAxis = normalize zAxis
    if (abs (dot xAxis zAxis)) > 0.9999 do
    (
        local yAxis = world.row2
        if (length yAxis) < 0.000001 do throw "A model bone has an invalid orientation."
        zAxis = normalize (cross xAxis (normalize yAxis))
    )
    local boneDirection = normalize (endPosition - startPosition)
    local boneLength = distance startPosition endPosition
    local node = undefined
    try
    (
        node = boneSys.createBone startPosition endPosition zAxis
        if node == undefined do throw "3ds Max could not create a bone."
        node.name = frame.name
        node.setBoneEnable false 0
        node.boneAutoAlign = false
        node.boneScaleType = #none
        node.width = amax 0.003 (amin 0.01 (boneLength * 0.035))
        node.height = node.width
        node.length = boneLength
        node.transform = world
        
        -- Keep the original frame orientation as the bone pivot.
        -- Only the display geometry is rotated to meet its real child joint.
        local alignmentDot = amax -1.0 (amin 1.0 (dot xAxis boneDirection))
        if alignmentDot < 0.999999 do
        (
            local alignmentAxis = cross xAxis boneDirection
            if (length alignmentAxis) < 0.000001 do
            (
                alignmentAxis = cross xAxis [0,0,1]
                if (length alignmentAxis) < 0.000001 do alignmentAxis = cross xAxis [0,1,0]
            )
            alignmentAxis = normalize alignmentAxis
            node.objectOffsetRot = quat (acos alignmentDot) alignmentAxis
        )
        node
    )
    catch
    (
        if isValidNode node do delete node
        throw()
    )
)

fn MLBuildModel model =
(
    local created = #()
    try
    (
        local root = dummy name:(getFilenameFile model.sourcePath)
        root.boxsize = [0.1,0.1,0.1]
        append created root
        setUserProp root "MaxLeedsRoot" true
        setUserProp root "MaxLeedsGame" model.game
        setUserProp root "MaxLeedsPlatform" model.platform
        setUserProp root "MaxLeedsModelID" model.modelID
        setUserProp root "MaxLeedsSource" model.sourcePath
        local frameNodes = #()
        for frame in model.frames do
        (
            local node = MLCreateFrameBone frame model.frames
            setUserProp node "MaxLeedsFrame" frame.pointer
            setUserProp node "MaxLeedsFrameName" frame.name
            setUserProp node "MaxLeedsBoneID" frame.boneID
            setUserProp node "MaxLeedsLocalMatrix" (frame.localMatrix as string)
            setUserProp node "MaxLeedsBindMatrix" (frame.worldMatrix as string)
            append frameNodes node
            append created node
        )
        for index = 1 to model.frames.count do
        (
            local parent = root
            for parentIndex = 1 to model.frames.count where model.frames[parentIndex].pointer == model.frames[index].parentPointer do parent = frameNodes[parentIndex]
            frameNodes[index].parent = parent
            frameNodes[index].transform = model.frames[index].worldMatrix
        )
        for index = 1 to model.frames.count do
        (
            frameNodes[index].transform = model.frames[index].worldMatrix
        )
        for index = 1 to model.frames.count do
        (
            frameNodes[index].setBoneEnable true 0
            frameNodes[index].boneAutoAlign = false
            frameNodes[index].boneScaleType = #none
            if model.frames[index].boneID < 0 do hide frameNodes[index]
        )
        for index = 1 to model.frames.count do
        (
            if (distance frameNodes[index].pos model.frames[index].worldMatrix.row4) > 0.001 do
                throw ("3ds Max moved imported bone " + model.frames[index].name + ". The import was cancelled.")
        )
        for part in model.parts do
        (
            local node = MLCreateMesh part model.materials
            append created node
            local frameIndex = 0
            for index = 1 to model.frames.count where model.frames[index].pointer == part.framePointer do frameIndex = index
            -- Skin meshes cannot be parented to a weighted bone: that would apply its transform twice.
            -- Rigid pieces still follow their model frame.
            if part.weights.count > 0 then node.parent = root
            else node.parent = if frameIndex > 0 then frameNodes[frameIndex] else root
            node.transform = if frameIndex > 0 then model.frames[frameIndex].worldMatrix else matrix3 1
            if part.weights.count > 0 do
            (
                local modifier = Skin()
                addModifier node modifier
                select node
                setCommandPanelTaskMode #modify
                modPanel.setCurrentObject modifier
                for index = 1 to frameNodes.count do
                (
                    skinOps.addBone modifier frameNodes[index] (if index == frameNodes.count then 1 else 0)
                )
                if isProperty modifier #weightAllVertices do modifier.weightAllVertices = false
                for vertex = 1 to part.weights.count do
                (
                    local boneIDs = #()
                    local weights = #()
                    for influence in part.weights[vertex] do
                    (
                        if influence[1] < 1 or influence[1] > frameNodes.count do throw "A skin weight refers to a missing bone."
                        if influence[2] > 0.0 do
                        (
                            local existing = findItem boneIDs influence[1]
                            if existing == 0 then
                            (
                                append boneIDs influence[1]
                                append weights influence[2]
                            )
                            else weights[existing] += influence[2]
                        )
                    )
                    if boneIDs.count == 0 do throw "A skinned vertex has no bone influence."
                    -- Replace all influences in one operation, then preserve the game's weights.
                    skinOps.ReplaceVertexWeights modifier vertex boneIDs weights
                    skinOps.unNormalizeVertex modifier vertex true
                    local actual = for index = 1 to frameNodes.count collect 0.0
                    for index = 1 to (skinOps.GetVertexWeightCount modifier vertex) do
                    (
                        local bone = skinOps.GetVertexWeightBoneID modifier vertex index
                        if bone >= 1 and bone <= actual.count do
                            actual[bone] += skinOps.GetVertexWeight modifier vertex index
                    )
                    for index = 1 to actual.count do
                    (
                        local expectedIndex = findItem boneIDs index
                        local expected = if expectedIndex > 0 then weights[expectedIndex] else 0.0
                        if (abs (actual[index] - expected)) > 0.0001 do throw "Skin did not preserve the source bone weights."
                    )
                )
            )
        )
        select root
        redrawViews()
        created.count
    )
    catch
    (
        local reason = getCurrentException()
        for node in created where isValidNode node do delete node
        throw()
    )
)
fn MLWritePspObject destination nodes game modelID =
(
    if modelID < 0 or modelID > 65534 do throw "Enter the game's model ID, or import its original model first."
    local writer = MLWriter()
    local temporary = MLTemporaryFile destination
    local snapshots = #()
    try
    (
        local triangles = #()
        local materials = #()
        local materialNodes = #()
        local referenceRoot = undefined
        local rootCount = 0
        for node in nodes where (getUserProp node "MaxLeedsRoot") == "true" do
        (
            referenceRoot = node
            rootCount += 1
        )
        if rootCount > 1 do throw "Select one model root for MDL export."
        local rootInverse = if referenceRoot != undefined then inverse referenceRoot.transform else matrix3 1
        for node in nodes where (superclassof node) == GeometryClass and (classof node) != BoneGeometry do
        (
            for modifier in node.modifiers where (classof modifier) == Skin do throw "Character model export has not been ported. Use Object / weapon export for an unskinned mesh."
            local snapshot = snapshotAsMesh node
            append snapshots snapshot
            for faceIndex = 1 to snapshot.numfaces do
            (
                local face = getFace snapshot faceIndex
                local materialID = getFaceMatID snapshot faceIndex
                local material = if (classof node.material) == MultiMaterial then node.material.materialList[materialID] else node.material
                local slot = findItem materialNodes material
                if slot == 0 do
                (
                    append materialNodes material
                    local name = if material != undefined then material.name else "default"
                    if material != undefined and isProperty material #diffuseMap and material.diffuseMap != undefined and isProperty material.diffuseMap #filename do name = getFilenameFile material.diffuseMap.filename
                    if name.count > 31 do throw "PSP texture names must be at most 31 characters."
                    local rgba = if material != undefined then copy material.diffuse else color 255 255 255 255
                    rgba.a = if material != undefined then material.opacity * 255.0 / 100.0 else 255
                    append materials (MLMaterial name:name rgba:rgba)
                    slot = materials.count
                )
                local uvFace = if meshop.getMapSupport snapshot 1 then meshop.getMapFace snapshot 1 faceIndex else [0,0,0]
                local colorFace = if meshop.getMapSupport snapshot 0 then meshop.getMapFace snapshot 0 faceIndex else [0,0,0]
                local alphaFace = if meshop.getMapSupport snapshot -2 then meshop.getMapFace snapshot -2 faceIndex else [0,0,0]
                local faceNormals = meshop.getFaceRNormals snapshot faceIndex
                local inverseMatrix = inverse (node.objectTransform * rootInverse)
                local normalMatrix = matrix3 [inverseMatrix.row1.x,inverseMatrix.row2.x,inverseMatrix.row3.x] [inverseMatrix.row1.y,inverseMatrix.row2.y,inverseMatrix.row3.y] [inverseMatrix.row1.z,inverseMatrix.row2.z,inverseMatrix.row3.z] [0,0,0]
                local corners = #()
                for corner = 1 to 3 do
                (
                    local point = (getVert snapshot (face[corner] as integer)) * node.objectTransform * rootInverse
                    local uv = if uvFace[corner] > 0 then meshop.getMapVert snapshot 1 (uvFace[corner] as integer) else [0,0,0]
                    local rgba = color 255 255 255 255
                    if colorFace[corner] > 0 do
                    (
                        local value = meshop.getMapVert snapshot 0 (colorFace[corner] as integer)
                        rgba = color (value.x * 255) (value.y * 255) (value.z * 255) 255
                    )
                    if alphaFace[corner] > 0 do rgba.a = (meshop.getMapVert snapshot -2 (alphaFace[corner] as integer)).x * 255
                    local normal = normalize (faceNormals[corner] * normalMatrix)
                    append corners #(point,uv,rgba,normal)
                )
                append triangles #(slot,corners)
            )
        )
        if triangles.count < 1 or triangles.count > 4096 do throw "PSP object export requires between 1 and 4096 triangles in this build. Split larger objects."
        local ordered = #()
        for slot = 1 to materials.count do for triangle in triangles where triangle[1] == slot do append ordered triangle
        triangles = ordered
        writer.openFile temporary
        writer.zeros 0x30
        local frame = writer.tell()
        writer.zeros 0xAC
        writer.align 16
        local geometry = writer.tell()
        writer.zeros 0x20
        local header = writer.tell()
        writer.zeros (0x48 + triangles.count * 0x30)
        writer.align 4
        local verticesPointer = writer.tell()
        for triangle in triangles do for corner in triangle[2] do
        (
            writer.float corner[2].x; writer.float (1.0 - corner[2].y)
            local rgba = corner[3]
            writer.byte (rgba.r as integer); writer.byte (rgba.g as integer); writer.byte (rgba.b as integer); writer.byte (rgba.a as integer)
            writer.point corner[4]
            writer.point corner[1]
        )
        local geometryEnd = writer.tell()
        local materialPointers = #()
        for description in materials do
        (
            writer.align 4
            local pointer = writer.tell()
            append materialPointers pointer
            writer.long 0
            local rgba = description.rgba
            writer.long (bit.or (rgba.r as integer) (bit.or (bit.shift (rgba.g as integer) 8) (bit.or (bit.shift (rgba.b as integer) 16) (bit.shift (rgba.a as integer) 24))))
            writer.long 2; writer.long 0
        )
        local materialTable = writer.tell()
        for pointer in materialPointers do
        (
            local field = writer.tell()
            writer.long pointer
            append writer.relocations field
        )
        writer.align 16
        local atomic = writer.tell()
        writer.zeros 0x34
        local frameName = writer.tell()
        writer.text "dummy"
        local end = writer.tell()
        writer.seek frame
        writer.long 0x03000000
        writer.seek (frame + 0x10)
        writer.matrix (matrix3 1)
        writer.matrix (matrix3 1)
        writer.seek end
        writer.pointer (frame + 8) (atomic + 8)
        writer.pointer (frame + 12) (atomic + 8)
        writer.pointer (frame + 0x98) frame
        writer.pointer (frame + 0xA8) frameName
        writer.patchLong geometry 8
        writer.patchLong (geometry + 8) 1
        writer.pointer (geometry + 12) materialTable
        writer.patchLong (geometry + 16) materials.count
        writer.patchLong (geometry + 20) materials.count
        local minimum = copy triangles[1][2][1][1]
        local maximum = copy minimum
        for triangle in triangles do for corner in triangle[2] do for axis = 1 to 3 do
        (
            minimum[axis] = amin minimum[axis] corner[1][axis]
            maximum[axis] = amax maximum[axis] corner[1][axis]
        )
        local center = (minimum + maximum) / 2
        local radius = 0.0
        for triangle in triangles do for corner in triangle[2] do radius = amax radius (distance center corner[1])
        writer.seek (header + 16)
        writer.point center
        writer.float radius
        writer.seek end
        writer.patchLong header (geometryEnd - header)
        writer.patchLong (header + 4) 0x1FF
        writer.patchLong (header + 8) triangles.count
        writer.seek (header + 0x20)
        writer.point [1,1,1]
        writer.long (triangles.count * 3)
        writer.point [0,0,0]
        writer.long 0
        writer.long (verticesPointer - header)
        writer.float 0
        for index = 1 to triangles.count do
        (
            writer.seek (header + 0x48 + (index - 1) * 0x30)
            writer.long ((index - 1) * 108)
            writer.short 1
            writer.short (triangles[index][1] - 1)
            writer.float 0; writer.float 1; writer.float 1
            local corners = triangles[index][2]
            writer.float (amin corners[1][2].x corners[2][2].x corners[3][2].x)
            writer.float (1.0 - amax corners[1][2].y corners[2][2].y corners[3][2].y)
            writer.float (amax corners[1][2].x corners[2][2].x corners[3][2].x)
            writer.float (1.0 - amin corners[1][2].y corners[2][2].y corners[3][2].y)
            writer.float 0
            writer.zeros 8
        )
        writer.seek end
        writer.patchLong atomic (if game == "LCS" then 0x01050001 else 0x00041601)
        writer.pointer (atomic + 4) frame
        writer.pointer (atomic + 8) (frame + 8)
        writer.pointer (atomic + 12) (frame + 8)
        writer.pointer (atomic + 20) geometry
        writer.seek (atomic + 40)
        writer.short modelID; writer.short 0
        writer.seek end
        writer.pointer 0x20 atomic
        writer.align 4
        local relocationOffset = writer.tell()
        local textureHead = relocationOffset + (writer.relocations.count + materials.count + 1) * 4
        for offset in writer.relocations do writer.long offset
        for offset in materialPointers do writer.long offset
        writer.long textureHead
        writer.long (atomic + 0x24)
        for index = 1 to materials.count do
        (
            local namePointer = writer.tell()
            writer.text materials[index].name
            writer.patchLong materialPointers[index] namePointer
        )
        local logicalEnd = writer.tell()
        writer.patchLong 0 0x006D646C
        writer.patchLong 8 logicalEnd
        writer.patchLong 12 relocationOffset
        writer.patchLong 16 relocationOffset
        writer.patchLong 20 (writer.relocations.count + materials.count + 1)
        writer.patchLong 0x18 textureHead
        writer.patchLong 0x1C 0x10000
        writer.align 2048
        writer.closeFile()
        for snapshot in snapshots do free snapshot
        snapshots = #()
        MLFinishFile temporary destination
        triangles.count
    )
    catch
    (
        local reason = getCurrentException()
        writer.closeFile()
        for snapshot in snapshots do free snapshot
        if doesFileExist temporary do deleteFile temporary
        throw()
    )
)
