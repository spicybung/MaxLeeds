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

global MLPspLayout, MLReadPspVector, MLReadFrames, MLReadMaterials, MLReadPspGeometry, MLReadModel, MLBuildModel, MLWritePspObject, MLWritePs2Object, MLWriteClumpModel, MLFrameBoneTarget, MLCreateFrameBone, MLGatherExportGeometry, MLWriteSkeleton, MLTrianglePalette, MLBuildModelStrips, MLMdlSameGroup, MLMdlObjectGroups, MLMdlRigidLocalGeometry, MLMdlRootFrame, MLValidateStoriesExport
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
    if game != "LCS" and game != "MH2" do
    (
        if (length globalMatrix.row1) >= 1.0e-8 and (length globalMatrix.row2) >= 1.0e-8 and (length globalMatrix.row3) >= 1.0e-8 do world = globalMatrix
    )
    local nameOffset = if platform == "PSP" or game == "VCS" then 0xA8 else 0xA4
    local namePointer = reader.atLong (pointer + nameOffset)
    local name = if namePointer > 0 and namePointer < reader.length then reader.text namePointer (amin 128 (reader.length - namePointer)) else "frame" + (frames.count + 1) as string
    if name == "" do name = "frame" + (frames.count + 1) as string
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
fn MLMdlAtomicTag game platform =
(
    if game == "LCS" then 0x01050001 else if platform == "PS2" then 0x0004AA01 else 0x00041601
)
fn MLMdlClumpTag game platform =
(
    if game == "VCS" and platform == "PS2" then 0x0000AA02 else 0x00000002
)
fn MLMdlIsAtomic tag platform =
(
    (bit.and tag 255) == 1 or (platform == "PSP" and tag == 0x01F40400)
)
fn MLMdlRootFrame reader pointer =
(
    local visited = #()
    local current = pointer
    while current != 0 do
    (
        if (findItem visited current) != 0 do throw "The MDL frame parent list contains a cycle."
        append visited current
        if visited.count > 2048 do throw "The MDL frame parent list is too long."
        reader.check current 0xAC
        local parent = reader.atLong (current + 4)
        if parent == 0 do return current
        current = parent
    )
    throw "The model has no valid root frame."
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
        if logicalEnd < 0x28 do throw "The MDL logical size is invalid."
        reader.check 0 logicalEnd
        reader.length = logicalEnd
        local candidates = #(0x20, reader.atLong 0x20, reader.atLong 0x24)
        local top = 0
        local atomics = #()
        local rootFrame = 0
        for candidate in candidates where top == 0 and candidate >= 0x20 and candidate + 0x34 <= logicalEnd do
        (
            local tag = reader.atLong candidate
            local kind = bit.and tag 255
            if MLMdlIsAtomic tag platform then
            (
                local frame = reader.atLong (candidate + 4)
                local geometry = reader.atLong (candidate + 20)
                if frame >= 0x20 and geometry >= 0x20 and geometry + 0x68 <= logicalEnd do (top = candidate; append atomics candidate; rootFrame = MLMdlRootFrame reader frame)
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
                        if not (MLMdlIsAtomic (reader.atLong atomic) platform) do throw "The model object list contains an invalid entry."
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
            local traversal = #()
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
                traversal = MLReadFrames reader anchor platform game #() (matrix3 1) #()
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
                part.atomicPointer = atomic
                if part.materialID < 1 or part.materialID > materials.count do throw "A Stories geometry part refers to a missing material."
                part.materialID += materialBase
                for index = 1 to part.faceIDs.count do part.faceIDs[index] += materialBase
                if part.weights.count > 0 and hierarchy != 0 do
                (
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
    local preferred = false
    for child in frames where child.parentPointer == frame.pointer do
    (
        local childPosition = child.worldMatrix.row4
        local childDistance = distance startPosition childPosition
        if childDistance > 0.00001 do
        (
            local actualBone = child.boneID >= 0
            if bestPosition == undefined or (actualBone and not preferred) or (actualBone == preferred and childDistance < bestDistance) do
            (
                bestPosition = childPosition
                bestDistance = childDistance
                preferred = actualBone
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
    if frame.boneID < 0 do
    (
        local helper = point name:frame.name pos:startPosition size:0.015 cross:true box:false
        helper.transform = world
        helper.isHidden = true
        return helper
    )
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
        local root = dummy name:(if model.name == "" then getFilenameFile model.sourcePath else model.name)
        root.boxsize = [0.1,0.1,0.1]
        append created root
        setUserProp root "MaxLeedsRoot" true
        setUserProp root "MaxLeedsGame" model.game
        setUserProp root "MaxLeedsPlatform" model.platform
        setUserProp root "MaxLeedsModelID" model.modelID
        setUserProp root "MaxLeedsSource" model.sourcePath
        if model.game == "MH2" do setUserProp root "MaxLeedsSourceDigest" (MLFileDigest model.sourcePath)
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
            if model.frames[index].boneID >= 0 do
            (
                frameNodes[index].setBoneEnable true 0
                frameNodes[index].boneAutoAlign = false
                frameNodes[index].boneScaleType = #none
            )
            else hide frameNodes[index]
        )
        for index = 1 to model.frames.count do
        (
            if (distance frameNodes[index].pos model.frames[index].worldMatrix.row4) > 0.001 do
                throw ("3ds Max moved imported bone " + model.frames[index].name + ". The import was cancelled.")
        )
        local sharedMaterial = MLCreateMaterial model.materials root.name
        for part in model.parts do
        (
            local node = MLCreateMesh part model.materials sharedMaterial:sharedMaterial
            append created node
            setUserProp node "MaxLeedsAtomic" part.atomicPointer
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
                local lastBoneIndex = 0
                for index = 1 to frameNodes.count where model.frames[index].boneID >= 0 do lastBoneIndex = index
                if lastBoneIndex == 0 do throw "The character does not contain valid animation bones."
                for index = 1 to frameNodes.count where model.frames[index].boneID >= 0 do
                (
                    skinOps.addBone modifier frameNodes[index] (if index == lastBoneIndex then 1 else 0)
                )
                local skinBoneMap = for index = 1 to frameNodes.count collect 0
                for index = 1 to frameNodes.count where model.frames[index].boneID >= 0 do
                (
                    for skinIndex = 1 to (skinOps.GetNumberBones modifier) where (skinOps.GetBoneName modifier skinIndex 0) == frameNodes[index].name do skinBoneMap[index] = skinIndex
                    if skinBoneMap[index] == 0 do throw ("Skin did not register bone " + frameNodes[index].name)
                )
                if isProperty modifier #weightAllVertices do modifier.weightAllVertices = false
                for vertex = 1 to part.weights.count do
                (
                    local boneIDs = #()
                    local weights = #()
                    for influence in part.weights[vertex] do
                    (
                        if influence[1] < 1 or influence[1] > frameNodes.count do throw "A skin weight refers to a missing bone."
                        if model.frames[influence[1]].boneID < 0 do throw "A skin weight refers to a helper frame rather than an animation bone."
                        if influence[2] > 0.0 do
                        (
                            local skinIndex = skinBoneMap[influence[1]]
                            local existing = findItem boneIDs skinIndex
                            if existing == 0 then
                            (
                                append boneIDs skinIndex
                                append weights influence[2]
                            )
                            else weights[existing] += influence[2]
                        )
                    )
                    if boneIDs.count == 0 do throw "A skinned vertex has no bone influence."
                    -- Replace all influences in one operation, then preserve the game's weights.
                    skinOps.ReplaceVertexWeights modifier vertex boneIDs weights
                    skinOps.unNormalizeVertex modifier vertex true
                    local actual = for index = 1 to boneIDs.count collect 0.0
                    for index = 1 to (skinOps.GetVertexWeightCount modifier vertex) do
                    (
                        local bone = skinOps.GetVertexWeightBoneID modifier vertex index
                        local slot = findItem boneIDs bone
                        local value = skinOps.GetVertexWeight modifier vertex index
                        if slot > 0 then actual[slot] += value
                        else if (abs value) > 0.0001 do throw "Skin added an unexpected bone influence."
                    )
                    for index = 1 to actual.count do
                        if (abs (actual[index] - weights[index])) > 0.0001 do throw "Skin did not preserve the source bone weights."
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
fn MLMdlFrameOrder frameNodes =
(
    local parents = #()
    for index = 1 to frameNodes.count do
    (
        local node = frameNodes[index]
        if (findItem frameNodes node) != index do throw "The MDL frame selection contains a duplicate node."
        local ancestor = node.parent
        local parentIndex = 0
        while ancestor != undefined and parentIndex == 0 do
        (
            parentIndex = findItem frameNodes ancestor
            ancestor = ancestor.parent
        )
        append parents parentIndex
    )
    local pending = #()
    for index = frameNodes.count to 1 by -1 where parents[index] == 0 do append pending index
    local order = #()
    while pending.count > 0 do
    (
        local index = pending[pending.count]
        deleteItem pending pending.count
        append order index
        for child = frameNodes.count to 1 by -1 where parents[child] == index do append pending child
    )
    if order.count != frameNodes.count do throw "The MDL frame hierarchy contains a cycle."
    order
)

fn MLMdlOrderTriangles triangles materialCount =
(
    local buckets = for slot = 1 to materialCount collect #()
    for triangle in triangles do
    (
        local slot = triangle[1]
        if slot < 1 or slot > materialCount do throw "A face references an invalid material slot."
        append buckets[slot] triangle
    )
    local ordered = #()
    for bucket in buckets do join ordered bucket
    ordered
)

fn MLGatherExportGeometry nodes =
(
    local triangles = #()
    local materials = #()
    local materialNodes = #()
    local snapshots = #()
    local referenceRoot = undefined
    local rootCount = 0
    local frameNodes = #()
    local hasSkin = false
    local hasRigid = false
    try
    (
        for node in nodes where (MLUserFlag node "MaxLeedsRoot") do
        (
            referenceRoot = node
            rootCount += 1
        )
        if rootCount > 1 do throw "Select one model root for MDL export."
        local rootInverse = if referenceRoot != undefined then inverse referenceRoot.transform else matrix3 1
        for node in nodes where isValidNode node do
        (
            if (getUserProp node "MaxLeedsFrame") != undefined or (classof node) == BoneGeometry do append frameNodes node
        )
        for node in nodes where (superclassof node) == GeometryClass and (classof node) != BoneGeometry do
        (
            local skinModifier = undefined
            for modifier in node.modifiers where (classof modifier) == Skin do skinModifier = modifier
            if skinModifier != undefined then hasSkin = true else hasRigid = true
            if skinModifier == undefined do
            (
                local ancestor = node.parent
                local originalFrame = false
                while ancestor != undefined and not originalFrame do
                (
                    if (getUserProp ancestor "MaxLeedsFrame") != undefined do originalFrame = true
                    ancestor = ancestor.parent
                )
                if not originalFrame and (findItem frameNodes node) == 0 do append frameNodes node
            )
            if skinModifier != undefined and frameNodes.count == 0 do throw "The selected skinned mesh has no bone hierarchy."
            local snapshot = MLSnapshotWithoutSkin node
            append snapshots snapshot
            if skinModifier != undefined and (skinOps.GetNumberVertices skinModifier) != snapshot.numverts do throw "A modifier above Skin changed vertex topology. Move topology edits below Skin before exporting MDL."
            local objectMatrix = node.objectTransform * rootInverse
            local inverseMatrix = inverse objectMatrix
            local normalMatrix = matrix3 [inverseMatrix.row1.x,inverseMatrix.row2.x,inverseMatrix.row3.x] [inverseMatrix.row1.y,inverseMatrix.row2.y,inverseMatrix.row3.y] [inverseMatrix.row1.z,inverseMatrix.row2.z,inverseMatrix.row3.z] [0,0,0]
            for faceIndex = 1 to snapshot.numfaces do
            (
                local face = getFace snapshot faceIndex
                local materialID = getFaceMatID snapshot faceIndex
                local material = node.material
                if (classof material) == MultiMaterial do
                (
                    local slots = for index = 1 to material.materialIDList.count where material.materialIDList[index] == materialID collect index
                    if slots.count != 1 do throw "Each used MDL face material ID must resolve to one Multi/Sub-Object slot."
                    material = material.materialList[slots[1]]
                )
                local slot = findItem materialNodes material
                if slot == 0 do
                (
                    append materialNodes material
                    local name = if material != undefined then material.name else "default"
                    if material != undefined and isProperty material #diffuseMap and material.diffuseMap != undefined and isProperty material.diffuseMap #filename do name = getFilenameFile material.diffuseMap.filename
                    if name.count > 31 do throw ("Texture name exceeds 31 characters: " + name)
                    local rgba = if material != undefined then copy material.diffuse else color 255 255 255 255
                    rgba.a = if material != undefined then material.opacity * 255.0 / 100.0 else 255
                    append materials (MLMaterial name:name rgba:rgba)
                    slot = materials.count
                )
                local uvFace = if meshop.getMapSupport snapshot 1 then meshop.getMapFace snapshot 1 faceIndex else [0,0,0]
                local colorFace = if meshop.getMapSupport snapshot 0 then meshop.getMapFace snapshot 0 faceIndex else [0,0,0]
                local alphaFace = if meshop.getMapSupport snapshot -2 then meshop.getMapFace snapshot -2 faceIndex else [0,0,0]
                local faceNormals = meshop.getFaceRNormals snapshot faceIndex
                local corners = #()
                for corner = 1 to 3 do
                (
                    local point = (getVert snapshot (face[corner] as integer)) * objectMatrix
                    local uv = if uvFace[corner] > 0 then meshop.getMapVert snapshot 1 (uvFace[corner] as integer) else [0,0,0]
                    local rgba = color 255 255 255 255
                    if colorFace[corner] > 0 do
                    (
                        local value = meshop.getMapVert snapshot 0 (colorFace[corner] as integer)
                        rgba = color (value.x * 255) (value.y * 255) (value.z * 255) 255
                    )
                    if alphaFace[corner] > 0 do rgba.a = (meshop.getMapVert snapshot -2 (alphaFace[corner] as integer)).x * 255
                    local normal = normalize (faceNormals[corner] * normalMatrix)
                    local influences = #()
                    if skinModifier != undefined do
                    (
                        local vertexID = face[corner] as integer
                        for weightIndex = 1 to (skinOps.GetVertexWeightCount skinModifier vertexID) do
                        (
                            local weight = skinOps.GetVertexWeight skinModifier vertexID weightIndex
                            if weight > 0 do
                            (
                                local boneID = skinOps.GetVertexWeightBoneID skinModifier vertexID weightIndex
                                local boneName = skinOps.GetBoneName skinModifier boneID 0
                                local frameID = 0
                                for frameIndex = 1 to frameNodes.count where frameNodes[frameIndex].name == boneName do
                                (
                                    if frameID != 0 do throw ("MDL Skin bone name is ambiguous: " + boneName)
                                    frameID = frameIndex
                                )
                                if frameID == 0 do throw ("Skin bone " + boneName + " is outside the selected model hierarchy.")
                                append influences #(frameID, weight)
                            )
                        )
                        if influences.count == 0 do throw ("Mesh " + node.name + " has an unweighted vertex " + vertexID as string)
                        if influences.count > 4 do
                        (
                            qsort influences MLWeightGreater
                            while influences.count > 4 do deleteItem influences influences.count
                        )
                        local total = 0.0
                        for influence in influences do total += influence[2]
                        if total <= 0 do throw "A skin vertex has zero weight."
                        for influence in influences do influence[2] /= total
                    )
                    append corners #(point,uv,rgba,normal,influences)
                )
                if (dot (cross objectMatrix.row1 objectMatrix.row2) objectMatrix.row3) < 0 do
                (
                    local swapped = corners[2]
                    corners[2] = corners[3]
                    corners[3] = swapped
                )
                append triangles #(slot,corners,node,(skinModifier != undefined))
            )
        )
        for snapshot in snapshots do free snapshot
        snapshots = #()
        if triangles.count == 0 do throw "The selection contains no exportable mesh faces."
        if hasSkin and frameNodes.count > 254 do throw "The MDL frame table supports at most 254 exported hierarchy frames."
        if materials.count > 2048 do throw "The material count exceeds the MDL limit."
        local frameOrder = MLMdlFrameOrder frameNodes
        local frameRemap = for index = 1 to frameNodes.count collect 0
        for index = 1 to frameOrder.count do frameRemap[frameOrder[index]] = index
        for triangle in triangles do for corner in triangle[2] do for influence in corner[5] do
            influence[1] = frameRemap[influence[1]]
        frameNodes = for index in frameOrder collect frameNodes[index]
        local ordered = MLMdlOrderTriangles triangles materials.count
        #(ordered, materials, frameNodes, hasSkin, rootInverse, hasRigid)
    )
    catch
    (
        for snapshot in snapshots do free snapshot
        throw()
    )
)

fn MLExportRigidFrame objectNode frameNodes =
(
    local ancestor = objectNode.parent
    while ancestor != undefined do
    (
        if (findItem frameNodes ancestor) != 0 and (getUserProp ancestor "MaxLeedsFrame") != undefined do return ancestor
        ancestor = ancestor.parent
    )
    objectNode
)

fn MLTrianglePalette triangle maximumBones =
(
    local palette = #()
    for corner in triangle[2] do for influence in corner[5] do
    (
        if (findItem palette influence[1]) == 0 do append palette influence[1]
    )
    if palette.count > maximumBones do throw "A triangle contains more bone influences than this platform can address."
    palette
)

fn MLCornerEqual first second =
(
    if distance first[1] second[1] > 0.000001 do return false
    if distance first[2] second[2] > 0.000001 do return false
    if distance first[4] second[4] > 0.000001 do return false
    local left = first[3]
    local right = second[3]
    if (abs (left.r - right.r)) > 0.01 or (abs (left.g - right.g)) > 0.01 or (abs (left.b - right.b)) > 0.01 or (abs (left.a - right.a)) > 0.01 do return false
    if first[5].count != second[5].count do return false
    for index = 1 to first[5].count do
    (
        if first[5][index][1] != second[5][index][1] or (abs (first[5][index][2] - second[5][index][2])) > 0.000001 do return false
    )
    true
)

fn MLBuildModelStrips triangles skinned maximumVertices paletteLimit =
(
    local used = for index = 1 to triangles.count collect false
    local strips = #()
    for startIndex = 1 to triangles.count where not used[startIndex] do
    (
        local source = triangles[startIndex]
        local vertices = copy source[2]
        local palette = if skinned then MLTrianglePalette source paletteLimit else #()
        used[startIndex] = true
        local extended = true
        while extended and vertices.count < maximumVertices do
        (
            extended = false
            local nextVertex = vertices.count + 1
            local requiredFirst = if (mod nextVertex 2) == 1 then vertices[vertices.count - 1] else vertices[vertices.count]
            local requiredSecond = if (mod nextVertex 2) == 1 then vertices[vertices.count] else vertices[vertices.count - 1]
            for candidateIndex = startIndex + 1 to (amin triangles.count (startIndex + 512)) while not extended do
            (
                if not used[candidateIndex] and triangles[candidateIndex][1] == source[1] do
                (
                    local candidate = triangles[candidateIndex][2]
                    for rotation = 1 to 3 while not extended do
                    (
                        local first = candidate[rotation]
                        local second = candidate[(mod rotation 3) + 1]
                        local third = candidate[(mod (rotation + 1) 3) + 1]
                        if (MLCornerEqual first requiredFirst) and (MLCornerEqual second requiredSecond) do
                        (
                            local nextPalette = copy palette
                            if skinned do
                            (
                                for influence in third[5] where (findItem nextPalette influence[1]) == 0 do append nextPalette influence[1]
                            )
                            if nextPalette.count <= paletteLimit do
                            (
                                append vertices third
                                palette = nextPalette
                                used[candidateIndex] = true
                                extended = true
                            )
                        )
                    )
                )
            )
        )
        append strips #(source[1], vertices, palette)
    )
    strips
)

fn MLPspWeightBytes influences palette =
(
    local bytes = for index = 1 to 8 collect 0
    local largest = 0
    local total = 0
    for influence in influences do
    (
        local channel = findItem palette influence[1]
        if channel == 0 do throw "A skin influence is absent from the triangle bone palette."
        bytes[channel] = amin 128 (amax 0 ((influence[2] * 128.0 + 0.5) as integer))
        total += bytes[channel]
        if largest == 0 or bytes[channel] > bytes[largest] do largest = channel
    )
    if largest == 0 do throw "A skin vertex has no bone weights."
    bytes[largest] += (128 - total)
    if bytes[largest] < 0 or bytes[largest] > 128 do throw "A skin weight could not be encoded."
    bytes
)

fn MLResolveMdlBoneIDs frameNodes =
(
    local ids = for node in frameNodes collect -1
    local reserved = #()
    for index = 1 to frameNodes.count do
    (
        local property = getUserProp frameNodes[index] "MaxLeedsBoneID"
        if property != undefined do
        (
            local value = property as integer
            if value == undefined or value < -1 or value > 255 do throw "MDL bone IDs must be integers from -1 through 255."
            if value >= 0 do
            (
                if (findItem reserved value) != 0 do throw "Two MDL bones have the same animation ID."
                append reserved value
                ids[index] = value
            )
        )
    )
    for index = 1 to frameNodes.count where ids[index] < 0 and (classof frameNodes[index]) == BoneGeometry do
    (
        local available = 0
        while available <= 255 and (findItem reserved available) != 0 do available += 1
        if available > 255 do throw "There are no unused MDL animation bone IDs."
        ids[index] = available
        append reserved available
    )
    ids
)

fn MLWriteSkeleton writer rootFrame frameNodes rootInverse platform game requireBones =
(
    if frameNodes.count < 1 do throw "A skinned export needs at least one bone."
    local frameOrder = MLMdlFrameOrder frameNodes
    for index = 1 to frameOrder.count do if frameOrder[index] != index do throw "MDL frames must be gathered in hierarchy traversal order before serialization."
    local boneIDs = MLResolveMdlBoneIDs frameNodes
    local framePointers = #()
    local parents = #()
    for node in frameNodes do
    (
        writer.align 16
        append framePointers (writer.tell())
        writer.zeros 0xAC
        local ancestor = node.parent
        local frameParent = 0
        while ancestor != undefined and frameParent == 0 do
        (
            frameParent = findItem frameNodes ancestor
            ancestor = ancestor.parent
        )
        append parents frameParent
    )
    local framesEnd = writer.tell()
    local nameOffset = if platform == "PSP" or game == "VCS" then 0xA8 else 0xA4
    for index = 1 to frameNodes.count do
    (
        local node = frameNodes[index]
        local pointer = framePointers[index]
        local world = node.transform * rootInverse
        local parentPointer = if parents[index] == 0 then rootFrame else framePointers[parents[index]]
        local parentWorld = if parents[index] == 0 then (matrix3 1) else (frameNodes[parents[index]].transform * rootInverse)
        writer.pointer (pointer + 4) parentPointer
        writer.seek (pointer + 0x10)
        writer.matrix (world * inverse parentWorld)
        writer.matrix world
    )
    for parentIndex = 0 to frameNodes.count do
    (
        local first = 0
        local previous = 0
        for childIndex = 1 to frameNodes.count where parents[childIndex] == parentIndex do
        (
            if first == 0 then first = childIndex
            else writer.pointer (framePointers[previous] + 0x94) framePointers[childIndex]
            previous = childIndex
        )
        if first != 0 do writer.pointer ((if parentIndex == 0 then rootFrame else framePointers[parentIndex]) + 0x90) framePointers[first]
    )
    writer.seek framesEnd
    for index = 1 to frameNodes.count do
    (
        local frameName = getUserProp frameNodes[index] "MaxLeedsFrameName"
        if frameName == undefined or frameName == "" do frameName = frameNodes[index].name
        if frameName.count > 127 do throw "A bone name is longer than 127 characters."
        local namePointer = writer.tell()
        writer.text frameName
        writer.pointer (framePointers[index] + nameOffset) namePointer
    )
    local boneCount = 0
    for id in boneIDs where id >= 0 do boneCount += 1
    if boneCount == 0 and not requireBones do return #(0, framePointers)
    if boneCount == 0 do throw "No real animation bones were found in the hierarchy."
    writer.align 16
    local hierarchy = writer.tell()
    writer.zeros 0x38
    local table = writer.tell()
    local bones = 0
    for index = 1 to frameNodes.count do
    (
        local boneID = boneIDs[index]
        if boneID >= 0 do
        (
            writer.long (bit.or (bit.shift index 8) boneID)
            writer.long 0
            bones += 1
        )
    )
    writer.patchLong hierarchy 0x3000
    writer.patchLong (hierarchy + 4) bones
    writer.pointer (hierarchy + 0x30) table
    writer.pointer (hierarchy + 0x34) rootFrame
    #(hierarchy, framePointers)
)

fn MLMdlSameGroup first second =
(
    if first == second do return true
    if not isValidNode first or not isValidNode second do return false
    local firstAtomic = getUserProp first "MaxLeedsAtomic"
    local secondAtomic = getUserProp second "MaxLeedsAtomic"
    if firstAtomic == undefined or secondAtomic == undefined do return false
    local firstValue = firstAtomic as integer
    local secondValue = secondAtomic as integer
    firstValue != undefined and firstValue > 0 and firstValue == secondValue
)

fn MLMdlObjectGroups triangles =
(
    local groups = #()
    local skinFlags = #()
    for triangle in triangles do
    (
        local groupIndex = 0
        for index = 1 to groups.count while groupIndex == 0 do
            if MLMdlSameGroup triangle[3] groups[index] do groupIndex = index
        if groupIndex == 0 then
        (
            append groups triangle[3]
            append skinFlags triangle[4]
        )
        else if skinFlags[groupIndex] != triangle[4] do
            throw ("One MDL object contains both skinned and rigid faces: " + groups[groupIndex].name)
    )
    groups
)

fn MLMdlRigidLocalGeometry triangles frameNodes rootInverse =
(
    local original = #(triangles, 0)
    if triangles.count == 0 do return original
    if triangles[1][4] do return original
    local rigidFrame = MLExportRigidFrame triangles[1][3] frameNodes
    local frameIndex = findItem frameNodes rigidFrame
    if frameIndex == 0 do return original
    if (getUserProp rigidFrame "MaxLeedsFrame") == undefined and (classof rigidFrame) != BoneGeometry do return original
    for triangle in triangles do
    (
        if triangle[4] do throw "Rigid and skinned faces cannot share a Stories atomic."
        local candidate = MLExportRigidFrame triangle[3] frameNodes
        if candidate != rigidFrame do throw "A Stories atomic has mesh parts attached to different frames."
    )
    local frameWorld = rigidFrame.transform * rootInverse
    local localMatrix = inverse frameWorld
    local normalMatrix = matrix3 [frameWorld.row1.x,frameWorld.row2.x,frameWorld.row3.x] [frameWorld.row1.y,frameWorld.row2.y,frameWorld.row3.y] [frameWorld.row1.z,frameWorld.row2.z,frameWorld.row3.z] [0,0,0]
    local localTriangles = #()
    for triangle in triangles do
    (
        local corners = #()
        for corner in triangle[2] do
        (
            local localPoint = corner[1] * localMatrix
            local localNormal = normalize (corner[4] * normalMatrix)
            append corners #(localPoint, corner[2], corner[3], localNormal, corner[5])
        )
        append localTriangles #(triangle[1],corners,triangle[3],false)
    )
    #(localTriangles,frameIndex)
)

fn MLValidateStoriesExport path game platform triangleCount atomicCount modelID expectedSkin =
(
    local model = MLReadModel path game platform
    local actualTriangles = 0
    local actualAtomics = #()
    local actualSkin = false
    for part in model.parts do
    (
        actualTriangles += part.faces.count
        if part.weights.count > 0 then
        (
            actualSkin = true
            if part.weights.count != part.vertices.count do throw "The saved MDL has incomplete bone weights."
            for influences in part.weights do
            (
                local total = 0.0
                for influence in influences do total += influence[2]
                if total < 0.95 or total > 1.05 do throw "The saved MDL has invalid bone weights."
            )
        )
        if (findItem actualAtomics part.atomicPointer) == 0 do append actualAtomics part.atomicPointer
        if part.vertices.count < 3 do throw "The saved MDL contains an empty geometry part."
        for face in part.faces do
            for corner = 1 to 3 do
                if face[corner] < 1 or face[corner] > part.vertices.count do
                    throw "The saved MDL contains a face outside its vertex buffer."
    )
    if actualTriangles != triangleCount do
        throw ("The saved MDL has " + actualTriangles as string + " faces, expected " + triangleCount as string + ".")
    if actualAtomics.count != atomicCount do
        throw ("The saved MDL has " + actualAtomics.count as string + " objects, expected " + atomicCount as string + ".")
    if model.modelID != modelID do throw "The saved MDL model ID does not match the selected ID."
    if actualSkin != expectedSkin do throw "The saved MDL changed the model skinning."
    if model.parts.count == 0 or model.materials.count == 0 do
        throw "The saved MDL has no readable geometry or materials."
    true
)

fn MLWritePspObject destination nodes game modelID =
(
    if modelID < 0 or modelID > 65534 do throw "Enter the game's model ID, or import its original model first."
    local collected = MLGatherExportGeometry nodes
    local objectNodes = MLMdlObjectGroups collected[1]
    if objectNodes.count > 1 do return MLWriteClumpModel destination collected game modelID "PSP"
    local writer = MLWriter()
    local temporary = MLTemporaryFile destination
    try
    (
        local exportData = collected
        local triangles = exportData[1]
        local materials = exportData[2]
        local frameNodes = exportData[3]
        local skinned = exportData[4]
        local rootInverse = exportData[5]
        local rigidGeometry = MLMdlRigidLocalGeometry triangles frameNodes rootInverse
        triangles = rigidGeometry[1]
        local rigidFrameIndex = rigidGeometry[2]
        local strips = MLBuildModelStrips triangles skinned 255 8
        if strips.count < 1 or strips.count > 4096 do throw "PSP MDL allows at most 4096 strips per geometry. Divide this object."
        local vertexCount = 0
        for strip in strips do vertexCount += strip[2].count
        if vertexCount > 1000000 do throw "The PSP geometry exceeds one million strip vertices."
        writer.openFile temporary
        writer.zeros 0x30
        local frame = writer.tell()
        writer.zeros 0xAC
        writer.align 16
        local geometry = writer.tell()
        writer.zeros 0x20
        local header = writer.tell()
        writer.zeros (0x48 + strips.count * 0x30)
        writer.align 4
        local verticesPointer = writer.tell()
        for strip in strips do for corner in strip[2] do
        (
            if skinned do
            (
                local weightBytes = MLPspWeightBytes corner[5] strip[3]
                for weightByte in weightBytes do writer.byte weightByte
            )
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
        writer.patchLong (header + 4) (if skinned then 0x1C3FF else 0x1FF)
        writer.patchLong (header + 8) strips.count
        writer.seek (header + 0x20)
        writer.point [1,1,1]
        writer.long vertexCount
        writer.point [0,0,0]
        writer.long 0
        writer.long (verticesPointer - header)
        writer.float 0
        local vertexOffset = 0
        for index = 1 to strips.count do
        (
            writer.seek (header + 0x48 + (index - 1) * 0x30)
            writer.long (vertexOffset * (if skinned then 44 else 36))
            writer.short (strips[index][2].count - 2)
            writer.short (strips[index][1] - 1)
            writer.float 0; writer.float 1; writer.float 1
            local corners = strips[index][2]
            local minU = corners[1][2].x
            local maxU = minU
            local minV = corners[1][2].y
            local maxV = minV
            for corner in corners do
            (
                minU = amin minU corner[2].x
                maxU = amax maxU corner[2].x
                minV = amin minV corner[2].y
                maxV = amax maxV corner[2].y
            )
            writer.float minU
            writer.float (1.0 - maxV)
            writer.float maxU
            writer.float (1.0 - minV)
            writer.float 0
            if skinned then
            (
                for boneIndex = 1 to 8 do writer.byte (if boneIndex <= strips[index][3].count then strips[index][3][boneIndex] else 0)
            )
            else writer.zeros 8
            vertexOffset += corners.count
        )
        writer.seek end
        writer.patchLong atomic (MLMdlAtomicTag game "PSP")
        writer.pointer (atomic + 20) geometry
        writer.seek (atomic + 40)
        writer.short modelID; writer.short 0
        writer.seek end
        local attachedFrame = frame
        if skinned then
        (
            local skeleton = MLWriteSkeleton writer frame frameNodes rootInverse "PSP" game true
            writer.pointer (atomic + 44) skeleton[1]
        )
        else if rigidFrameIndex > 0 do
        (
            local skeleton = MLWriteSkeleton writer frame frameNodes rootInverse "PSP" game false
            attachedFrame = skeleton[2][rigidFrameIndex]
        )
        writer.pointer (attachedFrame + 8) (atomic + 8)
        writer.pointer (attachedFrame + 12) (atomic + 8)
        writer.pointer (atomic + 4) attachedFrame
        writer.pointer (atomic + 8) (attachedFrame + 8)
        writer.pointer (atomic + 12) (attachedFrame + 8)
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
        MLValidateStoriesExport temporary game "PSP" triangles.count 1 modelID skinned
        MLFinishFile temporary destination
        triangles.count
    )
    catch
    (
        local reason = getCurrentException()
        writer.closeFile()
        if doesFileExist temporary do deleteFile temporary
        throw()
    )
)

fn MLPs2Byte value = (amin 255 (amax 0 ((value + 0.5) as integer)))
fn MLPs2SignedByte value = (amin 127 (amax -127 ((value + (if value >= 0 then 0.5 else -0.5)) as integer)))
fn MLPs2SignedShort value = (amin 32767 (amax -32767 ((value + (if value >= 0 then 0.5 else -0.5)) as integer)))

fn MLWritePs2Strip writer strip scale skinned =
(
    local corners = strip[2]
    local count = corners.count
    local uvMax = [0,0,0]
    local signedUV = false
    for corner in corners do
    (
        uvMax.x = amax uvMax.x (abs corner[2].x)
        uvMax.y = amax uvMax.y (abs (1.0 - corner[2].y))
        if corner[2].x < 0 or corner[2].y > 1.0 do signedUV = true
    )
    local range = if signedUV then (127.0 / 127.5) else 2.0
    local uvScale = [amax 0.5 (uvMax.x / range), amax 0.5 (uvMax.y / range), 1]
    local packetStart = writer.tell()
    writer.zeros 16
    writer.long (bit.or 0x79000000 (bit.shift count 16))
    for corner in corners do
    (
        writer.signedShort (MLPs2SignedShort (corner[1].x / scale.x * 32768.0))
        writer.signedShort (MLPs2SignedShort (corner[1].y / scale.y * 32768.0))
        writer.signedShort (MLPs2SignedShort (corner[1].z / scale.z * 32768.0))
    )
    writer.align 4
    writer.long (bit.or (if signedUV then 0x76000000 else 0x76004000) (bit.shift count 16))
    for corner in corners do
    (
        local u = corner[2].x / uvScale.x * 127.5
        local v = (1.0 - corner[2].y) / uvScale.y * 127.5
        if signedUV then
        (
            writer.signedByte (MLPs2SignedByte u)
            writer.signedByte (MLPs2SignedByte v)
        )
        else
        (
            writer.byte (MLPs2Byte u)
            writer.byte (MLPs2Byte v)
        )
    )
    writer.align 4
    writer.long (bit.or 0x6F000000 (bit.shift count 16))
    for corner in corners do
    (
        local c = corner[3]
        local r = MLPs2Byte (c.r * 31.0 / 255.0)
        local g = MLPs2Byte (c.g * 31.0 / 255.0)
        local b = MLPs2Byte (c.b * 31.0 / 255.0)
        writer.short (bit.or r (bit.or (bit.shift g 5) (bit.or (bit.shift b 10) (if c.a >= 128 then 0x8000 else 0))))
    )
    writer.align 4
    writer.long (bit.or 0x6A000000 (bit.shift count 16))
    for corner in corners do
    (
        local n = corner[4]
        writer.signedByte (MLPs2SignedByte (n.x * 127.0))
        writer.signedByte (MLPs2SignedByte (n.y * 127.0))
        writer.signedByte (MLPs2SignedByte (n.z * 127.0))
    )
    writer.align 4
    if skinned do
    (
        writer.long (bit.or 0x6C00007F (bit.shift count 16))
        for corner in corners do
        (
            for influenceIndex = 1 to 4 do
            (
                if influenceIndex <= corner[5].count then
                (
                    local influence = corner[5][influenceIndex]
                    if influence[1] > 63 do throw "PS2 bone offsets can address at most 63 exported hierarchy frames."
                    local packedWeight = bit.and (bit.floatAsInt influence[2]) (bit.not 255)
                    writer.long (bit.or packedWeight (influence[1] * 4))
                )
                else writer.long 0
            )
        )
    )
    writer.long 0x14000000
    writer.align 16
    local packetEnd = writer.tell()
    writer.patchLong packetStart (bit.or 0x60000000 (((packetEnd - packetStart - 16) / 16) as integer))
    #(packetStart, packetEnd, uvScale)
)

fn MLWritePs2Object destination nodes game modelID =
(
    if modelID < 0 or modelID > 65534 do throw "Enter the game's model ID, or import its original model first."
    local data = MLGatherExportGeometry nodes
    local objectNodes = MLMdlObjectGroups data[1]
    if objectNodes.count > 1 do return MLWriteClumpModel destination data game modelID "PS2"
    local triangles = data[1]
    local materials = data[2]
    local frameNodes = data[3]
    local skinned = data[4]
    local rootInverse = data[5]
    local rigidGeometry = MLMdlRigidLocalGeometry triangles frameNodes rootInverse
    triangles = rigidGeometry[1]
    local rigidFrameIndex = rigidGeometry[2]
    local strips = MLBuildModelStrips triangles skinned 255 63
    if strips.count > 512 do throw "PS2 MDL geometry supports at most 512 strips. Divide this object."
    if skinned and frameNodes.count > 63 do throw "PS2 skin offsets support up to 63 hierarchy frames in this writer."
    local writer = MLWriter()
    local temporary = MLTemporaryFile destination
    try
    (
        local scale = [0.0001,0.0001,0.0001]
        local minimum = copy triangles[1][2][1][1]
        local maximum = copy minimum
        for triangle in triangles do for corner in triangle[2] do for axis = 1 to 3 do
        (
            minimum[axis] = amin minimum[axis] corner[1][axis]
            maximum[axis] = amax maximum[axis] corner[1][axis]
            scale[axis] = amax scale[axis] ((abs corner[1][axis]) * 1.0001)
        )
        local center = (minimum + maximum) / 2.0
        local radius = 0.0
        for triangle in triangles do for corner in triangle[2] do radius = amax radius (distance center corner[1])
        writer.openFile temporary
        writer.zeros 0x30
        local frame = writer.tell()
        writer.zeros 0xAC
        writer.align 16
        local geometry = writer.tell()
        writer.zeros 0x20
        local header = writer.tell()
        local firstPacket = MLAlign (0x40 + strips.count * 0x30) 16
        writer.zeros firstPacket
        local packetRecords = #()
        for strip in strips do append packetRecords (MLWritePs2Strip writer strip scale skinned)
        local geometryEnd = writer.tell()
        if geometryEnd - header > 0xFFFFF do throw "PS2 geometry exceeds the 20-bit packet size limit."
        local materialPointers = #()
        for description in materials do
        (
            writer.align 4
            append materialPointers (writer.tell())
            writer.long 0
            local rgba = description.rgba
            writer.long (bit.or (rgba.r as integer) (bit.or (bit.shift (rgba.g as integer) 8) (bit.or (bit.shift (rgba.b as integer) 16) (bit.shift (rgba.a as integer) 24))))
            writer.long 2
            writer.long 0
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
        writer.pointer (frame + 0x98) frame
        writer.pointer (frame + (if game == "LCS" then 0xA4 else 0xA8)) frameName
        writer.patchLong geometry 8
        writer.patchLong (geometry + 8) 1
        writer.pointer (geometry + 12) materialTable
        writer.patchLong (geometry + 16) materials.count
        writer.patchLong (geometry + 20) materials.count
        writer.patchLong (header + 0x10) (bit.or (bit.shift strips.count 20) (geometryEnd - header))
        writer.seek (header + 0x1A)
        writer.short firstPacket
        writer.seek (header + 0x28)
        writer.point scale
        writer.seek (header + 0x34)
        writer.point [0,0,0]
        for index = 1 to strips.count do
        (
            local descriptor = header + 0x40 + (index - 1) * 0x30
            writer.patchLong (descriptor + 0x1C) (packetRecords[index][1] - header - firstPacket)
            writer.seek (descriptor + 0x10)
            writer.float packetRecords[index][3].x
            writer.float packetRecords[index][3].y
            writer.seek (descriptor + 0x22)
            writer.short (strips[index][1] - 1)
        )
        writer.seek end
        writer.patchLong atomic (MLMdlAtomicTag game "PS2")
        writer.pointer (atomic + 20) geometry
        writer.seek (atomic + 40)
        writer.short modelID
        writer.short 0
        writer.seek end
        local attachedFrame = frame
        if skinned then
        (
            local skeleton = MLWriteSkeleton writer frame frameNodes rootInverse "PS2" game true
            writer.pointer (atomic + 44) skeleton[1]
        )
        else if rigidFrameIndex > 0 do
        (
            local skeleton = MLWriteSkeleton writer frame frameNodes rootInverse "PS2" game false
            attachedFrame = skeleton[2][rigidFrameIndex]
        )
        writer.pointer (attachedFrame + 8) (atomic + 8)
        writer.pointer (attachedFrame + 12) (atomic + 8)
        writer.pointer (atomic + 4) attachedFrame
        writer.pointer (atomic + 8) (attachedFrame + 8)
        writer.pointer (atomic + 12) (attachedFrame + 8)
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
        MLValidateStoriesExport temporary game "PS2" triangles.count 1 modelID skinned
        MLFinishFile temporary destination
        triangles.count
    )
    catch
    (
        writer.closeFile()
        if doesFileExist temporary do deleteFile temporary
        throw()
    )
)

fn MLWriteMaterialsBlock writer geometry materials =
(
    local pointers = #()
    for material in materials do
    (
        writer.align 4
        append pointers (writer.tell())
        writer.long 0
        local rgba = material.rgba
        writer.long (bit.or (rgba.r as integer) (bit.or (bit.shift (rgba.g as integer) 8) (bit.or (bit.shift (rgba.b as integer) 16) (bit.shift (rgba.a as integer) 24))))
        writer.long 2
        writer.long 0
    )
    local table = writer.tell()
    for pointer in pointers do
    (
        local field = writer.tell()
        writer.long pointer
        append writer.relocations field
    )
    writer.patchLong geometry 8
    writer.patchLong (geometry + 8) 1
    writer.pointer (geometry + 12) table
    writer.patchLong (geometry + 16) materials.count
    writer.patchLong (geometry + 20) materials.count
    pointers
)

fn MLWritePspGeometryBlock writer triangles materials skinned =
(
    local strips = MLBuildModelStrips triangles skinned 255 8
    if strips.count < 1 or strips.count > 4096 do throw "PSP geometry exceeds 4096 strips."
    local vertexCount = 0
    for strip in strips do vertexCount += strip[2].count
    if vertexCount > 1000000 do throw "PSP geometry exceeds one million vertices."
    writer.align 16
    local geometry = writer.tell()
    writer.zeros 0x20
    local header = writer.tell()
    writer.zeros (0x48 + strips.count * 0x30)
    writer.align 4
    local vertexStart = writer.tell()
    for strip in strips do for corner in strip[2] do
    (
        if skinned do
        (
            local weightBytes = MLPspWeightBytes corner[5] strip[3]
            for value in weightBytes do writer.byte value
        )
        writer.float corner[2].x
        writer.float (1.0 - corner[2].y)
        local rgba = corner[3]
        writer.byte (rgba.r as integer)
        writer.byte (rgba.g as integer)
        writer.byte (rgba.b as integer)
        writer.byte (rgba.a as integer)
        writer.point corner[4]
        writer.point corner[1]
    )
    local geometryEnd = writer.tell()
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
    writer.seek (header + 0x10)
    writer.point center
    writer.float radius
    writer.patchLong header (geometryEnd - header)
    writer.patchLong (header + 4) (if skinned then 0x1C3FF else 0x1FF)
    writer.patchLong (header + 8) strips.count
    writer.seek (header + 0x20)
    writer.point [1,1,1]
    writer.long vertexCount
    writer.point [0,0,0]
    writer.long 0
    writer.long (vertexStart - header)
    writer.float 0
    local vertexOffset = 0
    for index = 1 to strips.count do
    (
        local descriptor = header + 0x48 + (index - 1) * 0x30
        writer.seek descriptor
        writer.long (vertexOffset * (if skinned then 44 else 36))
        writer.short (strips[index][2].count - 2)
        writer.short (strips[index][1] - 1)
        writer.float 0
        writer.float 1
        writer.float 1
        local corners = strips[index][2]
        local minU = corners[1][2].x
        local maxU = minU
        local minV = corners[1][2].y
        local maxV = minV
        for corner in corners do
        (
            minU = amin minU corner[2].x
            maxU = amax maxU corner[2].x
            minV = amin minV corner[2].y
            maxV = amax maxV corner[2].y
        )
        writer.float minU
        writer.float (1.0 - maxV)
        writer.float maxU
        writer.float (1.0 - minV)
        writer.float 0
        if skinned then
        (
            for boneIndex = 1 to 8 do writer.byte (if boneIndex <= strips[index][3].count then strips[index][3][boneIndex] else 0)
        )
        else writer.zeros 8
        vertexOffset += corners.count
    )
    writer.seek geometryEnd
    local materialPointers = MLWriteMaterialsBlock writer geometry materials
    #(geometry, materialPointers)
)

fn MLWritePs2GeometryBlock writer triangles materials skinned =
(
    local strips = MLBuildModelStrips triangles skinned 255 63
    if strips.count < 1 or strips.count > 512 do throw "PS2 geometry exceeds 512 strips."
    local scale = [0.0001,0.0001,0.0001]
    for triangle in triangles do for corner in triangle[2] do for axis = 1 to 3 do
        scale[axis] = amax scale[axis] ((abs corner[1][axis]) * 1.0001)
    writer.align 16
    local geometry = writer.tell()
    writer.zeros 0x20
    local header = writer.tell()
    local firstPacket = MLAlign (0x40 + strips.count * 0x30) 16
    writer.zeros firstPacket
    local packets = #()
    for strip in strips do append packets (MLWritePs2Strip writer strip scale skinned)
    local geometryEnd = writer.tell()
    if geometryEnd - header > 0xFFFFF do throw "PS2 geometry exceeds the 20-bit packet size limit."
    writer.patchLong (header + 0x10) (bit.or (bit.shift strips.count 20) (geometryEnd - header))
    writer.seek (header + 0x1A)
    writer.short firstPacket
    writer.seek (header + 0x28)
    writer.point scale
    writer.seek (header + 0x34)
    writer.point [0,0,0]
    for index = 1 to strips.count do
    (
        local descriptor = header + 0x40 + (index - 1) * 0x30
        writer.patchLong (descriptor + 0x1C) (packets[index][1] - header - firstPacket)
        writer.seek (descriptor + 0x10)
        writer.float packets[index][3].x
        writer.float packets[index][3].y
        writer.seek (descriptor + 0x22)
        writer.short (strips[index][1] - 1)
    )
    writer.seek geometryEnd
    local materialPointers = MLWriteMaterialsBlock writer geometry materials
    #(geometry, materialPointers)
)

fn MLWriteClumpModel destination data game modelID platform =
(
    if modelID < 0 or modelID > 65534 do throw "Enter the game's model ID before exporting."
    local triangles = data[1]
    local materials = data[2]
    local frameNodes = data[3]
    local skinned = data[4]
    local rootInverse = data[5]
    if skinned and platform == "PS2" and frameNodes.count > 63 do
        throw "PS2 skin offsets support at most 63 hierarchy frames."
    if frameNodes.count > 254 do throw "The MDL hierarchy exceeds 254 frames."
    local objectNodes = MLMdlObjectGroups triangles
    if objectNodes.count < 2 do throw "ClumpModel export needs two or more objects."
    if objectNodes.count > 2048 do throw "The MDL clump contains too many objects."
    local writer = MLWriter()
    local temporary = MLTemporaryFile destination
    try
    (
        writer.openFile temporary
        writer.zeros 0x30
        local rootFrame = writer.tell()
        writer.zeros 0xAC
        local geometryPointers = #()
        local materialPointers = #()
        local materialNames = #()
        local skinnedParts = #()
        for objectNode in objectNodes do
        (
            local localTriangles = #()
            local localMaterials = #()
            local usedMaterials = #()
            local isSkinned = false
            local rigidFrame = MLExportRigidFrame objectNode frameNodes
            local inverseFrame = matrix3 1
            local normalFrame = matrix3 1
            for triangle in triangles where MLMdlSameGroup triangle[3] objectNode do
            (
                if not triangle[4] and (MLExportRigidFrame triangle[3] frameNodes) != rigidFrame do
                    throw ("Mesh parts belonging to " + objectNode.name + " are attached to different frames.")
                if localTriangles.count == 0 do
                (
                    isSkinned = triangle[4]
                    local frameWorld = if isSkinned then (matrix3 1) else (rigidFrame.transform * rootInverse)
                    inverseFrame = inverse frameWorld
                    normalFrame = matrix3 [frameWorld.row1.x,frameWorld.row2.x,frameWorld.row3.x] [frameWorld.row1.y,frameWorld.row2.y,frameWorld.row3.y] [frameWorld.row1.z,frameWorld.row2.z,frameWorld.row3.z] [0,0,0]
                )
                local localMaterialID = findItem usedMaterials triangle[1]
                if localMaterialID == 0 do
                (
                    append usedMaterials triangle[1]
                    append localMaterials materials[triangle[1]]
                    localMaterialID = localMaterials.count
                )
                local corners = #()
                for corner in triangle[2] do
                (
                    local point = corner[1] * inverseFrame
                    local normal = if isSkinned then corner[4] else normalize (corner[4] * normalFrame)
                    append corners #(point,corner[2],corner[3],normal,corner[5])
                )
                append localTriangles #(localMaterialID,corners,objectNode,isSkinned)
            )
            local result = if platform == "PSP" then
                MLWritePspGeometryBlock writer localTriangles localMaterials isSkinned
                else MLWritePs2GeometryBlock writer localTriangles localMaterials isSkinned
            append geometryPointers result[1]
            append skinnedParts isSkinned
            for index = 1 to result[2].count do
            (
                append materialPointers result[2][index]
                append materialNames localMaterials[index].name
            )
        )
        writer.align 16
        local clump = writer.tell()
        writer.zeros 0x34
        local atomics = #()
        for index = 1 to objectNodes.count do
        (
            writer.align 16
            append atomics (writer.tell())
            writer.zeros 0x34
        )
        local rootName = writer.tell()
        writer.text "root"
        local end = writer.tell()
        writer.seek rootFrame
        writer.long 0x03000000
        writer.seek (rootFrame + 0x10)
        writer.matrix (matrix3 1)
        writer.matrix (matrix3 1)
        writer.seek end
        writer.pointer (rootFrame + 0x98) rootFrame
        writer.pointer (rootFrame + (if platform == "PSP" or game == "VCS" then 0xA8 else 0xA4)) rootName
        writer.patchLong clump (MLMdlClumpTag game platform)
        writer.pointer (clump + 4) rootFrame
        writer.pointer (clump + 8) (atomics[1] + 0x1C)
        writer.pointer (clump + 12) (atomics[atomics.count] + 0x1C)
        local skeleton = MLWriteSkeleton writer rootFrame frameNodes rootInverse platform game skinned
        local hierarchy = skeleton[1]
        local framePointers = skeleton[2]
        local endOfSkeleton = writer.tell()
        local atomicFrames = #()
        for index = 1 to atomics.count do
        (
            local atomic = atomics[index]
            local framePointer = rootFrame
            if not skinnedParts[index] do
            (
                local rigidFrame = MLExportRigidFrame objectNodes[index] frameNodes
                local frameIndex = findItem frameNodes rigidFrame
                if frameIndex == 0 do throw "A rigid model part has no matching frame."
                framePointer = framePointers[frameIndex]
            )
            append atomicFrames framePointer
            writer.patchLong atomic (MLMdlAtomicTag game platform)
            writer.pointer (atomic + 4) framePointer
            writer.pointer (atomic + 20) geometryPointers[index]
            writer.pointer (atomic + 28) (if index == atomics.count then clump + 8 else atomics[index + 1] + 0x1C)
            writer.pointer (atomic + 32) (if index == 1 then clump + 8 else atomics[index - 1] + 0x1C)
            if skinnedParts[index] do writer.pointer (atomic + 44) hierarchy
            writer.seek (atomic + 40)
            writer.short modelID
            writer.short 0
        )
        local linkedFrames = #()
        for framePointer in atomicFrames where (findItem linkedFrames framePointer) == 0 do append linkedFrames framePointer
        for framePointer in linkedFrames do
        (
            local attached = #()
            for index = 1 to atomicFrames.count where atomicFrames[index] == framePointer do append attached index
            writer.pointer (framePointer + 8) (atomics[attached[1]] + 8)
            writer.pointer (framePointer + 12) (atomics[attached[attached.count]] + 8)
            for linkIndex = 1 to attached.count do
            (
                local atomicIndex = attached[linkIndex]
                writer.pointer (atomics[atomicIndex] + 8) (if linkIndex == attached.count then framePointer + 8 else atomics[attached[linkIndex + 1]] + 8)
                writer.pointer (atomics[atomicIndex] + 12) (if linkIndex == 1 then framePointer + 8 else atomics[attached[linkIndex - 1]] + 8)
            )
        )
        writer.seek endOfSkeleton
        writer.pointer 0x20 clump
        writer.align 4
        local relocationOffset = writer.tell()
        local textureHead = relocationOffset + (writer.relocations.count + materialPointers.count + 1) * 4
        for offset in writer.relocations do writer.long offset
        for pointer in materialPointers do writer.long pointer
        writer.long textureHead
        writer.long (atomics[1] + 0x24)
        for index = 1 to materialPointers.count do
        (
            local namePointer = writer.tell()
            writer.text materialNames[index]
            writer.patchLong materialPointers[index] namePointer
        )
        local logicalEnd = writer.tell()
        writer.patchLong 0 0x006D646C
        writer.patchLong 8 logicalEnd
        writer.patchLong 12 relocationOffset
        writer.patchLong 16 relocationOffset
        writer.patchLong 20 (writer.relocations.count + materialPointers.count + 1)
        writer.patchLong 0x18 textureHead
        writer.patchLong 0x1C 0x10000
        writer.align 2048
        writer.closeFile()
        MLValidateStoriesExport temporary game platform triangles.count objectNodes.count modelID skinned
        MLFinishFile temporary destination
        triangles.count
    )
    catch
    (
        writer.closeFile()
        if doesFileExist temporary do deleteFile temporary
        throw()
    )
)
