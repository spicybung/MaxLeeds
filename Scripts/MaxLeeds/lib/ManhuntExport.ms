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

global MLWriteManhuntPcEdits, MLFileDigest, MLSnapshotWithoutSkin
fn MLFileDigest path =
(
    local input = undefined
    local algorithm = undefined
    try
    (
        input = (dotNetClass "System.IO.File").OpenRead path
        algorithm = (dotNetClass "System.Security.Cryptography.SHA256").Create()
        local bytes = algorithm.ComputeHash input
        local result = (dotNetClass "System.BitConverter").ToString bytes
        input.Close(); input = undefined
        algorithm.Clear(); algorithm = undefined
        result
    )
    catch
    (
        if input != undefined do input.Close()
        if algorithm != undefined do algorithm.Clear()
        throw()
    )
)
fn MLSnapshotWithoutSkin node =
(
    local modifiers = #()
    try
    (
        for modifier in node.modifiers where (classof modifier) == Skin do
        (
            append modifiers #(modifier,modifier.enabled)
            modifier.enabled = false
        )
        local result = snapshotAsMesh node
        for item in modifiers do item[1].enabled = item[2]
        result
    )
    catch
    (
        for item in modifiers do item[1].enabled = item[2]
        throw()
    )
)
fn MLMhWriteCompressed source destination =
(
    local reader = MLReader()
    local header = MLWriter()
    local input = undefined
    local output = undefined
    local compressor = undefined
    try
    (
        reader.openFile source
        local length = reader.length
        reader.closeFile()
        header.openFile destination
        header.long 0x4D48325A
        header.long length
        header.byte 0x78; header.byte 0x9C
        header.closeFile()
        input = (dotNetClass "System.IO.File").OpenRead source
        output = (dotNetClass "System.IO.File").Open destination ((dotNetClass "System.IO.FileMode").Append)
        compressor = dotNetObject "System.IO.Compression.DeflateStream" output ((dotNetClass "System.IO.Compression.CompressionMode").Compress)
        local buffer = (dotNetClass "System.Array").CreateInstance (dotNetClass "System.Byte") 65536
        local a = 1
        local b = 0
        local amount = input.Read buffer 0 65536
        while amount > 0 do
        (
            compressor.Write buffer 0 amount
            for index = 0 to amount - 1 do
            (
                a = mod (a + ((buffer.GetValue index) as integer)) 65521
                b = mod (b + a) 65521
            )
            amount = input.Read buffer 0 65536
        )
        compressor.Close(); compressor = undefined
        output.Close(); output = undefined
        input.Close(); input = undefined
        header.stream = fopen destination "ab"
        if header.stream == undefined do throw "Cannot finish the compressed output."
        header.byte (bit.shift b -8); header.byte (bit.and b 255)
        header.byte (bit.shift a -8); header.byte (bit.and a 255)
        header.closeFile()
    )
    catch
    (
        reader.closeFile(); header.closeFile()
        if compressor != undefined do compressor.Close()
        if output != undefined do output.Close()
        if input != undefined do input.Close()
        throw()
    )
)
fn MLWriteManhuntPcEdits destination nodes =
(
    local roots = for node in nodes where (MLUserFlag node "MaxLeedsRoot") collect node
    if roots.count != 1 do throw "Select one imported Manhunt PC model root."
    local root = roots[1]
    if (getUserProp root "MaxLeedsGame") != "MH2" or (getUserProp root "MaxLeedsPlatform") != "PC" do throw "Position / UV export requires an imported Manhunt 2 PC model."
    local source = getUserProp root "MaxLeedsSource"
    if source == undefined or not doesFileExist source do throw "The original Manhunt model file is missing."
    local digest = getUserProp root "MaxLeedsSourceDigest"
    if digest == undefined do throw "Reimport this model with the current MaxLeeds version before exporting edits."
    if digest != (MLFileDigest source) do throw "The source model changed after import. Reimport it before exporting edits."
    local decoded = MLDecodeResource source #("PMLC")
    local temporary = MLTemporaryFile destination
    local packed = MLTemporaryFile destination
    local reader = MLReader()
    local writer = MLWriter()
    local snapshot = undefined
    try
    (
        -- Read the source again so offsets never come from unchecked scene properties.
        local models = MLReadManhuntModels source
        MLOpenResource reader decoded[1] "PMLC"
        if not copyFile decoded[1] temporary do throw "Cannot stage the Manhunt model output."
        writer.stream = fopen temporary "r+b"
        if writer.stream == undefined do throw "Cannot edit the staged Manhunt model."
        local used = #()
        local meshCount = 0
        local vertexTotal = 0
        local inverseConversion = rotateXMatrix -90
        for node in nodes where (superclassof node) == GeometryClass and (classof node) != BoneGeometry do
        (
            local pointer = getUserProp node "MaxLeedsAtomic"
            if pointer == undefined do throw (node.name + " has no source geometry identity. Reimport it before exporting edits.")
            pointer = pointer as integer
            if (findItem used pointer) != 0 do throw "Two scene meshes refer to the same source object."
            append used pointer
            local original = undefined
            for model in models where model.platform == "PC" do for part in model.parts where part.atomicPointer == pointer do original = part
            if original == undefined do throw "The scene mesh is not present in the original PC model."
            local header = reader.atLong (pointer + 12)
            local records = reader.atLong (header + 44)
            local faceIndices = reader.atLong (header + 48)
            local stride = reader.atLong (header + 96)
            local vertexType = reader.atLong (header + 144)
            local uvCount = MLBits vertexType 8 4
            local uvOffset = if (bit.and vertexType 0x1000) != 0 then 44 else 24
            local vertexStart = header + 180 + records * 44 + faceIndices * 2
            snapshot = MLSnapshotWithoutSkin node
            if snapshot.numverts != original.vertices.count do throw (node.name + ": vertex count changed. Position / UV export requires the original topology.")
            local sourceFaces = #()
            local sourceIDs = #()
            for index = 1 to original.faces.count do
            (
                local face = original.faces[index]
                local a = original.vertices[face.x as integer]
                local b = original.vertices[face.y as integer]
                local c = original.vertices[face.z as integer]
                if a != b and b != c and c != a do (append sourceFaces face; append sourceIDs original.faceIDs[index])
            )
            if original.faceIDs.count != original.faces.count do throw "The source model has an incomplete native face material stream."
            if snapshot.numfaces != sourceFaces.count do throw (node.name + ": face count changed. Position / UV export requires the original topology.")
            for index = 1 to sourceFaces.count do
            (
                if (getFace snapshot index) != sourceFaces[index] do throw (node.name + ": face indices or winding changed.")
                if (getFaceMatID snapshot index) != sourceIDs[index] do throw (node.name + ": face material assignments changed; this export preserves native materials.")
            )
            local positions = #()
            for index = 1 to snapshot.numverts do
            (
                local point = (getVert snapshot index) * inverseConversion
                for axis = 1 to 3 do if point[axis] != point[axis] or (abs point[axis]) > 100000 do throw "A vertex position is not finite or exceeds the supported range."
                append positions point
                writer.seek (vertexStart + (index - 1) * stride)
                writer.point point
            )
            for channel = 1 to uvCount do
            (
                if not meshop.getMapSupport snapshot channel do throw (node.name + ": a source UV channel is missing.")
                local values = for index = 1 to snapshot.numverts collect undefined
                for index = 1 to snapshot.numfaces do
                (
                    local face = getFace snapshot index
                    local mapFace = meshop.getMapFace snapshot channel index
                    for corner = 1 to 3 do
                    (
                        local vertex = face[corner] as integer
                        local mapIndex = mapFace[corner] as integer
                        if mapIndex < 1 or mapIndex > meshop.getNumMapVerts snapshot channel do
                            throw (node.name + ": invalid UV vertex in channel " + channel as string)
                        local uv = meshop.getMapVert snapshot channel mapIndex
                        if values[vertex] != undefined and (distance values[vertex] uv) > 0.00001 do throw (node.name + ": a UV seam needs new native vertices; position / UV export cannot split topology.")
                        values[vertex] = uv
                    )
                )
                for index = 1 to values.count where values[index] != undefined do
                (
                    local uv = values[index]
                    if uv.x != uv.x or uv.y != uv.y or (abs uv.x) > 10000 or (abs uv.y) > 10000 do throw "A UV coordinate is not finite or exceeds the supported range."
                    writer.seek (vertexStart + (index - 1) * stride + uvOffset + (channel - 1) * 8)
                    writer.float uv.x; writer.float (1.0 - uv.y)
                )
            )
            -- Update native material AABBs and the object sphere after moving vertices.
            for record = 0 to records - 1 do
            (
                local row = header + 180 + record * 44
                local count = reader.atShort (row + 24)
                local first = reader.atShort (row + 28)
                if mod count 3 != 0 or mod first 3 != 0 or first + count > original.faces.count * 3 do
                    throw "The original material face range is invalid."
                if count > 0 do
                (
                    local minimum = [1.0e30,1.0e30,1.0e30]
                    local maximum = -minimum
                    for faceIndex = ((first / 3 + 1) as integer) to (((first + count) / 3) as integer) do
                        for corner = 1 to 3 do
                        (
                            local value = positions[original.faces[faceIndex][corner] as integer]
                            for axis = 1 to 3 do (minimum[axis] = amin minimum[axis] value[axis]; maximum[axis] = amax maximum[axis] value[axis])
                        )
                    writer.seek row; writer.point minimum; writer.point maximum
                )
            )
            local minimum = copy positions[1]
            local maximum = copy positions[1]
            for value in positions do for axis = 1 to 3 do (minimum[axis] = amin minimum[axis] value[axis]; maximum[axis] = amax maximum[axis] value[axis])
            local center = (minimum + maximum) * 0.5
            local radius = 0.0
            for value in positions do radius = amax radius (distance value center)
            writer.seek (header + 52); writer.point center; writer.float radius
            vertexTotal += snapshot.numverts
            meshCount += 1
            free snapshot; snapshot = undefined
        )
        if meshCount == 0 do throw "There are no imported PC meshes to export."
        writer.closeFile(); reader.closeFile()
        local checked = MLReadManhuntModels temporary
        if checked.count != models.count do throw "The edited model failed structural validation."
        if decoded[2] then
        (
            MLMhWriteCompressed temporary packed
            local verified = MLReadManhuntModels packed
            if verified.count != models.count do throw "The compressed output failed structural validation."
            MLFinishFile packed destination
        )
        else MLFinishFile temporary destination
        if doesFileExist temporary do deleteFile temporary
        if decoded[2] and doesFileExist decoded[1] do deleteFile decoded[1]
        #(meshCount,vertexTotal)
    )
    catch
    (
        if snapshot != undefined do free snapshot
        writer.closeFile(); reader.closeFile()
        if doesFileExist temporary do deleteFile temporary
        if doesFileExist packed do deleteFile packed
        if decoded[2] and doesFileExist decoded[1] do deleteFile decoded[1]
        throw()
    )
)
