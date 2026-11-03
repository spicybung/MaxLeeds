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

global MLCheckTools
-- Compare values explicitly; MAXScript array identity is not a vector assertion.
fn MLCheckVifVector actual expected =
(
    if actual.count != expected.count do return false
    for index = 1 to actual.count do if actual[index] != expected[index] do return false
    true
)
fn MLCheckVifUnpack folder =
(
    local path = folder + "\\vif_vectors.bin"
    local writer = MLWriter()
    local reader = MLReader()
    try
    (
        writer.openFile path
        for value in #(1,2,3,4,4,3,2,1) do writer.long value
        writer.closeFile()
        reader.openFile path
        local state = MLVifState cycle:1 writes:3 mode:2 mask:0x00EE5500
        state.clearMemory()
        state.row = #(10,20,30,40)
        state.column = #(90,91,92,93)
        state.store 2 0 #(9,9,9,9) false true
        local vectors = MLVifReadUnpack reader 0x7C040000 state
        if reader.tell() != 32 or vectors.count != 4 do throw "VIF partial fill consumed the wrong input size."
        if not (MLCheckVifVector vectors[1] #(11,22,33,44)) do throw "VIF difference input failed."
        if not (MLCheckVifVector vectors[2] #(11,22,33,44)) do throw "VIF difference row fill failed."
        if not (MLCheckVifVector vectors[3] #(92,9,92,9)) do throw "VIF column/protected fill failed."
        if not (MLCheckVifVector vectors[4] #(15,25,35,45)) do throw "VIF partial-cycle difference accumulation failed."
        if not (MLCheckVifVector state.row #(15,25,35,45)) do throw "Masked fill changed VIF row arithmetic."
        reader.seek 0
        state = MLVifState cycle:0 writes:256 mask:0x55555555
        state.clearMemory()
        state.row = #(10,20,30,40)
        vectors = MLVifReadUnpack reader 0x7C000000 state
        if vectors.count != 256 or reader.tell() != 0 or not (MLCheckVifVector vectors[256] state.row) do throw "Zero-source VIF fill or NUM=0 failed."
        state.row = #(4294950912L,8192,0,0)
        vectors = MLVifReadUnpack reader 0x79010000 state
        if vectors[1][1] != -16384 do throw "VIF row fill did not preserve signed word interpretation."
        state.mask = 0
        state.mode = 2
        vectors = MLVifReadUnpack reader 0x7C010000 state
        local rejected = false
        try (MLVifRequire vectors[1] 4) catch (rejected = true)
        if not rejected or state.row[1] != undefined do throw "Indeterminate VIF fill invented row values."
        state.mode = 0
        state.cycle = 1
        state.writes = 1
        state.baseAddress = 100
        state.setOffset 200
        reader.seek 0
        vectors = MLVifReadUnpack reader 0x6C018005 state
        state.mask = 255
        reader.seek 0
        vectors = MLVifReadUnpack reader 0x7C010069 state
        if not (MLCheckVifVector vectors[1] #(1,2,3,4)) do throw "Absolute and TOPS-relative VIF writes did not alias."
        state.launch()
        if state.tops != 300 or state.memory[106][1] != undefined do throw "VIF buffer swap or unknown VU memory invalidation failed."
        state.launch()
        if state.tops != 100 do throw "VIF second buffer swap failed."
        state.baseAddress = 1020
        state.setOffset 8
        state.mask = 0
        reader.seek 0
        vectors = MLVifReadUnpack reader 0x6C018005 state
        if not (MLCheckVifVector state.memory[2] #(1,2,3,4)) do throw "VIF relative address wrapping failed."
        reader.closeFile()
        writer.openFile path
        writer.short 0x801F
        writer.short 0
        writer.closeFile()
        reader.openFile path
        state = MLVifState cycle:1 writes:2 mode:2 mask:0x00005500
        state.clearMemory()
        state.row = #(1,2,3,4)
        vectors = MLVifReadUnpack reader 0x7F020000 state
        if not (MLCheckVifVector vectors[1] #(248,0,0,128)) or not (MLCheckVifVector vectors[2] #(1,2,3,4)) do throw "Packed V4-5 fill applied arithmetic or lost row data."
        if reader.tell() != 4 or not (MLCheckVifVector state.row #(1,2,3,4)) do throw "Packed VIF fill changed row state or consumed extra data."
        reader.closeFile()
    )
    catch
    (
        reader.closeFile()
        writer.closeFile()
        throw()
    )
)
fn MLCheckMobileTextures folder =
(
    local reader = MLReader()
    try
    (
        for profile in #("4","8","32","tiny") do
        (
            local mip = if profile == "tiny" then 2 else 1
            local images = MLReadMobileTextures (MLRoot + "tests\\lcs_mobile_" + profile + ".txd") folder level:mip
            if images.count != 1 or not images[1][3] do throw "Mobile TXD transparency check failed."
            reader.openFile images[1][2]
            local dimension = if mip == 2 then 1 else 2
            if reader.atShort 12 != dimension or reader.atShort 14 != dimension do throw "Mobile TXD mip dimensions failed."
            reader.seek 18
            for pixel = 1 to dimension * dimension do
                if reader.byte() != 51 or reader.byte() != 34 or reader.byte() != 17 or reader.byte() != 68 do throw "Mobile TXD pixel channels failed."
            reader.closeFile()
        )
        for profile in #("flags","truncated") do
        (
            local rejected = false
            try (MLReadMobileTextures (MLRoot + "tests\\lcs_mobile_" + profile + ".txd") folder) catch (rejected = true)
            if not rejected do throw "Malformed Mobile TXD was accepted."
        )
    )
    catch (reader.closeFile(); throw())
)
fn MLCheckMdlBoneIDs =
(
    local nodes = #()
    try
    (
        local first = bonesys.createBone [0,0,0] [1,0,0] [0,0,1]
        append nodes first
        local second = bonesys.createBone [1,0,0] [2,0,0] [0,0,1]
        append nodes second
        local third = bonesys.createBone [2,0,0] [3,0,0] [0,0,1]
        append nodes third
        setUserProp second "MaxLeedsBoneID" 0
        setUserProp third "MaxLeedsBoneID" 7
        local ids = MLResolveMdlBoneIDs nodes
        if not (MLCheckVifVector ids #(1,0,7)) do throw "MDL new bone ID collided with a reserved ID."
        setUserProp third "MaxLeedsBoneID" 0
        local rejected = false
        try (MLResolveMdlBoneIDs nodes) catch (rejected = true)
        if not rejected do throw "Duplicate MDL animation IDs were accepted."
        setUserProp third "MaxLeedsBoneID" 256
        rejected = false
        try (MLResolveMdlBoneIDs nodes) catch (rejected = true)
        if not rejected do throw "Out-of-range MDL animation ID was accepted."
        for node in nodes where isValidNode node do delete node
    )
    catch
    (
        for node in nodes where isValidNode node do delete node
        throw()
    )
)
fn MLCheckVcsSkinOrder folder =
(
    local created = #()
    try
    (
        local parentBone = bonesys.createBone [0,0,0] [1,0,0] [0,0,1]
        append created parentBone
        local childBone = bonesys.createBone [1,0,0] [2,0,0] [0,0,1]
        append created childBone
        local tipBone = bonesys.createBone [2,0,0] [3,0,0] [0,0,1]
        append created tipBone
        childBone.parent = parentBone
        tipBone.parent = childBone
        setUserProp parentBone "MaxLeedsBoneID" 7
        setUserProp childBone "MaxLeedsBoneID" 8
        setUserProp tipBone "MaxLeedsBoneID" 9
        local order = MLMdlFrameOrder #(childBone,parentBone,tipBone)
        if not (MLCheckVifVector order #(2,1,3)) do throw "MDL depth-first frame ordering failed."
        local node = mesh vertices:#([0,0,0],[1,0,0],[0,1,0]) faces:#([1,2,3])
        append created node
        local modifier = Skin()
        addModifier node modifier
        select node
        setCommandPanelTaskMode #modify
        modPanel.setCurrentObject modifier
        skinOps.addBone modifier parentBone 0
        skinOps.addBone modifier childBone 0
        skinOps.addBone modifier tipBone 1
        local parentID = 0
        local tipID = 0
        for index = 1 to (skinOps.GetNumberBones modifier) do
        (
            local name = skinOps.GetBoneName modifier index 0
            if name == parentBone.name do parentID = index
            if name == tipBone.name do tipID = index
        )
        if parentID == 0 or tipID == 0 do throw "Skin regression could not resolve its bones."
        for vertex = 1 to 3 do skinOps.ReplaceVertexWeights modifier vertex #(parentID,tipID) #(0.25,0.75)
        for platform in #("PS2","PSP") do
        (
            local path = folder + "\\vcs_skin_order_" + platform + ".mdl"
            local selectionNodes = #(childBone,node,parentBone,tipBone)
            if platform == "PS2" then MLWritePs2Object path selectionNodes "VCS" 101 else MLWritePspObject path selectionNodes "VCS" 101
            local model = MLReadModel path "VCS" platform
            local vertices = 0
            for part in model.parts do for influences in part.weights do
            (
                local parentWeight = 0.0
                local tipWeight = 0.0
                for influence in influences do
                (
                    local id = model.frames[influence[1]].boneID
                    if id == 7 then parentWeight += influence[2]
                    else if id == 9 then tipWeight += influence[2]
                    else throw "VCS Skin weight moved to the wrong animation bone."
                )
                if abs (parentWeight - 0.25) > 0.001 or abs (tipWeight - 0.75) > 0.001 do throw "VCS reordered skeleton lost skin weights."
                vertices += 1
            )
            if vertices != 3 do throw "VCS reordered skeleton regression lost vertices."
        )
        for node in created where isValidNode node do delete node
    )
    catch
    (
        for node in created where isValidNode node do delete node
        throw()
    )
)
fn MLCheckVcsModels folder =
(
    local nodes = #()
    local reader = MLReader()
    try
    (
        if not (MLMdlIsAtomic 0x01F40400 "PSP") or (MLMdlIsAtomic 0x01F40400 "PS2") do throw "VCS alternate PSP atomic classification failed."
        for position in #([10,20,30],[-5,4,2]) do
        (
            local node = mesh vertices:#([0,0,0],[1,0,0],[0,1,0]) faces:#([1,2,3])
            append nodes node
            node.pos = position
            node.material = standardMaterial name:"vcs_check"
        )
        for platform in #("PS2","PSP") do for count = 1 to 2 do
        (
            local path = folder + "\\vcs_" + platform + "_" + count as string + ".mdl"
            local selectionNodes = for index = 1 to count collect nodes[index]
            if platform == "PS2" then MLWritePs2Object path selectionNodes "VCS" 101 else MLWritePspObject path selectionNodes "VCS" 101
            reader.openFile path
            local top = reader.atLong 0x20
            local expected = if count == 1 then (if platform == "PS2" then 0x0004AA01 else 0x00041601) else (if platform == "PS2" then 0x0000AA02 else 2)
            if reader.atLong top != expected do throw "VCS platform-specific model tag failed."
            reader.closeFile()
            local model = MLReadModel path "VCS" platform
            if model.parts.count != count or model.modelID != 101 do throw "VCS model structure round trip failed."
            for index = 1 to count do
            (
                local part = model.parts[index]
                local transform = matrix3 1
                for frame in model.frames where frame.pointer == part.framePointer do transform = frame.worldMatrix
                local found = false
                for vertex in part.vertices where (distance (vertex * transform) nodes[index].pos) < 0.02 do found = true
                if not found do throw "VCS model frame placement round trip failed."
            )
        )
        for node in nodes where isValidNode node do delete node
    )
    catch
    (
        reader.closeFile()
        for node in nodes where isValidNode node do delete node
        throw()
    )
)
fn MLCheckLcsModels folder =
(
    local node = undefined
    try
    (
        for profile in #("standard","leeds") do
        (
            local models = MLReadMobileDff (MLRoot + "tests\\lcs_mobile_" + profile + ".dff")
            if models.count != 1 do throw "Mobile DFF clump count failed."
            local model = models[1]
            if model.platform != "Mobile" or model.game != "LCS" or model.frames.count != 2 or model.parts.count != 2 do throw "Mobile DFF model structure failed."
            if model.frames[2].parentPointer != 1 or (distance model.frames[2].worldMatrix.row4 [10,0,0]) > 0.00001 do throw "Mobile DFF parent transform failed."
            if model.materials.count != 4 or model.materials[2].name != "lcs_test" do throw "Mobile DFF shared material resolution failed."
            local part = model.parts[1]
            if part.vertices.count != 3 or part.faces.count != 1 do throw "Mobile DFF triangle decoding failed."
            if profile == "leeds" then
            (
                if abs (part.vertices[2].x - 0.50001024) > 0.00001 or abs (part.uv[2].x - 2.0) > 0.00001 do throw "Mobile DFF native position/UV scaling failed."
                if part.weights.count != 3 or part.weights[1].count != 2 do throw "Mobile DFF skin stream failed."
                if model.frames[part.weights[1][1][1]].boneID != 7 or model.frames[part.weights[1][2][1]].boneID != 8 do throw "Mobile DFF HAnim mapping failed."
                if abs (part.weights[1][1][2] - 0.25) > 0.00001 do throw "Mobile DFF weight decoding failed."
            )
            else if (distance part.vertices[2] [1,0,0]) > 0.00001 or part.faceIDs[1] != 2 do throw "Mobile standard DFF geometry failed."
        )
        node = mesh name:"LCS_platform_check" vertices:#([0,0,0],[1,0,0],[0,1,0]) faces:#([1,2,3])
        meshop.setMapSupport node 1 true
        meshop.setNumMapVerts node 1 3
        meshop.setNumMapFaces node 1 1
        meshop.setMapVert node 1 1 [0,1,0]
        meshop.setMapVert node 1 2 [1,1,0]
        meshop.setMapVert node 1 3 [0,0,0]
        meshop.setMapFace node 1 1 [1,2,3]
        local material = multiMaterial numsubs:1
        material.materialIDList = #(42)
        material.materialList[1] = standardMaterial name:"lcs_sparse"
        node.material = material
        setFaceMatID node 1 42
        for platform in #("PS2","PSP") do
        (
            local path = folder + "\\lcs_" + platform + ".mdl"
            if platform == "PS2" then MLWritePs2Object path #(node) "LCS" 42 else MLWritePspObject path #(node) "LCS" 42
            local model = MLReadModel path "LCS" platform
            if model.modelID != 42 or model.materials[1].name != "lcs_sparse" do throw "LCS MDL identity/material round trip failed."
            local highU = false
            for part in model.parts do for uv in part.uv do
            (
                if uv.x < -0.00001 or uv.y < -0.00001 do throw "LCS MDL unsigned UV became negative."
                if abs (uv.x - 1.0) < 0.01 do highU = true
            )
            if not highU do throw "LCS MDL high-byte UV did not round trip."
        )
        local tiled = #([-2.0,3.0,0],[4.0,-1.0,0],[0.5,0.25,0])
        for index = 1 to 3 do meshop.setMapVert node 1 index tiled[index]
        for platform in #("PS2","PSP") do
        (
            local path = folder + "\\lcs_tiled_" + platform + ".mdl"
            if platform == "PS2" then MLWritePs2Object path #(node) "LCS" 42 else MLWritePspObject path #(node) "LCS" 42
            local model = MLReadModel path "LCS" platform
            for expected in tiled do
            (
                local found = false
                for part in model.parts do for uv in part.uv where (distance uv expected) < 0.04 do found = true
                if not found do throw "LCS tiled or negative MDL UV failed to round trip."
            )
        )
        delete node; node = undefined
    )
    catch
    (
        if isValidNode node do delete node
        throw()
    )
)

fn MLCheckWorldPlacement folder =
(
    local root = undefined
    local placement = undefined
    local writer = MLWriter()
    local reader = MLReader()
    local source = folder + "\\placement_source.img"
    local output = folder + "\\placement_edited.img"
    try
    (
        writer.openFile source
        writer.short 3; writer.short 7
        writer.zeros 12
        for row = 1 to 4 do
        (
            writer.point (matrix3 1)[row]
            writer.long 0x12345678
        )
        writer.closeFile()
        root = dummy boxsize:[1,1,1]
        placement = dummy boxsize:[1,1,1]
        placement.parent = root
        setUserProp root "MaxLeedsRoot" true
        setUserProp root "MaxLeedsIMG" source
        setUserProp root "MaxLeedsIMGHash" (MLFileDigest source)
        setUserProp placement "MaxLeedsPlacementAddresses" "0,100,200,0;"
        setUserProp placement "MaxLeedsResourceID" "7"
        setUserProp placement "MaxLeedsIPLID" "3"
        placement.transform = transMatrix [110,220,30]
        if MLWriteWorldPlacements output #(root,placement) != 1 do throw "World placement export count failed."
        reader.openFile output
        if (distance (reader.matrix 16).row4 [10,20,30]) > 0.00001 do throw "World sector origin was not removed on export."
        if (reader.atShort 0) != 3 or (reader.atShort 2) != 7 do throw "World placement identifiers changed."
        for row = 0 to 3 do if (reader.atLong (28 + row * 16)) != 0x12345678 do throw "World matrix padding changed."
        reader.closeFile()
        local outputDigest = MLFileDigest output
        setUserProp placement "MaxLeedsPlacementAddresses" "0,100,200,0;16,100,200,0;"
        local rejectedOverlap = false
        try (MLWriteWorldPlacements output #(root,placement))
        catch (rejectedOverlap = (findString (getCurrentException() as string) "overlap") != undefined)
        if not rejectedOverlap or (MLFileDigest output) != outputDigest do throw "Overlapping placements were accepted or changed the destination."
        delete placement; placement = undefined
        delete root; root = undefined
    )
    catch
    (
        reader.closeFile(); writer.closeFile()
        if isValidNode placement do delete placement
        if isValidNode root do delete root
        throw()
    )
)

fn MLCheckTools =
(
    local node = undefined
    local bone = undefined
    local collisionBox = undefined
    local stripNode = undefined
    local rigidPart = undefined
    local textureBitmap = undefined
    local effectsRoot = undefined
    local mhRoot = undefined
    local writer = MLWriter()
    local reader = MLReader()
    local savedSelection = selection as array
    local guidClass = dotNetClass "System.Guid"
    local guidValue = guidClass.NewGuid()
    local token = guidValue.ToString()
    local folder = (getDir #temp) + "\\MaxLeeds-check-" + token
    local binaryPath = folder + "\\values.bin"
    local modelPath = folder + "\\triangle.mdl"
    local collisionPath = folder + "\\triangle.col2"
    local texturePath = folder + "\\check_texture.tga"
    local dictionaryPath = folder + "\\check_textures.xtx"
    local textureFolder = folder + "\\decoded"
    local effectPath = folder + "\\GAME.DAT"
    local effectOutput = folder + "\\GAME_edited.DTZ"
    local animationPath = folder + "\\check.anim"
    local ifpPath = folder + "\\check.ifp"
    local compressedPath = folder + "\\check_compressed.ifp"
    local animationSource = undefined
    try
    (
        makeDir folder all:true
        MLCheckWorldPlacement folder
        writer.openFile binaryPath
        writer.long 0x7F123456
        writer.signedShort -1234
        writer.float 1.25
        writer.closeFile()
        reader.openFile binaryPath
        if reader.long() != 0x7F123456 or reader.signedShort() != -1234 or (abs (reader.float() - 1.25)) > 0.00001 do throw "Binary stream checks failed."
        reader.closeFile()
        for platform in #("pc","ps2","psp") do
        (
            local textureFixture = MLRoot + "tests\\texture_" + platform
            local replacedPath = folder + "\\replaced_" + platform + ".tex"
            local replacements = MLReplaceManhuntTextures (textureFixture + "_source.tex") (textureFixture + "_donor.tex") replacedPath
            if replacements != 1 or (MLFileDigest replacedPath) != (MLFileDigest (textureFixture + "_expected.tex")) do throw "Texture dictionary replacement changed unexpected bytes."
        )
        local ddsOutput = folder + "\\replaced_dds.tex"
        MLReplaceManhuntTextures (MLRoot + "tests\\texture_pc_source.tex") (MLRoot + "tests\\skin.dds") ddsOutput
        if (MLFileDigest ddsOutput) != (MLFileDigest (MLRoot + "tests\\texture_pc_expected.tex")) do throw "DDS replacement did not preserve the source dictionary."
        local previousDigest = MLFileDigest ddsOutput
        local invalidDds = folder + "\\skin.dds"
        copyFile (MLRoot + "tests\\wrong.dds") invalidDds
        local headerRejected = false
        try (MLReplaceManhuntTextures (MLRoot + "tests\\texture_pc_source.tex") invalidDds ddsOutput) catch (headerRejected = true)
        if not headerRejected or (MLFileDigest ddsOutput) != previousDigest do throw "Incompatible DDS header was accepted or overwrote the output."

        local rejected = false
        try (MLReplaceManhuntTextures (MLRoot + "tests\\texture_pc_source.tex") (MLRoot + "tests\\wrong.dds") ddsOutput) catch (rejected = true)
        if not rejected or (MLFileDigest ddsOutput) != previousDigest do throw "Rejected texture replacement overwrote the destination."
        MLReplaceManhuntTextures (MLRoot + "tests\\texture_pc_compressed.tex") (MLRoot + "tests\\skin.dds") ddsOutput
        local unpackedTextures = MLDecodeResource ddsOutput #("TCDT")
        local compressedMatch = (MLFileDigest unpackedTextures[1]) == previousDigest
        if unpackedTextures[2] do deleteFile unpackedTextures[1]
        if not compressedMatch do throw "Compressed texture replacement changed the payload."
        for rowSize in #(10,24) do
        (
            reader.openFile (MLRoot + "tests\\world_psp_" + rowSize as string + ".bin")
            local world = MLWorldReadMesh reader 0 reader.length 17 "VCS"
            reader.closeFile()
            if world == undefined or world[3] != "PSP" or world[1].vertices.count != 6 or world[1].faces.count != 2 do throw "PSP world material/vertex decoding failed."
            if (distance world[1].vertices[2] [0.5,0,0]) > 0.00001 or (distance world[1].uv[1] [1,0,0]) > 0.00001 do throw "PSP world coordinate or UV conversion failed."
            if world[1].uv[4].x != 0 or world[1].faceIDs[2] != 2 do throw "PSP world material assignment or zero UV scale was lost."
        )
        reader.openFile (MLRoot + "tests\\vif_fill.bin")
        local filled = MLReadPs2Geometry reader 0 "fill" 0 mh2:true
        reader.closeFile()
        if filled.count != 1 or filled[1].vertices.count != 3 or (distance filled[1].vertices[3] [-0.5,0.25,0]) > 0.00001 do throw "VIF STCYCL position fill failed."
        if (distance filled[1].uv[3] [1,0.5,0]) > 0.00001 do throw "VIF STROW UV fill failed."
        local boundsReader = MLReader length:2147483647
        local rejectedRange = false
        try (boundsReader.check 2147483640 16) catch (rejectedRange = true)
        if not rejectedRange do throw "Overflowing binary range was accepted."
        MLCheckMobileTextures folder
        MLCheckVcsSkinOrder folder
        MLCheckVcsModels folder
        MLCheckMdlBoneIDs()
        MLCheckLcsModels folder
        MLCheckVifUnpack folder
        local state = MLVifState()
        state.clearMemory()
        state.row = #(10,20,30,40)
        state.mode = 1
        local value = state.store 0 0 #(1,2,3,4) false false
        if not (MLCheckVifVector value #(11,22,33,44)) or not (MLCheckVifVector state.row #(10,20,30,40)) do throw "VIF offset arithmetic failed."
        state.mode = 2
        value = state.store 0 0 #(1,2,3,4) false false
        if not (MLCheckVifVector state.row #(11,22,33,44)) do throw "VIF difference arithmetic failed."
        state.mode = 3
        value = state.store 0 0 #(5,6,7,8) false false
        if not (MLCheckVifVector state.row #(5,6,7,8)) do throw "VIF row replacement mode failed."
        state.mode = 0
        state.column = #(90,91,92,93)
        state.mask = 0xE4
        value = state.store 0 0 #(1,2,3,4) true false
        if not (MLCheckVifVector value #(1,6,90,8)) do throw "VIF data/row/column/write-protect masking failed."
        state.writes = 0
        local rejectedCycle = false
        try (MLVifReadUnpack reader 0x6C010000 state) catch (rejectedCycle = (findString (getCurrentException() as string) "Invalid VIF cycle state.") != undefined)
        if not rejectedCycle do throw "Invalid VIF cycle state was accepted."
        state.writes = 1
        if MLVifWord (2147483647L + 1) != -2147483648 do throw "VIF arithmetic did not wrap at 32 bits."
        local halfValues = #(0.0,0.000000059604644775390625,0.00006103515625,0.333251953125,1.0,-2.0,65504.0)
        for value in halfValues do
            if (MLAnimHalf (MLAnimPackHalf value)) != value do throw "ANIM half-float round trip failed."
        local animationTrack = MLAnimTrack flags:23 boneKey:1 boneID:1 keys:#(
            MLAnimKey seconds:0.0 rotation:(quat 0 0 0 1) position:[0,0,0],
            MLAnimKey seconds:0.125 rotation:(quat 0 0 0 1) position:[1,2,3] scaling:[2,2,2])
        local animation = MLAnimFile clips:#(MLAnimClip name:"check" duration:0.125 tracks:#(animationTrack))
        MLWriteAnimations animationPath animation
        local loadedAnimation = MLReadAnimations animationPath
        if loadedAnimation.clips.count != 1 or loadedAnimation.clips[1].tracks[1].keys.count != 2 do throw "ANIM clip table round trip failed."
        local loadedKey = loadedAnimation.clips[1].tracks[1].keys[2]
        if loadedKey.seconds != 0.125 or loadedKey.position != [1,2,3] or loadedKey.scaling != [2,2,2] do throw "ANIM transform round trip failed."
        if MLAnimBoneID 0 0xB88A0000 != 1 do throw "ANIM hash-to-bone mapping failed."
        local ifpTrack = MLAnimTrack flags:19 boneID:1000 boneKey:1000 keys:#(
            MLAnimKey seconds:0.0 rotation:(quat 0 0 0 1) position:[0,0,0],
            MLAnimKey seconds:0.125 rotation:(quat 0 0 0 1) position:[1,2,3])
        local ifpClip = MLAnimClip name:"check_ifp" duration:0.125 tracks:#(ifpTrack)
        for game in #("MH1","MH2") do
        (
            MLWriteManhuntAnimation ifpPath ifpClip "MaxLeeds" game
            animationSource = MLReadIfpIndex ifpPath
            if animationSource.clips.count != 1 or animationSource.clips[1].trackCount != 1 or animationSource.clips[1].keyCount != 2 do throw "IFP index round trip failed."
            local loadedClip = MLReadIfpClip animationSource 1
            local key = loadedClip.tracks[1].keys[2]
            if (abs (key.seconds - 0.125)) > 0.00001 or (distance key.position [1,2,3]) > 0.001 do throw "IFP timing or coordinate conversion failed."
            MLCloseAnimationSource animationSource
            animationSource = undefined
        )
        animationSource = MLReadIfpIndex ifpPath
        local replacementIfp = folder + "\\replaced.ifp"
        MLReplaceManhuntAnimation replacementIfp animationSource 1 ifpClip
        if (MLFileDigest replacementIfp) != (MLFileDigest ifpPath) do throw "No-op IFP replacement did not preserve its exact bytes."
        MLCloseAnimationSource animationSource; animationSource = undefined
        MLMhWriteCompressed ifpPath compressedPath
        animationSource = MLReadIfpIndex compressedPath
        if not animationSource.ownsDecoded or animationSource.clips.count != 1 do throw "Z2HM animation decoding failed."
        if (MLFileDigest ifpPath) != (MLFileDigest animationSource.decodedPath) do throw "Z2HM compression changed the decoded payload."
        MLCloseAnimationSource animationSource
        animationSource = undefined
        if (MLSafeTextureStem "CON") != "texture_CON" do throw "Reserved texture filename protection failed."
        for platform in #("ps2","psp") do
        (
            local fixture = MLRoot + "tests\\manhunt_" + platform + ".bsp"
            local world = MLReadManhuntWorld fixture
            if world.parts.count != 1 or world.parts[1].vertices.count != 3 or world.parts[1].faces.count != 1 do throw "Manhunt world geometry decoding failed."
            local conversion = rotateXMatrix 90
            if (distance world.parts[1].vertices[2] ([6,6,7] * conversion)) > 0.0001 do throw "Manhunt world coordinate conversion failed."
            if (distance world.parts[1].uv[1] [0.5,-1,0]) > 0.0001 do throw "Manhunt world UV scale decoding failed."
        )
        local mhModel = MLReadManhunt (MLRoot + "tests\\manhunt_pc.mdl")
        MLBuildModel mhModel
        mhRoot = selection[1]
        if not (MLUserFlag mhRoot "MaxLeedsRoot") do throw "Model root metadata was not recognized."
        local mhFamily = MLSelectedFamily()
        local oldMesh = undefined
        for candidate in mhFamily where (superclassof candidate) == GeometryClass do oldMesh = candidate
        local replacement = mesh name:"MaxLeeds_check_mh_rebuild" vertices:#([0,0,0],[1,0,0],[0,0,1],[1,0,1]) faces:#([1,2,3],[3,2,4])
        replacement.parent = mhRoot
        replacement.material = oldMesh.material
        setUserProp replacement "MaxLeedsAtomic" (getUserProp oldMesh "MaxLeedsAtomic")
        meshop.setMapSupport replacement 1 true
        meshop.setNumMapVerts replacement 1 4
        meshop.setNumMapFaces replacement 1 2
        for index = 1 to 4 do meshop.setMapVert replacement 1 index (#([0,0,0],[1,0,0],[0,1,0],[1,1,0])[index])
        meshop.setMapFace replacement 1 1 [1,2,3]
        meshop.setMapFace replacement 1 2 [3,2,4]
        delete oldMesh
        select mhRoot
        local mhReport = MLWriteManhuntPcRebuild modelPath (MLSelectedFamily())
        local rebuiltMh = MLReadManhunt modelPath
        if mhReport[3] != 2 or rebuiltMh.parts[1].faces.count != 2 or rebuiltMh.parts[1].vertices.count != 4 do throw "Manhunt PC topology rebuild failed."
        local newMaterials = multiMaterial numsubs:2
        newMaterials.materialList[1] = standardMaterial name:"new_diffuse_a" diffuse:(color 255 0 0)
        newMaterials.materialList[2] = standardMaterial name:"new_diffuse_b" diffuse:(color 0 255 0)
        replacement.material = newMaterials
        -- Reversed, sparse IDs expose accidental materialList[faceID] indexing.
        newMaterials.materialIDList = #(42,7)
        setFaceMatID replacement 1 42
        setFaceMatID replacement 2 7
        if (MLMhSceneMaterial newMaterials 42) != newMaterials.materialList[1] do throw "Sparse material ID resolution failed."
        newMaterials.materialIDList = #(42,42)
        local rejectedMaterial = false
        try (MLMhSceneMaterial newMaterials 42) catch (rejectedMaterial = true)
        if not rejectedMaterial do throw "Duplicate used material IDs were accepted."
        newMaterials.materialIDList = #(42,7)
        MLWriteManhuntPcRebuild modelPath (MLSelectedFamily()) rebuildMaterials:true
        local materialRebuild = MLReadManhunt modelPath
        if materialRebuild.materials.count != 2 or materialRebuild.materials[1].name != "new_diffuse_b" or materialRebuild.materials[2].name != "new_diffuse_a" do throw "New Manhunt native material slots failed to round trip."
        if materialRebuild.parts[1].faceIDs[1] != 1 or materialRebuild.parts[1].faceIDs[2] != 2 do throw "Rebuilt Manhunt material face assignments changed."
        local skeletonRoot = boneSys.createBone [0,0,0] [0,1,0] [0,0,1]
        skeletonRoot.name = "Bip01"
        skeletonRoot.parent = mhRoot
        setUserProp skeletonRoot "MaxLeedsBoneID" 1000
        local skeletonChild = boneSys.createBone [0,1,0] [0,2,0] [0,0,1]
        skeletonChild.name = "new_bone"
        skeletonChild.parent = skeletonRoot
        setUserProp skeletonChild "MaxLeedsBoneID" 1200
        select mhRoot
        MLWriteManhuntPcRebuild modelPath (MLSelectedFamily()) rebuildMaterials:true rebuildSkeleton:true
        local savedProperties = getUserPropBuffer skeletonRoot
        local savedDigest = MLFileDigest modelPath
        setUserProp skeletonRoot "MaxLeedsFrame" 0
        local rejectedFrame = false
        try (MLWriteManhuntPcRebuild modelPath (MLSelectedFamily()) rebuildMaterials:true rebuildSkeleton:true)
        catch (rejectedFrame = (findString (getCurrentException() as string) "different source skeleton") != undefined)
        setUserPropBuffer skeletonRoot savedProperties
        if not rejectedFrame or (MLFileDigest modelPath) != savedDigest do throw "Invalid skeleton metadata was accepted or changed the destination."
        local skeletonRebuild = MLReadManhunt modelPath
        if skeletonRebuild.frames.count != 2 or skeletonRebuild.frames[2].boneID != 1200 or skeletonRebuild.frames[2].parentPointer != skeletonRebuild.frames[1].pointer do throw "Native skeleton/palette creation failed."
        local addedSkin = Skin()
        addModifier replacement addedSkin
        select replacement
        setCommandPanelTaskMode #modify
        modPanel.setCurrentObject addedSkin
        skinOps.addBone addedSkin skeletonRoot 0
        skinOps.addBone addedSkin skeletonChild 1
        local rootSkinID = 0
        local childSkinID = 0
        for index = 1 to (skinOps.GetNumberBones addedSkin) do
        (
            local name = skinOps.GetBoneName addedSkin index 0
            if name == skeletonRoot.name do rootSkinID = index
            if name == skeletonChild.name do childSkinID = index
        )
        if rootSkinID == 0 or childSkinID == 0 do throw "Skin did not register the conversion test bones."
        for vertex = 1 to replacement.numverts do skinOps.ReplaceVertexWeights addedSkin vertex #(rootSkinID,childSkinID) #(0.25,0.75)
        select mhRoot
        local rigidDigest = MLFileDigest modelPath
        local rejectedConversion = false
        try (MLWriteManhuntPcRebuild modelPath (MLSelectedFamily()) rebuildMaterials:true)
        catch (rejectedConversion = (findString (getCurrentException() as string) "enable Rebuild skeleton") != undefined)
        if not rejectedConversion or (MLFileDigest modelPath) != rigidDigest do throw "Rigid-to-skin conversion without palette rebuilding changed the destination."
        MLWriteManhuntPcRebuild modelPath (MLSelectedFamily()) rebuildMaterials:true rebuildSkeleton:true
        local converted = MLReadManhunt modelPath
        local convertedPart = converted.parts[1]
        if convertedPart.weights.count != convertedPart.vertices.count or convertedPart.weights.count == 0 do throw "Rigid-to-skin conversion did not create a skin stream."
        for influences in convertedPart.weights do
        (
            if influences.count != 2 do throw "Rigid-to-skin conversion lost a bone influence."
            local rootWeight = 0.0
            local childWeight = 0.0
            for influence in influences do
            (
                local id = converted.frames[influence[1]].boneID
                if id == 1000 then rootWeight += influence[2]
                else if id == 1200 then childWeight += influence[2]
                else throw "Rigid-to-skin conversion assigned an unexpected bone."
            )
            if abs (rootWeight - 0.25) > 0.00001 or abs (childWeight - 0.75) > 0.00001 do throw "Rigid-to-skin conversion changed bone weights."
        )
        reader.openFile modelPath
        local convertedHeader = reader.atLong (convertedPart.atomicPointer + 12)
        if (reader.atLong (convertedHeader + 144)) != 0x115E or (reader.atLong (convertedHeader + 96)) != 52 do throw "Rigid-to-skin conversion did not update its vertex declaration and stride."
        reader.closeFile()
        deleteModifier replacement addedSkin
        delete skeletonChild; delete skeletonRoot
        delete replacement
        delete mhRoot
        mhRoot = undefined
        local uvMaterial = standardMaterial()
        local uvMap = bitmapTexture()
        setAppData uvMaterial 0x4D4C0001 "VCS|49408"
        if not (MLApplyNativeWorldUV uvMaterial uvMap) do throw "VCS scrolling UV setup failed."
        local uvOffset = 0.0
        at time 6f uvOffset = uvMap.coords.U_Offset
        if (abs (uvOffset - 0.25)) > 0.00001 do throw "VCS scrolling UV phase failed."
        at time 21f uvOffset = uvMap.coords.U_Offset
        if (abs uvOffset) > 0.00001 do throw "VCS scrolling UV wrap failed."
        for game in #("lcs","vcs") do
        (
            reader.openFile (MLRoot + "tests\\world_" + game + ".bin")
            local parsed = MLWorldReadMesh reader 64 reader.length 1 (toUpper game)
            reader.closeFile()
            if parsed == undefined or parsed[1].vertices.count != 3 or parsed[1].colors.count != 3 do throw "Retail world strip / prelight decoding failed."
            if parsed[2][1].name != "tex_7" or parsed[1].uv[1] != [0,0,0] do throw "Ambiguous LCS/VCS material layout or zero UV scale decoding failed."
            if parsed[1].colors[1] != (color 0 0 255 255) do throw "World vertex colors did not decode correctly."
        )
        local mipLevels = MLMhMipChain 3 1 #(color 255 0 0 255,color 0 0 255 0,color 0 255 0 255) true
        if mipLevels.count != 2 or mipLevels[2][1] != 1 or mipLevels[2][2] != 1 do throw "Odd-sized mip dimensions failed."
        local mipPixel = mipLevels[2][3][1]
        if abs (mipPixel.r - 127.5) > 0.01 or abs (mipPixel.g - 127.5) > 0.01 or mipPixel.b != 0 or abs (mipPixel.a - 170) > 0.01 do throw "Mip filtering lost an edge pixel or introduced transparent colour bleed."
        for format in #("DXT1","DXT3","DXT5") do
        (
            local blockPath = folder + "\\block_" + format + ".bin"
            writer.openFile blockPath
            MLMhWriteDxt writer 4 4 (for index = 1 to 16 collect (color 255 0 0 255)) format
            writer.closeFile()
            if (MLFileDigest blockPath) != (MLFileDigest (MLRoot + "tests\\opaque_" + format + ".bin")) do throw "DXT opaque block encoding differs from its golden fixture."
        )
        local exactPixels = #(color 1 2 3 255, color 2 3 4 255, color 1 2 3 255, color 0 0 0 0)
        local exactResult = MLQuantize exactPixels 16
        for index = 1 to exactPixels.count do
        (
            local actual = exactResult[1][exactResult[2][index] + 1]
            for component = 1 to 4 do if actual[component] != exactPixels[index][component] do throw "Indexed palette lost an exact input color."
        )
        local layout = MLPspLayout 0x1FF
        if layout[3] != 36 do throw "PSP vertex stride checks failed."
        if MLPspAddress 16 8 32 != 384 do throw "PSP raster addressing checks failed."
        if (abs ((MLWorldHalf 0x3C00) - 1.0)) > 0.000001 do throw "LVZ half-float decoding failed."
        textureBitmap = MLTgaWriter()
        textureBitmap.openFile texturePath 8 8
        for row = 0 to 7 do textureBitmap.writeRow (for pixel = 1 to 8 collect (if mod pixel 2 == 0 then color 255 0 0 255 else color 0 0 255 128))
        textureBitmap.closeFile()
        textureBitmap = undefined
        for format in #("RGBA32","DXT1","DXT3","DXT5") do
        (
            local encodedPath = folder + "\\mips_" + format + ".tex"
            MLWriteManhuntTextures encodedPath #(texturePath) "PC" 32 mipmapsEnabled:true compression:format
            MLOpenResource reader encodedPath "TCDT"
            local entry = (MLMhTextureRecords reader)[1]
            if (reader.atLong (entry[3] + 28)) != 4 do throw "The generated DDS is missing mip levels."
            local expectedSize = if format == "RGBA32" then 468 else if format == "DXT1" then 184 else 240
            if entry[4] != expectedSize do throw "The generated DDS mip byte count is wrong."
            reader.closeFile()
        )
        local invalidPitchPath = folder + "\\invalid_pitch.dds"
        writer.openFile invalidPitchPath
        MLMhWriteDds writer (MLMhMipChain 8 8 (for index = 1 to 64 collect (color 255 0 0 255)) false) "RGBA32"
        writer.patchLong 20 2147483647
        writer.closeFile()
        local protectedTexture = folder + "\\mips_RGBA32.tex"
        local protectedDigest = MLFileDigest protectedTexture
        local rejectedPitch = false
        try (MLWriteManhuntTextures protectedTexture #(invalidPitchPath) "PC" 32)
        catch (rejectedPitch = (findString (getCurrentException() as string) "truncated") != undefined)
        if not rejectedPitch or (MLFileDigest protectedTexture) != protectedDigest do throw "Oversized DDS pitch was accepted or changed the destination."
        for platform in #("PS2","PSP") do for depth in #(4,8,16,32) do
        (
            local encodedPath = folder + "\\console_mips_" + platform + depth as string + ".tex"
            MLWriteManhuntTextures encodedPath #(texturePath) platform depth mipmapsEnabled:true
            MLOpenResource reader encodedPath "TCDT"
            local entry = (MLMhTextureRecords reader)[1]
            reader.seek (entry[2] + 92)
            if reader.byte() != 4 do throw "Console mip count was not written."
            local size = 0
            for level = 0 to 3 do
            (
                local width = bit.shift 8 (-level)
                if platform == "PSP" then size += (amax 16 (((width * depth + 7) / 8) as integer)) * (MLAlign width 8)
                else size += ((width * width * depth + 7) / 8) as integer
            )
            if entry[4] != size do throw "Console mip raster size is incorrect."
            if depth <= 8 and entry[5] < entry[3] + size do throw "Console mipmaps overlap the shared palette."
            reader.closeFile()
        )
        for platform in #("PC","PS2","PSP") do for depth in (if platform == "PC" then #(32) else #(4,8,16,32)) do
        (
            local encodedPath = folder + "\\encoded_" + platform + depth as string + ".tex"
            MLWriteManhuntTextures encodedPath #(texturePath) platform depth
            local extracted = MLReadManhuntTextures encodedPath platform (folder + "\\decode_" + platform + depth as string)
            if extracted.count != 1 do throw "New Manhunt dictionary did not decode."
            reader.openFile extracted[1][2]
            local pixelOffset = if platform == "PC" then 128 else 18
            reader.seek pixelOffset
            local blue = reader.byte(); local green = reader.byte(); local red = reader.byte(); local alpha = reader.byte()
            reader.closeFile()
            if blue != 255 or green != 0 or red != 0 or abs (alpha - (if depth == 16 then 255 else 128)) > 1 do throw "Manhunt encoded colour/alpha did not round trip."
        )
        for target in #("PS2", "PSP") do
        (
            MLWriteTextures dictionaryPath #(texturePath) target 8
            local decoded = MLReadTextures dictionaryPath "Auto" textureFolder
            if decoded.count != 1 or decoded[1][1] != "check_texture" do throw (target + " texture read/write checks failed.")
            if decoded[1][3] != true do throw (target + " texture transparency was lost.")
        )
        node = mesh name:"MaxLeeds_check_triangle" vertices:#([0,0,0],[1,0,0],[0,1,0]) faces:#([1,2,3])
        MLWritePspObject modelPath #(node) "VCS" 100
        local model = MLReadModel modelPath "VCS" "PSP"
        if model.parts.count != 1 or model.parts[1].vertices.count != 3 or model.modelID != 100 do throw "PSP model write/read checks failed."
        if distance model.parts[1].vertices[2] [1,0,0] > 0.00001 do throw "PSP model scale checks failed."
        MLWritePs2Object modelPath #(node) "VCS" 100
        model = MLReadModel modelPath "VCS" "PS2"
        if model.parts.count != 1 or model.parts[1].vertices.count != 3 or model.modelID != 100 do throw "PS2 model write/read checks failed."
        if distance model.parts[1].vertices[2] [1,0,0] > 0.001 do throw "PS2 model scale checks failed."
        stripNode = mesh name:"MaxLeeds_check_strip" vertices:#([0,0,0],[1,0,0],[0,1,0],[1,1,0]) faces:#([1,2,3],[3,2,4])
        MLWritePspObject modelPath #(stripNode) "VCS" 100
        model = MLReadModel modelPath "VCS" "PSP"
        if model.parts[1].vertices.count != 4 or model.parts[1].faces.count != 2 do throw "PSP triangle strip export failed."
        MLWritePs2Object modelPath #(stripNode) "VCS" 100
        model = MLReadModel modelPath "VCS" "PS2"
        if model.parts[1].vertices.count != 4 or model.parts[1].faces.count != 2 do throw "PS2 triangle strip export failed."
        delete stripNode
        stripNode = undefined
        bone = boneSys.createBone [0,0,0] [0,0,1] [1,0,0]
        bone.name = "MaxLeeds_check_bone"
        local skin = Skin()
        addModifier node skin
        select node
        setCommandPanelTaskMode #modify
        modPanel.setCurrentObject skin
        skinOps.addBone skin bone 1
        for vertex = 1 to 3 do skinOps.ReplaceVertexWeights skin vertex #(1) #(1.0)
        MLWritePspObject modelPath #(node,bone) "VCS" 100
        model = MLReadModel modelPath "VCS" "PSP"
        if model.parts[1].weights.count != 3 or model.frames.count != 2 do throw "PSP character skin round trip failed."
        MLWritePs2Object modelPath #(node,bone) "VCS" 100
        model = MLReadModel modelPath "VCS" "PS2"
        if model.parts[1].weights.count != 3 or model.frames.count != 2 do throw "PS2 character skin round trip failed."
        rigidPart = mesh name:"MaxLeeds_check_rigid" vertices:#([0,0,0],[1,0,0],[0,1,0]) faces:#([1,2,3])
        rigidPart.pos = [2,0,0]
        MLWritePspObject modelPath #(node,bone,rigidPart) "VCS" 100
        model = MLReadModel modelPath "VCS" "PSP"
        if model.parts.count != 2 or model.frames.count != 3 do throw "PSP mixed ClumpModel export failed."
        MLWritePs2Object modelPath #(node,bone,rigidPart) "VCS" 100
        model = MLReadModel modelPath "VCS" "PS2"
        if model.parts.count != 2 or model.frames.count != 3 do throw "PS2 mixed ClumpModel export failed."
        deleteModifier node skin
        delete bone
        bone = undefined
        MLWritePspObject modelPath #(node,rigidPart) "VCS" 100
        model = MLReadModel modelPath "VCS" "PSP"
        if model.parts.count != 2 or model.frames.count != 3 do throw "PSP rigid multi-part export failed."
        MLWritePs2Object modelPath #(node,rigidPart) "VCS" 100
        model = MLReadModel modelPath "VCS" "PS2"
        if model.parts.count != 2 or model.frames.count != 3 do throw "PS2 rigid multi-part export failed."
        delete rigidPart
        rigidPart = undefined
        collisionBox = box name:"MaxLeeds_check_box" width:1 length:1 height:1
        collisionBox.pos = [0.5,0.5,0.5]
        setUserProp collisionBox "MaxLeedsCollision" "Box"
        setUserProp collisionBox "MaxLeedsResourceID" 100
        setUserProp node "MaxLeedsResourceID" 100
        MLWriteCollision collisionPath #(node,collisionBox)
        reader.openFile collisionPath
        if (reader.text 0 4) != "2loc" do throw "Collision header checks failed."
        local pointer = reader.atLong 0x24
        if (reader.atShort (pointer + 0x34)) != 1 do throw "Collision triangle count checks failed."
        if (reader.atShort (pointer + 0x32)) != 1 do throw "Collision box count checks failed."
        if (mod reader.length 2048) != 0 do throw "Collision sector padding checks failed."
        reader.closeFile()
        writer.openFile effectPath
        writer.zeros 0xA0
        writer.patchLong 0 0x47544147
        writer.patchLong 8 0xA0
        writer.patchLong 0x54 1
        writer.patchLong 0x58 0x60
        writer.seek 0x60
        writer.float 1.0
        writer.float 2.0
        writer.float 3.0
        writer.float 1.0
        writer.byte 255
        writer.byte 128
        writer.byte 64
        writer.byte 255
        writer.byte 0
        writer.seek (0x60 + 24)
        writer.float 20.0
        writer.float 15.0
        writer.float 2.0
        writer.float 5.0
        writer.closeFile()
        local effectReport = MLReadWorldEffects effectPath
        if effectReport[1] != 1 do throw "2D effect descriptor import failed."
        effectsRoot = MLWorldFXRoots()
        local markers = MLWorldFXMarkers effectsRoot
        if markers.count != 1 or (abs ((MLWorldFXValue markers[1] "LightSize" 0.0) - 2.0)) > 0.0001 do throw "2D effect light parsing failed."
        MLWorldFXProperty markers[1] "LightSize" 7.5
        if (MLSaveWorldEffects effectsRoot effectOutput) != 1 do throw "2D effect export failed."
        local recompressed = MLInflateChunk effectOutput
        reader.openFile recompressed[1]
        if (abs ((reader.atFloat (0x60 + 32)) - 7.5)) > 0.0001 do throw "2D effect edited payload did not round trip."
        reader.closeFile()
        if recompressed[2] do deleteFile recompressed[1]
        delete effectsRoot
        effectsRoot = undefined
        delete collisionBox
        collisionBox = undefined
        delete node
        node = undefined
        for path in #(binaryPath,modelPath,collisionPath,texturePath,dictionaryPath,effectPath,effectOutput,animationPath,ifpPath,compressedPath) where doesFileExist path do deleteFile path
        for path in (getFiles (textureFolder + "\\*")) do deleteFile path
        if doesDirectoryExist textureFolder do (dotNetClass "System.IO.Directory").Delete textureFolder
        (dotNetClass "System.IO.Directory").Delete folder true
        select savedSelection
        "Binary, ANIM, MH1/MH2 IFP, Z2HM, Manhunt PC rebuild, PS2/PSP worlds, retail world strips, scrolling UVs, exact palettes, PS2/PSP textures, LVZ half-float, 2D Effect DAT/DTZ editing, ClumpModel, and COL2 checks passed."
    )
    catch
    (
        local reason = getCurrentException()
        reader.closeFile(); writer.closeFile()
        MLCloseAnimationSource animationSource
        if textureBitmap != undefined do textureBitmap.closeFile()
        if node != undefined and isValidNode node do delete node
        if bone != undefined and isValidNode bone do delete bone
        if collisionBox != undefined and isValidNode collisionBox do delete collisionBox
        if stripNode != undefined and isValidNode stripNode do delete stripNode
        if rigidPart != undefined and isValidNode rigidPart do delete rigidPart
        if effectsRoot != undefined and isValidNode effectsRoot do delete effectsRoot
        if mhRoot != undefined and isValidNode mhRoot do
        (
            local family = #()
            MLVisitFamilyNode mhRoot family
            for candidate in family where isValidNode candidate do delete candidate
        )
        for path in #(binaryPath,modelPath,collisionPath,texturePath,dictionaryPath,effectPath,effectOutput,animationPath,ifpPath,compressedPath) where doesFileExist path do deleteFile path
        for path in (getFiles (textureFolder + "\\*")) do deleteFile path
        try (if doesDirectoryExist textureFolder do (dotNetClass "System.IO.Directory").Delete textureFolder) catch ()
        try ((dotNetClass "System.IO.Directory").Delete folder true) catch ()
        select savedSelection
        throw()
    )
)
