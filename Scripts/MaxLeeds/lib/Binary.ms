-- MaxLeeds - spicybung
-- GPL-3.0-or-later

global MLReader, MLWriter, MLPart, MLFrame, MLMaterial, MLModel

struct MLReader
(
    stream,
    length = 0,
    fn check offset count =
    (
        if offset < 0 or count < 0 or offset + count > length do
            throw "The file is truncated or contains an invalid offset."
        true
    ),
    fn seek offset = (check offset 0; fseek stream offset #seek_set),
    fn tell = ftell stream,
    fn byte = (check (tell()) 1; readByte stream #unsigned),
    fn signedByte = (check (tell()) 1; readByte stream #signed),
    fn short = (check (tell()) 2; readShort stream #unsigned),
    fn signedShort = (check (tell()) 2; readShort stream #signed),
    fn long = (check (tell()) 4; readLong stream #unsigned),
    fn signedLong = (check (tell()) 4; readLong stream #signed),
    fn float =
    (
        check (tell()) 4
        local value = readFloat stream
        if value != value or (abs value) > 1.0e30 do throw "The file contains an invalid floating-point value."
        value
    ),
    fn atLong offset = (seek offset; long()),
    fn atShort offset = (seek offset; short()),
    fn atFloat offset = (seek offset; float()),
    fn point = [float(), float(), float()],
    fn atPoint offset = (seek offset; point()),
    fn text offset limit =
    (
        seek offset
        local result = ""
        local ended = false
        for index = 1 to limit while not ended do
        (
            local value = byte()
            if value == 0 then ended = true
            else result += bit.intAsChar value
        )
        result
    ),
    fn matrix offset =
    (
        local rows = #()
        for index = 0 to 3 do append rows (atPoint (offset + index * 16))
        matrix3 rows[1] rows[2] rows[3] rows[4]
    ),
    fn openFile path =
    (
        stream = fopen path "rb"
        if stream == undefined do throw "Cannot open the selected file."
        fseek stream 0 #seek_end
        length = ftell stream
        fseek stream 0 #seek_set
        true
    ),
    fn closeFile = (if stream != undefined do fclose stream; stream = undefined)
)

struct MLWriter
(
    stream,
    relocations = #(),
    fn tell = ftell stream,
    fn seek offset = fseek stream offset #seek_set,
    fn byte value = writeByte stream value #unsigned,
    fn short value = writeShort stream value #unsigned,
    fn signedShort value = writeShort stream value #signed,
    fn long value = writeLong stream value #unsigned,
    fn float value = writeFloat stream value,
    fn point value = (float value.x; float value.y; float value.z),
    fn zeros count = (for index = 1 to count do byte 0),
    fn align alignment =
    (
        local remainder = mod (tell()) alignment
        if remainder != 0 do zeros (alignment - remainder)
    ),
    fn patchLong offset value =
    (
        local position = tell()
        seek offset
        long value
        seek position
    ),
    fn pointer offset value =
    (
        patchLong offset value
        if value != 0 and (findItem relocations offset) == 0 do append relocations offset
    ),
    fn text value =
    (
        for index = 1 to value.count do
        (
            local code = bit.charAsInt value[index]
            byte (if code >= 32 and code <= 126 then code else 63)
        )
        byte 0
    ),
    fn matrix value =
    (
        for row = 1 to 4 do (point value[row]; long 0)
    ),
    fn openFile path =
    (
        stream = fopen path "wb"
        if stream == undefined do throw "Cannot create the output file."
        relocations = #()
        true
    ),
    fn closeFile = (if stream != undefined do fclose stream; stream = undefined)
)

struct MLMaterial (name = "default", rgba = (color 255 255 255 255))
struct MLPart (name = "model", vertices = #(), faces = #(), uv = #(), colors = #(), normals = #(), weights = #(), materialID = 1, faceIDs = #(), framePointer = 0)
struct MLFrame (pointer = 0, parentPointer = 0, name = "bone", localMatrix = (matrix3 1), worldMatrix = (matrix3 1), boneID = -1)
struct MLModel (parts = #(), frames = #(), materials = #(), platform = "PSP", game = "VCS", modelID = -1, sourcePath = "")

global MLBits, MLAlign, MLColor, MLStripFaces, MLCreateMesh, MLCreateNormals, MLFinishFile, MLTemporaryFile
fn MLBits value first count = bit.and (bit.shift value (-first)) ((bit.shift 1 count) - 1)
fn MLAlign value alignment = ((ceil (value as float / alignment)) as integer) * alignment
fn MLColor value = color (MLBits value 0 8) (MLBits value 8 8) (MLBits value 16 8) (MLBits value 24 8)
fn MLStripFaces count base =
(
    local faces = #()
    for index = 3 to count do
    (
        if (mod index 2) == 1 then append faces [base + index - 2, base + index - 1, base + index]
        else append faces [base + index - 1, base + index - 2, base + index]
    )
    faces
)
fn MLCreateNormals node part =
(
    if part.normals.count != part.vertices.count or part.faces.count == 0 do return false
    local modifier = Edit_Normals()
    addModifier node modifier
    select node
    setCommandPanelTaskMode #modify
    modPanel.setCurrentObject modifier
    local allNormals = #{}
    allNormals.count = modifier.GetNumNormals node:node
    for index = 1 to allNormals.count do allNormals[index] = true
    modifier.Break selection:allNormals node:node
    for faceIndex = 1 to part.faces.count do
    (
        local face = part.faces[faceIndex]
        for corner = 1 to 3 do
        (
            local normalID = modifier.GetNormalID faceIndex corner node:node
            local normalValue = part.normals[face[corner] as integer]
            modifier.SetNormal normalID &normalValue node:node
            modifier.SetNormalExplicit normalID explicit:true node:node
        )
    )
    modifier.displayLength = 0
    modifier.SelLevel = #Object
    true
)
fn MLCreateMesh part materials =
(
    local node = mesh name:part.name vertices:part.vertices faces:part.faces
    try
    (
    if part.uv.count == part.vertices.count do
    (
        meshop.setMapSupport node 1 true
        meshop.setNumMapVerts node 1 part.uv.count
        meshop.setNumMapFaces node 1 part.faces.count
        for index = 1 to part.uv.count do meshop.setMapVert node 1 index part.uv[index]
        for index = 1 to part.faces.count do meshop.setMapFace node 1 index part.faces[index]
    )
    if part.colors.count == part.vertices.count do
    (
        for channel in #(0, -2) do
        (
            meshop.setMapSupport node channel true
            meshop.setNumMapVerts node channel part.colors.count
            meshop.setNumMapFaces node channel part.faces.count
            for index = 1 to part.colors.count do
            (
                local value = part.colors[index]
                local vector = if channel == 0 then [value.r / 255.0, value.g / 255.0, value.b / 255.0] else [value.a / 255.0, 0, 0]
                meshop.setMapVert node channel index vector
            )
            for index = 1 to part.faces.count do meshop.setMapFace node channel index part.faces[index]
        )
        node.showVertexColors = true
    )
    if materials.count > 0 do
    (
        local multi = multiMaterial numsubs:materials.count name:(part.name + " materials")
        for index = 1 to materials.count do
        (
            local description = materials[index]
            multi.materialList[index] = standardMaterial name:description.name diffuse:description.rgba opacity:(description.rgba.a * 100.0 / 255.0)
        )
        node.material = multi
    )
    for index = 1 to part.faces.count do setFaceMatID node index (if part.faceIDs.count == part.faces.count then part.faceIDs[index] else part.materialID)
    update node
    MLCreateNormals node part
        node
    )
    catch
    (
        local reason = getCurrentException()
        if isValidNode node do delete node
        throw()
    )
)
fn MLTemporaryFile destination =
(
    local guidClass = dotNetClass "System.Guid"
    local guidValue = guidClass.NewGuid()
    local token = guidValue.ToString()
    (getFilenamePath destination) + "MaxLeeds-" + token + (getFilenameType destination)
)
fn MLFinishFile temporary destination =
(
    if not doesFileExist temporary do throw "The writer did not create a file."
    local io = dotNetClass "System.IO.File"
    if doesFileExist destination then io.Replace temporary destination undefined
    else io.Move temporary destination
    destination
)
