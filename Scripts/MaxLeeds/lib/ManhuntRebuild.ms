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

global MLWriteManhuntPcRebuild, MLMhWriteSkeleton
fn MLMhCopyGeometryBytes reader writer offset count =
(
    reader.seek offset
    for index = 1 to count do writer.byte (reader.byte())
)
fn MLMhCornerKey vertex uv normal rgba =
(
    local key = vertex as string
    for channel in uv do for axis = 1 to 2 do key += ":" + (bit.floatAsInt channel[axis]) as string
    for axis = 1 to 3 do key += ":" + (bit.floatAsInt normal[axis]) as string
    for axis = 1 to 4 do key += ":" + rgba[axis] as string
    key
)
-- Face IDs are user-assigned IDs, not Multi/Sub-Object array positions.
fn MLMhSceneMaterial material faceID =
(
    if material != undefined and (classof material) == MultiMaterial do
    (
        local slots = for index = 1 to material.materialIDList.count where material.materialIDList[index] == faceID collect index
        if slots.count != 1 do throw "Every used face material ID must resolve to exactly one Multi/Sub-Object slot."
        material = material.materialList[slots[1]]
    )
    if material == undefined do throw "Assign a material to every used face slot before rebuilding materials."
    material
)
fn MLMhEncodePcMesh reader writer node original model family rebuildMaterials:false rebuildSkeleton:false =
(
    local header = reader.atLong (original.atomicPointer + 12)
    local recordCount = reader.atLong (header + 44)
    local materialInputs = #()
    local sourceType = reader.atLong (header + 144)
    local stride = reader.atLong (header + 96)
    local sourceSkinned = (bit.and sourceType 0x1000) != 0
    local skinned = sourceSkinned
    local outputType = sourceType
    local uvCount = MLBits sourceType 8 4
    local materialIDs = #()
    local materialBase = undefined
    for index = 0 to recordCount - 1 do
    (
        local row = header + 180 + index * 44
        local count = reader.atShort (row + 24)
        local slot = reader.atShort (row + 26)
        local first = reader.atShort (row + 28)
        append materialIDs (slot + 1)
        if count > 0 do materialBase = original.faceIDs[first / 3 + 1] - slot - 1
    )
    if materialBase == undefined do throw "The source object has no material face ranges."
    local palette = MLMhPalette reader model.frames
    local skin = undefined
    for modifier in node.modifiers where (classof modifier) == Skin do
    (
        if skin != undefined do throw "A rebuilt mesh must have at most one Skin modifier."
        skin = modifier
    )
    if skinned and skin == undefined do throw (node.name + ": the source mesh is skinned, but the scene mesh has no Skin modifier.")
    if not sourceSkinned and skin != undefined do
    (
        if not rebuildSkeleton do throw (node.name + ": enable Rebuild skeleton from current bind pose when adding Skin to a rigid source.")
        skinned = true
        outputType = bit.or (bit.and sourceType (bit.not 255)) 0x105E
        stride = 44 + uvCount * 8
    )
    local skinPalette = #()
    if skinned do
    (
        for index = 1 to (skinOps.GetNumberBones skin) do
        (
            local name = skinOps.GetBoneName skin index 0
            local matches = for bone in family where bone.name == name and ((getUserProp bone "MaxLeedsBoneID") != undefined or (classof bone) == BoneGeometry) collect bone
            if matches.count != 1 do throw ("Cannot uniquely resolve Skin bone " + name)
            local propertyID = getUserProp matches[1] "MaxLeedsBoneID"
            local id = if propertyID == undefined then MLMhBoneID matches[1].name else propertyID as integer
            if id == undefined or id < 0 do throw ("Assign a nonnegative MaxLeedsBoneID to Skin bone " + name)
            local slot = 0
            for paletteIndex = 1 to palette.count where palette[paletteIndex] > 0 and model.frames[palette[paletteIndex]].boneID == id do
            (
                if slot != 0 do throw ("More than one palette entry resolves Skin bone " + name)
                slot = paletteIndex
            )
            append skinPalette slot
        )
    )
    local snapshot = undefined
    try
    (
        snapshot = MLSnapshotWithoutSkin node
        if snapshot.numfaces == 0 do throw (node.name + ": cannot rebuild an empty mesh.")
        if rebuildMaterials do
        (
            materialIDs = #()
            for faceIndex = 1 to snapshot.numfaces do
            (
                local id = getFaceMatID snapshot faceIndex
                if (findItem materialIDs id) == 0 do append materialIDs id
            )
            sort materialIDs
            if materialIDs.count > 4096 do throw "An object cannot have more than 4096 native materials."
            for id in materialIDs do
            (
                local material = MLMhSceneMaterial node.material id
                local name = material.name
                if isProperty material #diffuseMap and (classof material.diffuseMap) == BitmapTexture do name = getFilenameFile material.diffuseMap.filename
                if name == "" or name.count > 127 do throw "Native material texture names must contain 1 to 127 ASCII characters."
                for index = 1 to name.count do if (bit.charAsInt name[index]) < 32 or (bit.charAsInt name[index]) > 126 do throw "Native material names must use ASCII characters."
                if not isProperty material #diffuse do throw "Use Standard materials with diffuse colours or bitmap textures for native material export."
                local rgba = copy material.diffuse
                rgba.a = if isProperty material #opacity then material.opacity * 255.0 / 100.0 else 255
                append materialInputs #(name,rgba)
            )
            materialBase = 0
            recordCount = materialIDs.count
        )
        if skinned and (skinOps.GetNumberVertices skin) != snapshot.numverts do throw (node.name + ": a modifier above Skin changed vertex topology. Move topology edits below Skin before rebuilding.")
        for channel = 1 to uvCount do if not meshop.getMapSupport snapshot channel do throw (node.name + ": a required UV channel is missing.")
        local rows = #()
        local faceGroups = for index = 1 to recordCount collect #()
        local lookup = dotNetObject "System.Collections.Hashtable"
        local inverseConversion = rotateXMatrix -90
        local geometryTransform = matrix3 1
        if rebuildSkeleton do
        (
            local roots = for candidate in family where MLUserFlag candidate "MaxLeedsRoot" collect candidate
            local frames = for frame in model.frames where frame.pointer == original.framePointer collect frame
            if roots.count != 1 or frames.count != 1 do throw "Cannot resolve the rebuilt object frame."
            geometryTransform = node.objectTransform * inverse (frames[1].worldMatrix * roots[1].transform)
        )
        if abs (dot (cross geometryTransform.row1 geometryTransform.row2) geometryTransform.row3) < 0.000001 do throw "The rebuilt mesh has a singular object transform."
        local inverseGeometry = inverse geometryTransform
        local normalTransform = matrix3 [inverseGeometry.row1.x,inverseGeometry.row2.x,inverseGeometry.row3.x] [inverseGeometry.row1.y,inverseGeometry.row2.y,inverseGeometry.row3.y] [inverseGeometry.row1.z,inverseGeometry.row2.z,inverseGeometry.row3.z] [0,0,0]
        local mirrored = (dot (cross geometryTransform.row1 geometryTransform.row2) geometryTransform.row3) < 0
        local faceTotal = 0
        for faceIndex = 1 to snapshot.numfaces do
        (
            local face = getFace snapshot faceIndex
            local material = (getFaceMatID snapshot faceIndex) - materialBase
            local record = findItem materialIDs material
            if record == 0 do throw (node.name + ": a face uses a material absent from this native object.")
            local normals = meshop.getFaceRNormals snapshot faceIndex
            local uvFaces = for channel = 1 to uvCount collect (meshop.getMapFace snapshot channel faceIndex)
            local colorFace = if meshop.getMapSupport snapshot 0 then meshop.getMapFace snapshot 0 faceIndex else undefined
            local alphaFace = if meshop.getMapSupport snapshot -2 then meshop.getMapFace snapshot -2 faceIndex else undefined
            local outputFace = [0,0,0]
            for corner = 1 to 3 do
            (
                local sourceCorner = if mirrored then #(1,3,2)[corner] else corner
                local vertex = face[sourceCorner] as integer
                local uv = for channel = 1 to uvCount collect (meshop.getMapVert snapshot channel (uvFaces[channel][sourceCorner] as integer))
                local normal = normalize (normals[sourceCorner] * normalTransform * inverseConversion)
                local rgba = if vertex <= original.colors.count then copy original.colors[vertex] else color 255 255 255 255
                if colorFace != undefined do
                (
                    local value = meshop.getMapVert snapshot 0 (colorFace[sourceCorner] as integer)
                    rgba.r = value.x * 255; rgba.g = value.y * 255; rgba.b = value.z * 255
                )
                if alphaFace != undefined do rgba.a = (meshop.getMapVert snapshot -2 (alphaFace[sourceCorner] as integer)).x * 255
                for component = 1 to 4 do
                (
                    if rgba[component] != rgba[component] do throw "A vertex color is not finite."
                    rgba[component] = amin 255 (amax 0 ((floor (rgba[component] + 0.5)) as integer))
                )
                for channel in uv do for axis = 1 to 2 do
                    if channel[axis] != channel[axis] or (abs channel[axis]) > 10000 do throw "A UV coordinate is not finite or exceeds the supported range."
                for axis = 1 to 3 do if normal[axis] != normal[axis] or (abs normal[axis]) > 1.001 do throw "A vertex normal is invalid."
                local key = MLMhCornerKey vertex uv normal rgba
                local row = 0
                if lookup.ContainsKey key then row = lookup.get_Item key
                else
                (
                    if rows.count >= 65535 do throw "The rebuilt PC object exceeds 65535 native vertices. Split it within the original object layout."
                    local position = (getVert snapshot vertex) * geometryTransform * inverseConversion
                    for axis = 1 to 3 do if position[axis] != position[axis] or (abs position[axis]) > 100000 do throw "A vertex position is not finite or exceeds the supported range."
                    local influences = #()
                    if skinned do
                    (
                        local total = 0.0
                        for index = 1 to (skinOps.GetVertexWeightCount skin vertex) do
                        (
                            local weight = skinOps.GetVertexWeight skin vertex index
                            if weight != weight or weight < 0 or weight > 1.001 do throw "A Skin weight is invalid."
                            if weight > 0.000001 do
                            (
                                local bone = skinOps.GetVertexWeightBoneID skin vertex index
                                if bone < 1 or bone > skinPalette.count or skinPalette[bone] < 1 or skinPalette[bone] > 256 do throw "A weighted bone is absent from the native palette."
                                local token = skinPalette[bone] - 1
                                local existing = 0
                                for candidate = 1 to influences.count where influences[candidate][1] == token do existing = candidate
                                if existing == 0 then append influences #(token,weight) else influences[existing][2] += weight
                                total += weight
                            )
                        )
                        if influences.count == 0 or total <= 0 do throw "A rebuilt skinned vertex has no positive influences."
                        if influences.count > 4 do throw "A rebuilt vertex exceeds four Skin influences. Use Limit to 4 influences before exporting."
                        for influence in influences do influence[2] /= total
                    )
                    append rows #(position,uv,normal,rgba,influences)
                    row = rows.count
                    lookup.Add key row
                )
                outputFace[corner] = row
            )
            if outputFace.x != outputFace.y and outputFace.x != outputFace.z and outputFace.y != outputFace.z do
            (
                append faceGroups[record] outputFace
                faceTotal += 1
            )
        )
        if faceTotal < 1 or faceTotal * 3 > 65535 do throw "The rebuilt object's material face-index ranges exceed 65535 entries or contain no triangles."
        writer.align 16
        local start = writer.tell()
        MLMhCopyGeometryBytes reader writer header 180
        local firstIndex = 0
        for index = 1 to recordCount do
        (
            local row = writer.tell()
            MLMhCopyGeometryBytes reader writer (header + 180 + (if rebuildMaterials then 0 else (index - 1) * 44)) 44
            local after = writer.tell()
            writer.seek (row + 24)
            writer.short (faceGroups[index].count * 3)
            writer.short (if rebuildMaterials then index - 1 else materialIDs[index] - 1)
            writer.short firstIndex
            firstIndex += faceGroups[index].count * 3
            if faceGroups[index].count > 0 do
            (
                local minimum = [1.0e30,1.0e30,1.0e30]
                local maximum = -minimum
                for face in faceGroups[index] do for corner = 1 to 3 do
                (
                    local point = rows[face[corner] as integer][1]
                    for axis = 1 to 3 do (minimum[axis] = amin minimum[axis] point[axis]; maximum[axis] = amax maximum[axis] point[axis])
                )
                writer.seek row; writer.point minimum; writer.point maximum
            )
            writer.seek after
        )
        for faces in faceGroups do for face in faces do for corner = 1 to 3 do writer.short (face[corner] - 1)
        for row in rows do
        (
            writer.point row[1]
            if skinned do
            (
                for index = 1 to 4 do writer.float (if index <= row[5].count then row[5][index][2] else 0.0)
                for index = 1 to 4 do writer.byte (if index <= row[5].count then row[5][index][1] else 0)
            )
            for axis = 1 to 3 do writer.signedShort (amin 32767 (amax -32768 (MLAnimRoundEven (row[3][axis] * 32768.0))))
            writer.signedShort 0
            writer.byte row[4].b; writer.byte row[4].g; writer.byte row[4].r; writer.byte row[4].a
            for uv in row[2] do (writer.float uv.x; writer.float (1.0 - uv.y))
        )
        local finish = writer.tell()
        if finish - start != 180 + recordCount * 44 + faceTotal * 6 + rows.count * stride do throw "The rebuilt PC vertex buffer does not match its declared stride."
        writer.patchLong (start + 96) stride
        writer.patchLong (start + 144) outputType
        writer.patchLong (start + 36) (finish - start - 32)
        writer.patchLong (start + 44) recordCount
        writer.patchLong (start + 48) (faceTotal * 3)
        writer.patchLong (start + 80) rows.count
        local minimum = copy rows[1][1]
        local maximum = copy rows[1][1]
        for row in rows do for axis = 1 to 3 do (minimum[axis] = amin minimum[axis] row[1][axis]; maximum[axis] = amax maximum[axis] row[1][axis])
        local center = (minimum + maximum) * 0.5
        local radius = 0.0
        for row in rows do radius = amax radius (distance row[1] center)
        writer.seek (start + 52); writer.point center; writer.float radius
        writer.seek finish; writer.align 4
        if rebuildMaterials do
        (
            writer.align 16
            local materialTable = writer.tell()
            local sourceTable = reader.atLong header
            if (reader.atLong (header + 4)) < 1 do throw "The source has no native material template."
            for material in materialInputs do MLMhCopyGeometryBytes reader writer sourceTable 12
            for index = 1 to materialInputs.count do
            (
                local material = materialInputs[index]
                local namePointer = writer.tell()
                writer.text material[1]
                writer.pointer (materialTable + (index - 1) * 12) namePointer
                local after = writer.tell()
                writer.seek (materialTable + (index - 1) * 12 + 5)
                for component = 1 to 4 do writer.byte (MLMhColorByte material[2][component])
                writer.seek after
            )
            writer.patchLong start materialTable
            writer.patchLong (start + 4) materialInputs.count
            writer.align 4
        )
        free snapshot; snapshot = undefined
        local expectedWeights = #()
        if skinned do for row in rows do
        (
            local influences = for influence in row[5] collect #(model.frames[palette[influence[1] + 1]].boneID,influence[2])
            append expectedWeights influences
        )
        #(start,rows.count,faceTotal,expectedWeights)
    )
    catch
    (
        if snapshot != undefined do free snapshot
        throw()
    )
)
fn MLWriteManhuntPcRebuild destination nodes rebuildMaterials:false rebuildSkeleton:false =
(
    local roots = for node in nodes where (MLUserFlag node "MaxLeedsRoot") collect node
    if roots.count != 1 or (getUserProp roots[1] "MaxLeedsGame") != "MH2" or (getUserProp roots[1] "MaxLeedsPlatform") != "PC" do throw "Select one imported Manhunt PC model root."
    local source = getUserProp roots[1] "MaxLeedsSource"
    local digest = getUserProp roots[1] "MaxLeedsSourceDigest"
    if source == undefined or not doesFileExist source do throw "The original Manhunt model is missing."
    if digest == undefined or digest != (MLFileDigest source) do throw "The original source changed or this model predates source validation. Reimport it before rebuilding."
    local models = MLReadManhuntModels source
    local decoded = MLDecodeResource source #("PMLC")
    local temporary = MLTemporaryFile destination
    local packed = MLTemporaryFile destination
    local skeletonSource = MLTemporaryFile destination
    local workingSource = decoded[1]
    local reader = MLReader()
    local writer = MLWriter()
    try
    (
        if rebuildSkeleton do
        (
            MLMhWriteSkeleton decoded[1] nodes roots[1] skeletonSource
            workingSource = skeletonSource
            models = MLReadManhuntModels workingSource
        )
        reader.openFile workingSource
        local payloadEnd = reader.atLong 16
        local count = reader.atLong 20
        local pointers = #()
        for index = 0 to count - 1 do
        (
            local field = reader.atLong (payloadEnd + index * 4)
            if (findItem pointers field) != 0 do throw "The source has duplicate relocation fields."
            append pointers field
        )
        reader.length = payloadEnd
        MLCopyFileRange workingSource 0 payloadEnd temporary
        writer.stream = fopen temporary "r+b"
        if writer.stream == undefined do throw "Cannot stage the rebuilt model."
        writer.seek payloadEnd
        local used = #()
        local expectedSkin = #()
        local vertexTotal = 0
        local faceTotal = 0
        for node in nodes where (superclassof node) == GeometryClass and (classof node) != BoneGeometry do
        (
            local pointer = getUserProp node "MaxLeedsAtomic"
            if pointer == undefined do throw (node.name + " has no source geometry identity.")
            pointer = pointer as integer
            if (findItem used pointer) != 0 do throw "Two scene meshes refer to the same source object."
            if (findItem pointers (pointer + 12)) == 0 do throw "The source object geometry pointer is not relocatable."
            local original = undefined
            local sourceModel = undefined
            for model in models where model.platform == "PC" do for part in model.parts where part.atomicPointer == pointer do (original = part; sourceModel = model)
            if original == undefined do throw "A scene mesh is not present in the original PC model."
            local report = MLMhEncodePcMesh reader writer node original sourceModel nodes rebuildMaterials:rebuildMaterials rebuildSkeleton:rebuildSkeleton
            local oldHeader = reader.atLong (pointer + 12)
            for offset in #(0,8) where (reader.atLong (oldHeader + offset)) != 0 do append pointers (report[1] + offset)
            writer.patchLong (pointer + 12) report[1]
            vertexTotal += report[2]
            faceTotal += report[3]
            append used pointer
            append expectedSkin report[4]
        )
        if used.count == 0 do throw "No imported PC mesh was selected for rebuilding."
        for field in writer.relocations where (findItem pointers field) == 0 do append pointers field
        writer.align 4
        local table = writer.tell()
        sort pointers
        for field in pointers do writer.long field
        local size = writer.tell()
        writer.patchLong 8 size
        writer.patchLong 12 table
        writer.patchLong 16 table
        writer.patchLong 20 pointers.count
        writer.closeFile(); reader.closeFile()
        local checked = MLReadManhuntModels temporary
        if checked.count != models.count do throw "The rebuilt model failed structural validation."
        local actualFaces = 0
        local actualVertices = 0
        for model in checked do for part in model.parts where (findItem used part.atomicPointer) != 0 do
        (
            actualFaces += part.faces.count
            actualVertices += part.vertices.count
            local expected = expectedSkin[findItem used part.atomicPointer]
            if expected.count != part.weights.count do throw "The rebuilt mesh lost its skin vertex stream."
            for vertex = 1 to expected.count do
            (
                local actual = part.weights[vertex]
                if actual.count != expected[vertex].count do throw "The rebuilt skin changed its influence count."
                for index = 1 to actual.count do
                (
                    local boneID = model.frames[actual[index][1]].boneID
                    if boneID != expected[vertex][index][1] or abs (actual[index][2] - expected[vertex][index][2]) > 0.00001 do throw "The rebuilt skin changed a bone assignment or weight."
                )
            )
        )
        if actualFaces != faceTotal or actualVertices != vertexTotal do throw "The rebuilt geometry did not round trip."
        if decoded[2] then
        (
            MLMhWriteCompressed temporary packed
            local verified = MLReadManhuntModels packed
            if verified.count != models.count do throw "The compressed rebuilt model failed validation."
            MLFinishFile packed destination
        )
        else MLFinishFile temporary destination
        if doesFileExist skeletonSource do deleteFile skeletonSource
        if doesFileExist temporary do deleteFile temporary
        if decoded[2] and doesFileExist decoded[1] do deleteFile decoded[1]
        #(used.count,vertexTotal,faceTotal)
    )
    catch
    (
        reader.closeFile(); writer.closeFile()
        if doesFileExist skeletonSource do deleteFile skeletonSource
        if doesFileExist temporary do deleteFile temporary
        if doesFileExist packed do deleteFile packed
        if decoded[2] and doesFileExist decoded[1] do deleteFile decoded[1]
        throw()
    )
)
