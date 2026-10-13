-- MaxLeeds - spicybung
-- GPL-3.0-or-later

global MLReadCollision, MLWriteCollision
fn MLReadCollision path =
(
    local reader = MLReader()
    local created = #()
    try
    (
        reader.openFile path
        if (reader.text 0 4) != "2loc" do throw "Choose a Leeds COL2 file."
        local logicalEnd = reader.atLong 8
        reader.check 0 logicalEnd
        local table = 0x20
        local count = 0
        while table + 8 <= logicalEnd do
        (
            local resourceID = reader.atLong table
            local modelPointer = reader.atLong (table + 4)
            if modelPointer == 0 do exit
            count += 1
            if count > 4096 do throw "Too many collision resources."
            reader.check modelPointer 0x60
            local sphereCount = reader.atShort (modelPointer + 0x30)
            local boxCount = reader.atShort (modelPointer + 0x32)
            local triangleCount = reader.atShort (modelPointer + 0x34)
            if sphereCount != 0 do throw "COL2 sphere shapes are not supported by this native build."
            local verticesPointer = reader.atLong (modelPointer + 0x4C)
            local trianglesPointer = reader.atLong (modelPointer + 0x50)
            local boxesPointer = reader.atLong (modelPointer + 0x44)
            if triangleCount > 0 do
            (
                reader.check trianglesPointer (triangleCount * 8)
                local part = MLPart name:(getFilenameFile path + "_collision" + count as string)
                local maximumVertex = 0
                local surfaces = #()
                for index = 0 to triangleCount - 1 do
                (
                    reader.seek (trianglesPointer + index * 8)
                    local raw = [reader.signedShort(), reader.signedShort(), reader.signedShort()]
                    if raw.x < 0 or raw.y < 0 or raw.z < 0 or (mod raw.x 6) != 0 or (mod raw.y 6) != 0 or (mod raw.z 6) != 0 do
                        throw "Collision triangle offsets are invalid."
                    local face = raw / 6 + [1,1,1]
                    maximumVertex = amax maximumVertex face.x face.y face.z
                    append part.faces face
                    append surfaces (reader.byte())
                    reader.byte()
                )
                reader.check verticesPointer (maximumVertex * 6)
                reader.seek verticesPointer
                for index = 1 to maximumVertex do append part.vertices ([reader.signedShort(), reader.signedShort(), reader.signedShort()] / 128.0)
                local node = MLCreateMesh part #()
                append created node
                node.wireColor = color 80 190 140
                for index = 1 to surfaces.count do setFaceMatID node index (surfaces[index] + 1)
                setUserProp node "MaxLeedsResourceID" resourceID
                setUserProp node "MaxLeedsCollision" "Mesh"
            )
            if boxCount > 0 do
            (
                reader.check boxesPointer (boxCount * 48)
                for index = 0 to boxCount - 1 do
                (
                    local minimum = reader.atPoint (boxesPointer + index * 48)
                    local maximum = reader.atPoint (boxesPointer + index * 48 + 16)
                    if minimum.x > maximum.x or minimum.y > maximum.y or minimum.z > maximum.z do throw "Collision box bounds are invalid."
                    local node = box name:(getFilenameFile path + "_box" + index as string) width:(maximum.x - minimum.x) length:(maximum.y - minimum.y) height:(maximum.z - minimum.z)
                    node.pos = [(minimum.x + maximum.x) / 2, (minimum.y + maximum.y) / 2, minimum.z]
                    node.boxMode = true
                    append created node
                    setUserProp node "MaxLeedsResourceID" resourceID
                    setUserProp node "MaxLeedsCollision" "Box"
                )
            )
            table += 8
        )
        if created.count == 0 do throw "No collision meshes or boxes were found."
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
fn MLWriteCollision destination nodes =
(
    if nodes.count == 0 do throw "Select collision meshes or boxes."
    local writer = MLWriter()
    local temporary = MLTemporaryFile destination
    local snapshots = #()
    try
    (
        local models = #()
        local usedIDs = #()
        for node in nodes where (superclassof node) == GeometryClass and (classof node) != BoneGeometry do
        (
            if (getUserProp node "MaxLeedsCollision") == "Box" do throw "Native collision box export has not been ported. Select collision meshes only."
            local snapshot = snapshotAsMesh node
            append snapshots snapshot
            if snapshot.numverts > 5462 do throw "A COL2 mesh can contain at most 5462 vertices. Split this mesh."
            if snapshot.numfaces > 32767 do throw "A COL2 mesh can contain at most 32767 faces. Split this mesh."
            local points = for index = 1 to snapshot.numverts collect ((getVert snapshot index) * node.objectTransform)
            if points.count == 0 do throw "The selection contains an empty mesh."
            local minimum = copy points[1]
            local maximum = copy points[1]
            for point in points do for component = 1 to 3 do
            (
                minimum[component] = amin minimum[component] point[component]
                maximum[component] = amax maximum[component] point[component]
                local quantized = point[component] * 128.0
                if quantized < -32768 or quantized > 32767 do throw "Collision coordinates exceed the COL2 range."
            )
            local resourceID = getUserProp node "MaxLeedsResourceID"
            if resourceID == undefined or resourceID <= 0 do resourceID = 4096 + models.count
            if (findItem usedIDs resourceID) != 0 do throw "Selected collision resources have the same ID. Export their boxes and mesh separately."
            append usedIDs resourceID
            append models #(node, snapshot, points, minimum, maximum, resourceID)
        )
        if models.count == 0 do throw "No geometry is selected."
        writer.openFile temporary
        writer.zeros (0x20 + (models.count + 1) * 8)
        writer.patchLong (0x20 + models.count * 8) 0xFFFFFFFF
        for modelIndex = 1 to models.count do
        (
            local model = models[modelIndex]
            local snapshot = model[2]
            writer.align 16
            local header = writer.tell()
            writer.zeros 0x60
            writer.align 2
            local verticesPointer = writer.tell()
            for point in model[3] do for component = 1 to 3 do writer.signedShort ((if point[component] < 0 then ceil (point[component] * 128.0 - 0.5) else floor (point[component] * 128.0 + 0.5)) as integer)
            local trianglesPointer = writer.tell()
            for faceIndex = 1 to snapshot.numfaces do
            (
                local face = getFace snapshot faceIndex
                for corner = 1 to 3 do writer.signedShort (((face[corner] as integer) - 1) * 6)
                local surface = (getFaceMatID snapshot faceIndex) - 1
                if surface < 0 or surface > 255 do throw "Collision surface IDs must be between 1 and 256 in Max."
                writer.byte surface
                writer.byte 0
            )
            local end = writer.tell()
            local center = (model[4] + model[5]) / 2
            writer.seek header
            writer.point center
            writer.float (distance center model[5])
            writer.point model[4]; writer.float 0
            writer.point model[5]; writer.float 0
            writer.short 0; writer.short 0; writer.short snapshot.numfaces
            writer.byte 0; writer.byte 0; writer.byte 4; writer.byte 0
            writer.seek end
            writer.pointer (header + 0x4C) verticesPointer
            writer.pointer (header + 0x50) trianglesPointer
            writer.patchLong (0x20 + (modelIndex - 1) * 8) model[6]
            writer.pointer (0x24 + (modelIndex - 1) * 8) header
        )
        writer.align 4
        local relocationOffset = writer.tell()
        sort writer.relocations
        for offset in writer.relocations do writer.long offset
        local logicalEnd = writer.tell()
        writer.seek 0
        writer.long 0x636F6C32; writer.long 0; writer.long logicalEnd
        writer.long relocationOffset; writer.long relocationOffset; writer.long writer.relocations.count
        writer.long 0; writer.long 0
        writer.seek logicalEnd
        writer.align 2048
        writer.closeFile()
        for snapshot in snapshots do free snapshot
        snapshots = #()
        MLFinishFile temporary destination
        models.count
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
