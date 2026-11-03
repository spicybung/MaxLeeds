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

global MLSelectedFamily, MLApplyTextures, MLMaterialImages, MLFindModelTextures, MLTextureDictionaryNames, MLImportModelTextures, MLSetBonesVisible, MLAuditSkin, MLLimitSkinWeights
fn MLTextureName value = toLower (getFilenameFile (filenameFromPath value))
fn MLVisitFamilyNode node result =
(
    if (findItem result node) == 0 do append result node
    for child in node.children do MLVisitFamilyNode child result
)
fn MLSelectedFamily =
(
    if selection.count == 0 do throw "Select a model or its mesh parts."
    local roots = #()
    for node in selection do
    (
        local root = node
        local ancestor = node
        while ancestor != undefined do
        (
            if (MLUserFlag ancestor "MaxLeedsRoot") do root = ancestor
            ancestor = ancestor.parent
        )
        if (findItem roots root) == 0 do append roots root
    )
    local result = #()
    for root in roots do MLVisitFamilyNode root result
    result
)
fn MLApplyNativeWorldUV material texture =
(
    local metadata = getAppData material 0x4D4C0001
    if metadata == undefined do return false
    local fields = filterString metadata "|"
    if fields.count != 2 or fields[1] != "VCS" do return false
    local flags = fields[2] as integer
    if (bit.and flags 0xF000) != 0xC000 do return false
    local modes = #(MLBits flags 8 2,MLBits flags 10 2)
    if (findItem modes 3) != 0 do return false
    local changed = false
    for axis = 1 to 2 where modes[axis] != 0 do
    (
        local controller = Float_Script()
        local expression = "local phase = (F - 1.0) * 0.05\nphase -= floor phase\n"
        expression += if modes[axis] == 1 then "phase" else "(if phase == 0.25 then 0.0 else (floor (2.0 * phase + 0.5)) * 0.25)"
        if axis == 2 do expression = "-(\n" + expression + "\n)"
        controller.script = expression
        if axis == 1 then texture.coords.U_Offset.controller = controller
        else texture.coords.V_Offset.controller = controller
        changed = true
    )
    changed
)

fn MLApplyTextures images nodes onlyMissing:false =
(
    local assigned = 0
    local textureTable = dotNetObject "System.Collections.Hashtable"
    for index = 1 to images.count do
    (
        local name = MLTextureName images[index][1]
        if not (textureTable.ContainsKey name) do textureTable.Add name index
    )
    local touched = #()
    for node in nodes where isValidNode node and isProperty node #material and node.material != undefined do
    (
        local materials = if (classof node.material) == MultiMaterial then node.material.materialList else #(node.material)
        for material in materials where material != undefined and isProperty material #diffuseMap do
        (
            if (findItem touched material) == 0 do
            (
                append touched material
                local name = MLTextureName material.name
                if textureTable.ContainsKey name and (not onlyMissing or material.diffuseMap == undefined) do
                (
                    local record = images[(textureTable.get_Item name)]
                    local bitmapMap = bitmapTexture filename:record[2]
                    bitmapMap.alphaSource = 0
                    MLApplyNativeWorldUV material bitmapMap
                    material.diffuseMap = bitmapMap
                    if isProperty material #diffuseMapEnable do material.diffuseMapEnable = true
                    if record.count >= 3 and record[3] == true and isProperty material #opacityMap do
                    (
                        local alphaMap = bitmapTexture filename:record[2]
                        alphaMap.alphaSource = 0
                        alphaMap.monoOutput = 1
                        MLApplyNativeWorldUV material alphaMap
                        material.opacityMap = alphaMap
                        if isProperty material #opacityMapEnable do material.opacityMapEnable = true
                    )
                    showTextureMap material true
                    assigned += 1
                )
            )
        )
    )
    assigned
)
fn MLMaterialImages nodes =
(
    local paths = #()
    for node in nodes where isValidNode node and isProperty node #material and node.material != undefined do
    (
        local materials = if (classof node.material) == MultiMaterial then node.material.materialList else #(node.material)
        for material in materials where material != undefined and isProperty material #diffuseMap do
        (
            local texture = material.diffuseMap
            if texture != undefined and isProperty texture #filename do
            (
                local path = texture.filename
                if path != "" and doesFileExist path and (findItem paths path) == 0 do append paths path
            )
        )
    )
    paths
)

fn MLTextureDictionaryNames path platform =
(
    local reader = MLReader()
    local names = #()
    try
    (
        reader.openFile path
        if (reader.text 0 4) == "xet" do
        (
            platform = MLTexturePlatform reader platform
            local slot = reader.atLong 0x2C
            local visited = #()
            while slot != 0x28 and slot != 0 do
            (
                if (findItem visited slot) != 0 do throw "Texture dictionary contains a cycle."
                append visited slot
                if visited.count > 4096 do throw "Texture dictionary contains too many entries."
                local base = slot - 8
                reader.check base (if platform == "PS2" then 0x60 else 0x50)
                append names (MLTextureName (reader.text (base + 16) (if platform == "PS2" then 64 else 32)))
                slot = reader.atLong (base + 12)
            )
        )
        reader.closeFile()
        names
    )
    catch
    (
        reader.closeFile()
        #()
    )
)

fn MLFindModelTextures modelPath nodes platform =
(
    local directory = getFilenamePath modelPath
    local stem = toLower (getFilenameFile modelPath)
    local modelGame = ""
    for node in nodes where (MLUserFlag node "MaxLeedsRoot") do
    (
        local sourceGame = getUserProp node "MaxLeedsGame"
        if sourceGame != undefined do modelGame = sourceGame
    )
    local candidates = #()
    if modelGame != "LCS" do join candidates (getFiles (directory + "*.xtx"))
    if modelGame != "VCS" do join candidates (getFiles (directory + "*.chk"))
    local result = #()
    local remaining = #()
    for candidate in candidates do
    (
        if (toLower (getFilenameFile candidate)) == stem then append result candidate
        else append remaining candidate
    )
    local materialNames = #()
    for node in nodes where isValidNode node and isProperty node #material and node.material != undefined do
    (
        local materials = if (classof node.material) == MultiMaterial then node.material.materialList else #(node.material)
        for material in materials where material != undefined do
        (
            local materialName = MLTextureName material.name
            if (findItem materialNames materialName) == 0 do append materialNames materialName
        )
    )
    for candidate in remaining do
    (
        local dictionaryNames = MLTextureDictionaryNames candidate platform
        local matched = false
        for name in dictionaryNames where (findItem materialNames name) != 0 do matched = true
        if matched do append result candidate
    )
    if result.count == 0 and candidates.count == 1 do append result candidates[1]
    result
)

fn MLImportModelTextures modelPath platform nodes =
(
    local textures = MLFindModelTextures modelPath nodes platform
    local imported = 0
    local applied = 0
    for dictionary in textures do
    (
        local output = (getFilenamePath modelPath) + (getFilenameFile modelPath) + "_textures\\" + (getFilenameFile dictionary) + "_" + (substring (getFilenameType dictionary) 2 3) + "\\"
        makeDir output all:true
        local records = MLReadTextures dictionary platform output
        imported += records.count
        applied += MLApplyTextures records nodes onlyMissing:true
    )
    #(imported, applied)
)

fn MLSetBonesVisible nodes state =
(
    local count = 0
    for node in nodes where isValidNode node do
    (
        local boneID = getUserProp node "MaxLeedsBoneID"
        if boneID != undefined and (boneID as integer) >= 0 do
        (
            if state then unhide node else hide node
            count += 1
        )
    )
    count
)

fn MLAuditSkin nodes =
(
    local meshes = 0
    local vertices = 0
    local empty = 0
    local excessive = 0
    local unnormalized = 0
    for node in nodes where isValidNode node and (superclassof node) == GeometryClass do
    (
        for modifier in node.modifiers where (classof modifier) == Skin do
        (
            meshes += 1
            local vertexCount = skinOps.GetNumberVertices modifier
            vertices += vertexCount
            for vertex = 1 to vertexCount do
            (
                local influenceCount = skinOps.GetVertexWeightCount modifier vertex
                if influenceCount == 0 do empty += 1
                if influenceCount > 4 do excessive += 1
                local total = 0.0
                for index = 1 to influenceCount do total += skinOps.GetVertexWeight modifier vertex index
                if influenceCount > 0 and (abs (total - 1.0)) > 0.001 do unnormalized += 1
            )
        )
    )
    #(meshes, vertices, empty, excessive, unnormalized)
)

fn MLWeightGreater left right = (if left[2] > right[2] then -1 else if left[2] < right[2] then 1 else 0)
fn MLLimitSkinWeights nodes =
(
    local modified = 0
    local savedSelection = selection as array
    try
    (
        for node in nodes where isValidNode node and (superclassof node) == GeometryClass do
        (
            for modifier in node.modifiers where (classof modifier) == Skin do
            (
                select node
                setCommandPanelTaskMode #modify
                modPanel.setCurrentObject modifier
                local vertexCount = skinOps.GetNumberVertices modifier
                for vertex = 1 to vertexCount do
                (
                    local originalCount = skinOps.GetVertexWeightCount modifier vertex
                    local candidates = #()
                    for index = 1 to originalCount do
                    (
                        local weight = skinOps.GetVertexWeight modifier vertex index
                        if weight > 0 do append candidates #(skinOps.GetVertexWeightBoneID modifier vertex index, weight)
                    )
                    if candidates.count == 0 do throw ("Vertex " + vertex as string + " of " + node.name + " has no weighted bone.")
                    if candidates.count > 4 do
                    (
                        qsort candidates MLWeightGreater
                        while candidates.count > 4 do deleteItem candidates candidates.count
                    )
                    local ids = #()
                    local weights = #()
                    local total = 0.0
                    for candidate in candidates do total += candidate[2]
                    if total <= 0 do throw "Skin influence total is zero."
                    for candidate in candidates do
                    (
                        append ids candidate[1]
                        append weights (candidate[2] / total)
                    )
                    if candidates.count != originalCount or (abs (total - 1.0)) > 0.001 do
                    (
                        skinOps.ReplaceVertexWeights modifier vertex ids weights
                        skinOps.unNormalizeVertex modifier vertex false
                        modified += 1
                    )
                )
            )
        )
        select savedSelection
        modified
    )
    catch (select savedSelection; throw())
)

fn MLMergeModelParts model =
(
    local merged = #()
    local keys = #()
    for part in model.parts do
    (
        local signature = #(part.atomicPointer,part.framePointer,part.uv.count > 0,part.colors.count > 0,part.normals.count > 0,part.weights.count > 0,part.extraUV.count)
        local groupIndex = 0
        if part.atomicPointer != 0 do for index = 1 to keys.count while groupIndex == 0 do
        (
            local match = true
            for component = 1 to signature.count where signature[component] != keys[index][component] do match = false
            if match do groupIndex = index
        )
        if groupIndex == 0 then
        (
            local combined = MLPart name:part.name atomicPointer:part.atomicPointer framePointer:part.framePointer materialID:part.materialID
            for channel = 1 to part.extraUV.count do append combined.extraUV #()
            append merged combined
            append keys signature
            groupIndex = merged.count
        )
        local target = merged[groupIndex]
        local base = target.vertices.count
        for index = 1 to part.faces.count do
        (
            append target.faces (part.faces[index] + [base,base,base])
            append target.faceIDs (if part.faceIDs.count == part.faces.count then part.faceIDs[index] else part.materialID)
        )
        join target.vertices part.vertices
        join target.uv part.uv
        join target.colors part.colors
        join target.normals part.normals
        join target.weights part.weights
        for channel = 1 to part.extraUV.count do join target.extraUV[channel] part.extraUV[channel]
    )
    model.parts = merged
    model
)
