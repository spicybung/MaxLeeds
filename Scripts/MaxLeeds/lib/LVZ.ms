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

global MLWorldReadPs2Mesh, MLInflateChunk, MLWorldRows, MLReadWorld, MLReadWorldEffects, MLWorldHalf, MLWorldFXProperty, MLWorldFXValue, MLWorldFXRoots, MLWorldFXMarkers, MLSaveWorldEffects

fn MLWorldFXProperty node field value =
(
    local encoded = if (classof value) == Float then "f32:" + ((bit.floatAsInt value) as string) else value as string
    setUserProp node ("MaxLeedsFX" + field) encoded
)

fn MLWorldFXValue node field defaultValue =
(
    if node == undefined or not (isValidNode node) do return defaultValue
    local raw = getUserProp node ("MaxLeedsFX" + field)
    if raw == undefined do return defaultValue
    try
    (
        if (classof defaultValue) == String then raw as string
        else if (classof defaultValue) == Integer then raw as integer
        else
        (
            local encoded = raw as string
            if matchPattern encoded pattern:"f32:*" then
                bit.intAsFloat ((substring encoded 5 (encoded.count - 4)) as integer)
            else raw as float
        )
    )
    catch (defaultValue)
)

fn MLWorldFXKindName kind =
(
    case kind of
    (
        0: "Light"
        1: "Particle"
        2: "Attractor"
        3: "PedBehaviour"
        default: "Unknown"
    )
)

fn MLWorldFXSetNativeProperty node propertyName value =
(
    if node != undefined and isValidNode node and isProperty node propertyName do
    (
        try (setProperty node propertyName value) catch ()
    )
)

fn MLWorldFXNativeColor node =
(
    if node != undefined and isValidNode node do
    (
        if isProperty node #rgb do
        (
            try (return (getProperty node #rgb)) catch ()
        )
        if isProperty node #color do
        (
            try (return (getProperty node #color)) catch ()
        )
    )
    color (MLWorldFXValue node "Red" 255) (MLWorldFXValue node "Green" 255) (MLWorldFXValue node "Blue" 255)
)

fn MLWorldFXRememberLightNode marker =
(
    if isProperty marker #multiplier do
        MLWorldFXProperty marker "PreviewIntensity" (bit.floatAsInt ((getProperty marker #multiplier) as float))
    if isProperty marker #useFarAtten do
        MLWorldFXProperty marker "PreviewAttenuation" (if getProperty marker #useFarAtten then 1 else 0)
    if isProperty marker #farAttenStart do
        MLWorldFXProperty marker "PreviewInnerRange" (bit.floatAsInt ((getProperty marker #farAttenStart) as float))
    if isProperty marker #farAttenEnd do
        MLWorldFXProperty marker "PreviewOuterRange" (bit.floatAsInt ((getProperty marker #farAttenEnd) as float))
    true
)

fn MLWorldFXCaptureLightNode marker =
(
    if marker == undefined or not (isValidNode marker) do return false
    if (MLWorldFXValue marker "Type" -1) != 0 do return false
    if (getUserProp marker "MaxLeedsFXLightNode") != "true" do return false
    local currentColor = MLWorldFXNativeColor marker
    MLWorldFXProperty marker "Red" (currentColor.r as integer)
    MLWorldFXProperty marker "Green" (currentColor.g as integer)
    MLWorldFXProperty marker "Blue" (currentColor.b as integer)
    if isProperty marker #multiplier do
    (
        local intensity = getProperty marker #multiplier
        if (bit.floatAsInt (intensity as float)) != (MLWorldFXValue marker "PreviewIntensity" (bit.floatAsInt (intensity as float))) do
            MLWorldFXProperty marker "Alpha" (amin 255 (amax 0 ((intensity * 255.0 + 0.5) as integer)))
    )
    if isProperty marker #useFarAtten do
    (
        local enabled = if getProperty marker #useFarAtten then 1 else 0
        local previous = MLWorldFXValue marker "PreviewAttenuation" enabled
        if enabled == 1 then
        (
            if isProperty marker #farAttenStart do
            (
                local value = getProperty marker #farAttenStart
                if previous != enabled or (bit.floatAsInt (value as float)) != (MLWorldFXValue marker "PreviewInnerRange" (bit.floatAsInt (value as float))) do
                    MLWorldFXProperty marker "LightInnerRange" value
            )
            if isProperty marker #farAttenEnd do
            (
                local value = getProperty marker #farAttenEnd
                if previous != enabled or (bit.floatAsInt (value as float)) != (MLWorldFXValue marker "PreviewOuterRange" (bit.floatAsInt (value as float))) do
                    MLWorldFXProperty marker "LightOuterRange" value
            )
        )
        else if previous != enabled do
        (
            MLWorldFXProperty marker "LightInnerRange" 0.0
            MLWorldFXProperty marker "LightOuterRange" 0.0
        )
    )
    MLWorldFXRememberLightNode marker
    true
)

fn MLWorldFXApplyLightNode marker =
(
    if marker == undefined or not (isValidNode marker) do return false
    if (MLWorldFXValue marker "Type" -1) != 0 do return false
    if (getUserProp marker "MaxLeedsFXLightNode") != "true" do return false
    local rgb = color (MLWorldFXValue marker "Red" 255) (MLWorldFXValue marker "Green" 255) (MLWorldFXValue marker "Blue" 255)
    local alpha = MLWorldFXValue marker "Alpha" 255
    local outerRange = amax 0.0 (MLWorldFXValue marker "LightOuterRange" 0.0)
    local innerRange = amax 0.0 (MLWorldFXValue marker "LightInnerRange" 0.0)
    if innerRange > outerRange and outerRange > 0 do innerRange = outerRange

    MLWorldFXSetNativeProperty marker #rgb rgb
    MLWorldFXSetNativeProperty marker #color rgb
    MLWorldFXSetNativeProperty marker #multiplier (alpha / 255.0)
    MLWorldFXSetNativeProperty marker #useFarAtten (outerRange > 0.0)
    MLWorldFXSetNativeProperty marker #farAttenStart innerRange
    MLWorldFXSetNativeProperty marker #farAttenEnd outerRange
    MLWorldFXSetNativeProperty marker #showFarAtten false
    MLWorldFXSetNativeProperty marker #castShadows false
    marker.wirecolor = rgb
    MLWorldFXRememberLightNode marker
    true
)

fn MLWorldFXCreateNode kind index position parentNode =
(
    local title = "C2DEffects_" + (MLWorldFXKindName kind) + "_" + (index + 1) as string
    local node = undefined
    if kind == 0 then
    (
        node = omniLight name:title pos:position
        setUserProp node "MaxLeedsFXLightNode" "true"
        -- Keep viewport lights off until explicitly enabled; retail maps may contain thousands.
        MLWorldFXSetNativeProperty node #on false
        MLWorldFXSetNativeProperty node #enabled false
    )
    else
    (
        node = point name:title pos:position size:1.5 cross:true box:false
        setUserProp node "MaxLeedsFXLightNode" "false"
    )
    node.parent = parentNode
    node.pos = position
    setUserProp node "MaxLeeds2DFXType" (MLWorldFXKindName kind)
    setUserProp node "MaxLeeds2DFXLocal" "true"
    setUserProp node "MaxLeeds2DFXIndex" (index as string)
    MLWorldFXProperty node "Index" index
    MLWorldFXProperty node "Type" kind
    node
)

fn MLWorldFXConvertNode marker newKind =
(
    if marker == undefined or not (isValidNode marker) do throw "Select an imported effect first."
    if newKind < 0 or newKind > 3 do throw "Invalid 2D effect type."
    if (MLWorldFXValue marker "Type" -1) == newKind do return marker

    local index = MLWorldFXValue marker "Index" -1
    if index < 0 do throw "The selected effect has no original descriptor index."
    MLWorldFXCaptureLightNode marker
    local origin = marker.parent
    local position = marker.pos
    local originalTransform = marker.transform
    local descendants = marker.children as array
    local selected = marker.isSelected
    local hidden = marker.isHidden
    local properties = getUserPropBuffer marker
    local replacement = undefined
    try
    (
        replacement = MLWorldFXCreateNode newKind index position origin
        setUserPropBuffer replacement properties
        MLWorldFXProperty replacement "Type" newKind
        setUserProp replacement "MaxLeeds2DFXType" (MLWorldFXKindName newKind)
        setUserProp replacement "MaxLeedsFXLightNode" (if newKind == 0 then "true" else "false")
        replacement.transform = originalTransform
        if newKind == 0 do MLWorldFXApplyLightNode replacement
        for child in descendants do child.parent = replacement
        if hidden do hide replacement
        if selected do selectMore replacement
        delete marker
        replacement
    )
    catch
    (
        if replacement != undefined and isValidNode replacement do delete replacement
        throw()
    )
)

fn MLWorldFXRawBytes reader offset =
(
    local alphabet = "0123456789ABCDEF"
    local result = ""
    reader.seek offset
    for index = 1 to 64 do
    (
        local value = reader.byte()
        result += alphabet[(bit.shift value -4) + 1]
        result += alphabet[(bit.and value 15) + 1]
    )
    result
)

fn MLWorldFXRawReadable marker =
(
    local original = getUserProp marker "MaxLeedsFXRawBytes"
    if original == undefined or original.count != 128 do return "Original descriptor bytes unavailable."
    local display = ""
    for index = 0 to 63 do
    (
        local start = index * 2 + 1
        display += (substring original start 2) + " "
        if (mod (index + 1) 16) == 0 do display += "\r\n"
    )
    display
)

fn MLWorldFXRoots =
(
    for ancestor in selection do
    (
        local candidate = ancestor
        while candidate != undefined do
        (
            if (getUserProp candidate "MaxLeedsEffectsSource") != undefined do return candidate
            candidate = candidate.parent
        )
    )
    for candidate in helpers where (getUserProp candidate "MaxLeedsEffectsSource") != undefined do return candidate
    undefined
)

fn MLWorldFXSort left right =
(
    local first = MLWorldFXValue left "Index" -1
    local second = MLWorldFXValue right "Index" -1
    if first < second then -1 else if first > second then 1 else 0
)

fn MLWorldFXMarkers root =
(
    local records = #()
    if root == undefined or not (isValidNode root) do return records
    for child in root.children where (getUserProp child "MaxLeeds2DFXIndex") != undefined do append records child
    qsort records MLWorldFXSort
    records
)

fn MLInflateChunk inputPath =
(
    local probe = MLReader()
    local magic = 0
    try
    (
        probe.openFile inputPath
        magic = probe.atLong 0
        probe.closeFile()
    )
    catch
    (
        probe.closeFile()
        throw()
    )
    if (findItem #(0x57524C44, 0x41455241, 0x41524541, 0x47544147) magic) > 0 do return #(inputPath, false)

    local outputPath = MLTemporaryFile ((getDir #temp) + "\\MaxLeeds-inflated.bin")
    local input = undefined
    local inflater = undefined
    local output = undefined
    try
    (
        input = (dotNetClass "System.IO.File").OpenRead inputPath
        local first = input.ReadByte()
        local second = input.ReadByte()
        if first < 0 or second < 0 or (bit.and first 15) != 8 or first >= 128 or (mod (first * 256 + second) 31) != 0 or (bit.and second 32) != 0 do
            throw "The LVZ/DTZ stream does not have a valid zlib header."
        inflater = dotNetObject "System.IO.Compression.DeflateStream" input ((dotNetClass "System.IO.Compression.CompressionMode").Decompress)
        output = (dotNetClass "System.IO.File").Create outputPath
        local buffer = (dotNetClass "System.Array").CreateInstance (dotNetClass "System.Byte") 65536
        local total = 0
        local count = inflater.Read buffer 0 65536
        while count > 0 do
        (
            total += count
            if total > 1073741824 do throw "The decompressed LVZ/DTZ exceeds the 1 GiB safety limit."
            output.Write buffer 0 count
            count = inflater.Read buffer 0 65536
        )
        output.Close()
        output = undefined
        inflater.Close()
        inflater = undefined
        input.Close()
        input = undefined
        local check = MLReader()
        check.openFile outputPath
        local inflatedMagic = check.atLong 0
        check.closeFile()
        if (findItem #(0x57524C44, 0x41455241, 0x41524541, 0x47544147) inflatedMagic) == 0 do throw "Decompressed LVZ/DTZ header was not recognized."
        #(outputPath, true)
    )
    catch
    (
        if output != undefined do output.Close()
        if inflater != undefined do inflater.Close()
        if input != undefined do input.Close()
        if doesFileExist outputPath do deleteFile outputPath
        throw()
    )
)

fn MLWorldIdent value = (findItem #(0x57524C44, 0x41455241, 0x41524541) value) > 0

fn MLWorldReadRows reader base =
(
    local rows = #()
    local cursor = base + 0x24
    while cursor + 8 <= reader.length and rows.count < 96 do
    (
        local pointer = reader.atLong cursor
        local x = reader.atLong (cursor + 4)
        if pointer < 0x20 do exit
        if pointer + 0x20 > reader.length do exit
        if not (MLWorldIdent (reader.atLong pointer)) do
        (
            if base + pointer + 0x20 > reader.length then exit
            pointer += base
            if not (MLWorldIdent (reader.atLong pointer)) do exit
        )
        append rows #(pointer, x)
        cursor += 8
    )
    if rows.count < 2 then #() else rows
)

fn MLWorldRows reader =
(
    local rows = MLWorldReadRows reader 0
    if rows.count > 1 do return rows
    local limit = amin reader.length 2097152
    for base = 4 to limit - 0x24 by 4 while rows.count < 2 do
    (
        if (MLWorldIdent (reader.atLong base)) and (reader.atLong (base + 4)) == 1 do
            rows = MLWorldReadRows reader base
    )
    rows
)

fn MLWorldHalf packed =
(
    local sign = if (bit.and packed 0x8000) != 0 then -1.0 else 1.0
    local exponent = MLBits packed 10 5
    local fraction = MLBits packed 0 10
    if exponent == 0 then sign * (fraction / 1024.0) * (2.0 ^ -14)
    else if exponent == 31 then 0.0
    else sign * (1.0 + fraction / 1024.0) * (2.0 ^ (exponent - 15))
)

fn MLWorldOrigin game rowX rowY =
(
    local lcs = game == "LCS"
    local dx = if lcs then 100.0 else 125.0
    local dy = if lcs then 86.6 else 108.25
    local xstart = if lcs then -2000.0 else -2400.0
    [xstart + dx * (rowX + 0.5) - (if (mod rowY 2) == 1 then dx / 2.0 else 0.0), -2000.0 + dy * (rowY + 0.5), 0]
)

fn MLWorldResources img sectorStart sectorEnd sectorIndex table records =
(
    if sectorStart + 8 > sectorEnd do return 0
    local pointer = img.atLong sectorStart
    local count = img.atShort (sectorStart + 4)
    if count < 1 or count > 4096 or pointer < 0x20 do return 0
    local listStart = sectorStart + pointer - 0x20
    if listStart < sectorStart or listStart + count * 8 > sectorEnd do return 0
    local candidates = #()
    for index = 0 to count - 1 do
    (
        local row = listStart + index * 8
        local id = img.atLong row
        local raw = img.atLong (row + 4)
        local offset = sectorStart + raw - 0x20
        if id < 65536 and offset >= sectorStart and offset < sectorEnd do append candidates #(id, offset)
    )
    local offsets = for candidate in candidates collect candidate[2]
    sort offsets
    local boundaries = dotNetObject "System.Collections.Hashtable"
    local nextOffset = sectorEnd
    for index = offsets.count to 1 by -1 do
    (
        local key = offsets[index] as string
        if not (boundaries.ContainsKey key) do
        (
            boundaries.Add key nextOffset
            nextOffset = offsets[index]
        )
    )
    for row in candidates do
    (
        local finish = boundaries.get_Item (row[2] as string)
        append records #(row[2], finish, sectorStart)
        local key = (sectorIndex as string) + ":" + row[1] as string
        if not (table.ContainsKey key) do table.Add key records.count
        local fallback = ":" + row[1] as string
        if not (table.ContainsKey fallback) then table.Add fallback records.count
        else if (table.get_Item fallback) > 0 do
        (
            local previous = records[(table.get_Item fallback)]
            if previous[1] != row[2] or previous[2] != finish do table.set_Item fallback 0
        )
    )
    candidates.count
)

fn MLWorldFindUnpack reader start limit =
(
    local stop = amin (limit - 4) (start + 0x90)
    local offset = MLAlign start 4
    while offset <= stop do
    (
        if (reader.atLong offset) == 0x6C018000 do return offset
        offset += 4
    )
    0
)

fn MLWorldMaterialScore reader start count rowSize =
(
    local score = if rowSize == 24 then 30 else 10
    for index = 0 to (amin count 8) - 1 do
    (
        local row = start + 4 + index * rowSize
        local texture = reader.atShort (row + (if rowSize == 24 then 4 else 0))
        local packed = if rowSize == 24 then reader.atLong row else reader.atShort (row + 2)
        local budget = if rowSize == 24 then bit.shift packed -1 else bit.and packed 0x7FFF
        if rowSize == 24 then score += (if packed != 0 and budget <= 0x40000 then 12 else -10)
        else score += (if budget > 0 then 8 else -6)
        if texture != 65535 do score += 2
        local u = reader.atShort (row + (if rowSize == 24 then 6 else 4))
        local v = reader.atShort (row + (if rowSize == 24 then 8 else 6))
        local uScale = MLWorldHalf u
        local vScale = MLWorldHalf v
        if (bit.and u 0x7C00) != 0x7C00 and (bit.and v 0x7C00) != 0x7C00 and (abs uScale) <= 256 and (abs vScale) <= 256 then
        (
            score += (if rowSize == 24 then 10 else 6)
            if (abs uScale) >= 0.00001 or (abs vScale) >= 0.00001 do score += (if rowSize == 24 then 4 else 2)
        )
        else score -= (if rowSize == 24 then 40 else 30)
        local flags = reader.atShort (row + (if rowSize == 24 then 10 else 8))
        if (findItem #(0,0x40,0x3C00,0x4000) flags) != 0 or (findItem #(0,0x4000) (bit.and flags 0xC000)) != 0 do score += 1
    )
    score
)

fn MLWorldReadPspMesh reader start finish resourceID game =
(
    if start < 0 or start + 8 > finish do return undefined
    local count = reader.atLong start
    if count < 1 or count > 1024 do return undefined
    local marker = reader.atFloat (start + 4)
    local chosen = undefined
    local bestScore = -1
    for rowSize in #(24,10) do
    (
        local listEnd = start + 8 + count * rowSize
        if listEnd <= finish do
        (
            local valid = true
            local total = 0
            local score = if rowSize == 24 then 20 else 12
            if rowSize == 24 and marker != 0 do score += 8
            for index = 0 to count - 1 while valid do
            (
                local row = start + 8 + index * rowSize
                local vertexCount = bit.and (reader.atShort (row + 2)) 0x7FFF
                local u = reader.atShort (row + 4)
                local v = reader.atShort (row + 6)
                if vertexCount < 3 or vertexCount > 8192 or (bit.and u 0x7C00) == 0x7C00 or (bit.and v 0x7C00) == 0x7C00 then valid = false
                else if abs (MLWorldHalf u) > 256 or abs (MLWorldHalf v) > 256 then valid = false
                total += vertexCount
                if index < 16 and (reader.atShort row) != 65535 do score += 2
            )
            local cursor = MLAlign listEnd 4
            while cursor < finish and cursor - start < 4096 and (reader.seek cursor; reader.byte()) == 0xAA do cursor += 1
            cursor = MLAlign cursor 4
            if valid and total <= 250000 and cursor + total * 10 <= finish and score > bestScore do
            (
                chosen = #(rowSize,cursor)
                bestScore = score
            )
        )
    )
    if chosen == undefined do return undefined
    local part = MLPart name:("resource_" + resourceID as string)
    local materials = #()
    local cursor = chosen[2]
    for index = 0 to count - 1 do
    (
        local row = start + 8 + index * chosen[1]
        local packed = reader.atShort (row + 2)
        local vertexCount = bit.and packed 0x7FFF
        local uScale = MLWorldHalf (reader.atShort (row + 4))
        local vScale = MLWorldHalf (reader.atShort (row + 6))
        append materials (MLMaterial name:("tex_" + (reader.atShort row) as string) twoSided:((bit.and packed 0x8000) == 0) worldGame:game worldFlags:(reader.atShort (row + 8)))
        local base = part.vertices.count
        reader.seek cursor
        for vertexIndex = 1 to vertexCount do
        (
            append part.uv [reader.byte() * uScale / 128.0,1.0 - reader.byte() * vScale / 128.0,0]
            local rgba = reader.short()
            append part.colors (color (floor ((MLBits rgba 0 5) * 255.0 / 31)) (floor ((MLBits rgba 5 5) * 255.0 / 31)) (floor ((MLBits rgba 10 5) * 255.0 / 31)) (if (bit.and rgba 32768) != 0 then 255 else 0))
            append part.vertices ([reader.signedShort(),reader.signedShort(),reader.signedShort()] / 32768.0)
        )
        local faces = MLStripFaces vertexCount base
        join part.faces faces
        for face in faces do append part.faceIDs (index + 1)
        cursor += vertexCount * 10
    )
    #(part,materials,"PSP")
)
fn MLWorldReadMesh reader start finish resourceID game =
(
    local parsed = try (MLWorldReadPs2Mesh reader start finish resourceID game) catch (undefined)
    if parsed != undefined then #(parsed[1],parsed[2],"PS2")
    else MLWorldReadPspMesh reader start finish resourceID game
)

fn MLWorldReadPs2Mesh reader start finish resourceID game =
(
    if start < 0 or start + 0x30 > finish do return undefined
    local count = reader.atShort start
    local sizeBytes = reader.atShort (start + 2)
    if count < 1 or count > 512 or sizeBytes > 0x8000 do return undefined
    local expected22 = MLAlign (4 + count * 22) 16 - 4
    local expected24 = MLAlign (4 + count * 24) 16 - 4
    if sizeBytes != expected22 and sizeBytes != expected24 do return undefined
    if start + 4 + sizeBytes > finish do return undefined
    local rowSize = if sizeBytes == expected22 and sizeBytes != expected24 then 22 else 24
    if sizeBytes == expected22 and sizeBytes == expected24 do
        if (MLWorldMaterialScore reader start count 22) > (MLWorldMaterialScore reader start count 24) do rowSize = 22
    if (MLWorldMaterialScore reader start count rowSize) < 20 do return undefined
    if sizeBytes < count * rowSize or start + 4 + sizeBytes > finish do return undefined

    local materials = #()
    local budgets = #()
    local uvScales = #()
    for index = 0 to count - 1 do
    (
        local row = start + 4 + index * rowSize
        local textureID = if rowSize == 24 then reader.atShort (row + 4) else reader.atShort row
        local budget = if rowSize == 24 then bit.shift (reader.atLong row) -1 else bit.and (reader.atShort (row + 2)) 0x7FFF
        local uPacked = reader.atShort (row + (if rowSize == 24 then 6 else 4))
        local vPacked = reader.atShort (row + (if rowSize == 24 then 8 else 6))
        local uScale = MLWorldHalf uPacked
        local vScale = MLWorldHalf vPacked
        if (bit.and uPacked 0x7C00) == 0x7C00 or (abs uScale) > 4096 do uScale = 1.0
        if (bit.and vPacked 0x7C00) == 0x7C00 or (abs vScale) > 4096 do vScale = 1.0
        local flags = reader.atShort (row + (if rowSize == 24 then 10 else 8))
        local cull = if rowSize == 24 then (bit.and (reader.atLong row) 1) != 0 else (bit.and (reader.atShort (row + 2)) 0x8000) != 0
        append materials (MLMaterial name:("tex_" + textureID as string) twoSided:(not cull) worldGame:game worldFlags:flags)
        append budgets budget
        append uvScales [uScale, vScale, 0]
    )

    local cursor = MLAlign (start + 4 + sizeBytes) 4
    while cursor + 4 < finish and cursor < start + 0x1000 and (reader.atLong cursor) == 0xAAAAAAAA do cursor += 4
    local part = MLPart name:("resource_" + resourceID as string)
    local materialIndex = 1
    local consumed = 0
    local stripCount = 0
    local limit = amin finish (start + 33554432)
    local firstUnpack = MLWorldFindUnpack reader cursor limit
    if firstUnpack == 0 do return undefined
    local byteBudget = 0
    local validBudget = true
    for budget in budgets do
    (
        if budget > 0x400000 do validBudget = false
        if budget > 0 do byteBudget += budget
    )
    if validBudget and byteBudget > 0 and byteBudget <= 33554432 do limit = amin limit (firstUnpack + byteBudget)
    while cursor + 0x48 < limit and stripCount < 512 do
    (
        local unpack = MLWorldFindUnpack reader cursor limit
        if unpack == 0 or unpack + 0x48 >= limit do exit
        local vertexCount = bit.and (reader.atLong (unpack + 16)) 0x7FFF
        if vertexCount < 3 or vertexCount > 8192 do exit
        local positionHeader = unpack + 20 + 8 + 20
        if (reader.atLong (unpack + 20)) != 0x20000000 or (reader.atLong (unpack + 28)) != 0x30000000 do exit
        if (MLBits (reader.atLong positionHeader) 24 7) != 0x79 do exit
        local dataPosition = positionHeader + 4
        local uvDelimiter = MLAlign (dataPosition + vertexCount * 6) 4
        if uvDelimiter + 36 > limit or (reader.atLong uvDelimiter) != 0x20000000 or (reader.atLong (uvDelimiter + 8)) != 0x30000000 do exit
        local uvHeader = uvDelimiter + 28
        if (MLBits (reader.atLong uvHeader) 24 7) != 0x76 do exit
        local uvPosition = uvHeader + 4
        local colorHeader = MLAlign (uvPosition + vertexCount * 2) 4
        if colorHeader + 4 + vertexCount * 2 > limit do exit
        if (MLBits (reader.atLong colorHeader) 24 7) != 0x6F do exit

        while materialIndex < count and budgets[materialIndex] > 0 and consumed >= budgets[materialIndex] do
        (
            materialIndex += 1
            consumed = 0
        )
        if part.vertices.count + vertexCount > 250000 do throw "A world resource exceeds 250000 vertices."
        local base = part.vertices.count
        for index = 0 to vertexCount - 1 do
        (
            reader.seek (dataPosition + index * 6)
            local point = [(reader.signedShort()) / 32767.5, (reader.signedShort()) / 32767.5, (reader.signedShort()) / 32767.5]
            append part.vertices point
            reader.seek (uvPosition + index * 2)
            append part.uv [(reader.byte()) * uvScales[materialIndex].x / 128.0, 1.0 - (reader.byte()) * uvScales[materialIndex].y / 128.0, 0]
            local packedColor = reader.atShort (colorHeader + 4 + index * 2)
            append part.colors (color ((MLBits packedColor 0 5) * 255 / 31) ((MLBits packedColor 5 5) * 255 / 31) ((MLBits packedColor 10 5) * 255 / 31) (if (bit.and packedColor 0x8000) != 0 then 255 else 0))
        )
        for index = 3 to vertexCount do
        (
            if (mod index 2) == 1 then append part.faces [base + index - 2, base + index - 1, base + index]
            else append part.faces [base + index - 1, base + index - 2, base + index]
            append part.faceIDs materialIndex
        )
        local endStrip = MLAlign (colorHeader + 4 + vertexCount * 2) 4
        if endStrip + 4 <= limit and (reader.atLong endStrip) != 0x14000006 and endStrip + 8 <= limit and (reader.atLong (endStrip + 4)) == 0x14000006 do endStrip += 4
        if endStrip + 4 <= limit and (reader.atLong endStrip) == 0x14000006 do endStrip += 4
        while endStrip + 4 <= limit and (reader.atLong endStrip) == 0 do endStrip += 4
        consumed += endStrip - unpack
        cursor = endStrip
        stripCount += 1
    )
    if part.faces.count == 0 then undefined else #(part, materials)
)

fn MLWorldDirectTexture reader address baseStart baseEnd textureID output lcsHeader:false sectorRelative:false ps2:true =
(
    local headerBytes = if lcsHeader then 8 else 16
    if address < baseStart or address + headerBytes > baseEnd do return undefined
    if not lcsHeader do
    (
        if (reader.atLong address) != 0xCCCCCCCC do return undefined
        local formatFlags = reader.atShort (address + 6)
        if (findItem #(0x25,0x45) (bit.and formatFlags 255)) == 0 do return undefined
    )
    local dataPointer = reader.atLong (address + (if lcsHeader then 0 else 8))
    local flags = reader.atLong (address + (if lcsHeader then 4 else 12))
    local logWidth = MLBits flags 0 6
    local logHeight = MLBits flags 6 6
    local depth = MLBits flags 12 6
    if logWidth > 11 or logHeight > 11 do return undefined
    if (findItem #(4,8,32) depth) == 0 do return undefined
    local width = bit.shift 1 logWidth
    local height = bit.shift 1 logHeight
    local pixels = width * height
    local rasterBytes = ((pixels * depth + 7) / 8) as integer
    local paletteBytes = if depth == 4 then 64 else if depth == 8 then 1024 else 0
    local mipmaps = MLBits flags 20 4
    local paletteRelative = 0
    for level = 0 to (amax 1 mipmaps) - 1 do
    (
        paletteRelative += (((amax 1 (bit.shift width (-level))) * (amax 1 (bit.shift height (-level))) * depth + 7) / 8) as integer
    )
    local candidates = #()
    if dataPointer > 0 do
    (
        if sectorRelative and dataPointer >= 0x20 do append candidates (baseStart + dataPointer - 0x20)
        append candidates dataPointer
        if not sectorRelative and dataPointer >= 0x20 do append candidates (baseStart + dataPointer - 0x20)
    )
    if not lcsHeader do append candidates (address + 16)
    local raster = 0
    for candidate in candidates where raster == 0 do
    (
        if candidate >= baseStart and (lcsHeader or candidate >= address + headerBytes) and candidate + paletteRelative + paletteBytes <= baseEnd do raster = candidate
    )
    if raster == 0 do return undefined
    local palette = #()
    local transparent = false
    if depth < 16 do
    (
        for index = 0 to (bit.shift 1 depth) - 1 do
        (
            local value = MLTextureColor reader (raster + paletteRelative + index * 4) 32 0 ps2
            append palette value
            if value.a < 254.5 do transparent = true
        )
    )
    local imagePath = output + "\\tex_" + textureID as string + ".tga"
    local image = MLTgaWriter()
    local temporary = MLTemporaryFile imagePath
    try
    (
        image.openFile temporary width height
        for y = 0 to height - 1 do
        (
            local row = #()
            for x = 0 to width - 1 do
            (
                local pixel = x + y * width
                if ps2 and (bit.and (bit.shift flags -24) 1) != 0 and depth < 16 do pixel = MLPs2Address x y logWidth
                local offset = raster + ((floor (pixel * depth / 8.0)) as integer)
                if depth == 32 then
                (
                    local value = MLTextureColor reader offset 32 0 ps2
                    if value.a < 254.5 do transparent = true
                    append row value
                )
                else
                (
                    reader.seek offset
                    local paletteIndex = reader.byte()
                    if depth == 4 do paletteIndex = if (mod pixel 2) == 0 then bit.and paletteIndex 15 else bit.shift paletteIndex -4
                    if ps2 and depth == 8 do paletteIndex = bit.or (bit.and paletteIndex (bit.not 0x18)) (#(0,16,8,24)[(MLBits paletteIndex 3 2) + 1])
                    append row palette[paletteIndex + 1]
                )
            )
            image.writeRow row
        )
        image.closeFile()
        MLFinishFile temporary imagePath
        #("tex_" + textureID as string, imagePath, transparent)
    )
    catch
    (
        image.closeFile()
        if doesFileExist temporary do deleteFile temporary
        undefined
    )
)

fn MLWorldMasterResource lvz rows resourceID =
(
    if (lvz.atLong 0) != 0x57524C44 do return undefined
    local tableStart = lvz.atLong 0x20
    local countAddress = 0x24 + rows.count * 8
    if tableStart < 0x40 or tableStart >= lvz.length or countAddress + 4 > lvz.length do return undefined
    local count = lvz.atLong countAddress
    local stride = if rows.count == 47 then 8 else 12
    if count < 1 or count > 65536 or resourceID >= count or tableStart + count * stride > lvz.length do return undefined
    local pointer = lvz.atLong (tableStart + resourceID * stride)
    if pointer < 0x40 or pointer + 16 > lvz.length do return undefined
    #(pointer, lvz.length)
)

fn MLWorldLoadTexture lvz img rows resourceTable resourceRecords textureID output game sectorID ps2:true =
(
    local lcs = game == "LCS"
    local sectorKey = sectorID as string + ":" + textureID as string
    local recordIndex = if resourceTable.ContainsKey sectorKey then resourceTable.get_Item sectorKey else 0
    if recordIndex > 0 do
    (
        local record = resourceRecords[recordIndex]
        for candidate = record[1] to (amin (record[2] - 16) (record[1] + 128)) by 4 do
        (
            if lcs or (img.atLong candidate) == 0xCCCCCCCC do
            (
                local decoded = MLWorldDirectTexture img candidate record[3] record[2] textureID output lcsHeader:lcs sectorRelative:true ps2:ps2
                if decoded != undefined do return decoded
            )
        )
    )
    local entry = MLWorldMasterResource lvz rows textureID
    if entry != undefined do
    (
        local decoded = MLWorldDirectTexture lvz entry[1] 0 entry[2] textureID output lcsHeader:lcs ps2:ps2
        if decoded != undefined do return decoded
    )
    local key = ":" + textureID as string
    recordIndex = if resourceTable.ContainsKey key then resourceTable.get_Item key else 0
    if recordIndex > 0 do
    (
        local record = resourceRecords[recordIndex]
        for candidate = record[1] to (amin (record[2] - 16) (record[1] + 128)) by 4 do
        (
            if lcs or (img.atLong candidate) == 0xCCCCCCCC do
            (
                local decoded = MLWorldDirectTexture img candidate record[3] record[2] textureID output lcsHeader:lcs sectorRelative:true ps2:ps2
                if decoded != undefined do return decoded
            )
        )
    )
    undefined
)

fn MLWorldFindImageFile lvzPath =
(
    local stem = getFilenamePath lvzPath + getFilenameFile lvzPath
    local candidates = #(stem + ".img", stem + ".IMG")
    for candidate in candidates where doesFileExist candidate do return candidate
    undefined
)

fn MLWorldFindDtz lvzPath =
(
    local directory = getFilenamePath lvzPath
    for level = 1 to 4 do
    (
        for name in #("GAME.DTZ", "game.dtz") do
        (
            local candidate = directory + name
            if doesFileExist candidate do return candidate
        )
        local parent = getFilenamePath (trimRight directory "\\/")
        if parent == directory or parent == "" do exit
        directory = parent
    )
    undefined
)

fn MLReadWorld lvzPath imagePath game maxInstances loadTextures =
(
    local decompressed = #(lvzPath, false)
    local lvz = MLReader()
    local img = MLReader()
    local nodes = #()
    local root = undefined
    try
    (
        if imagePath == undefined or not (doesFileExist imagePath) do throw "A matching IMG archive is required for LVZ world geometry."
        decompressed = MLInflateChunk lvzPath
        lvz.openFile decompressed[1]
        img.openFile imagePath
        local rows = MLWorldRows lvz
        if rows.count < 2 do throw "The LVZ sector directory was not found."
        if game == "Auto" do game = if rows.count >= 42 then "LCS" else "VCS"

        local resourceTable = dotNetObject "System.Collections.Hashtable"
        local resourceRecords = #()
        local placements = #()
        local seen = dotNetObject "System.Collections.Hashtable"
        local sectorIndex = 0
        local sectorCount = 0
        local passCount = if game == "LCS" then 8 else 9
        for rowIndex = 1 to rows.count - 1 do
        (
            local first = rows[rowIndex][1]
            local last = rows[rowIndex + 1][1]
            local count = if last > first then ((last - first) / 0x20) as integer else 0
            if count > 0 and count <= 256 do
            (
                for index = 0 to count - 1 do
                (
                    local header = first + index * 0x20
                    if header + 0x20 > lvz.length do exit
                    if not (MLWorldIdent (lvz.atLong header)) do exit
                    local fileSize = lvz.atLong (header + 8)
                    local sectorStart = lvz.atLong (header + 0x18)
                    local sectorEnd = sectorStart + fileSize - 0x20
                    if fileSize >= 0x30 and sectorStart < img.length do
                    (
                        sectorEnd = amin img.length sectorEnd
                        if sectorEnd > sectorStart + 0x30 do
                        (
                            sectorCount += 1
                            MLWorldResources img sectorStart sectorEnd sectorIndex resourceTable resourceRecords
                            local origin = MLWorldOrigin game (rows[rowIndex][2] + index) (rowIndex - 1)
                            local pointers = #()
                            local valid = sectorStart + 8 + passCount * 4 <= sectorEnd
                            if valid do
                            (
                                for pass = 0 to passCount - 1 do
                                (
                                    local pointer = img.atLong (sectorStart + 8 + pass * 4)
                                    if pointer < 0x20 or (mod pointer 4) != 0 or sectorStart + pointer - 0x20 > sectorEnd do valid = false
                                    if pointers.count > 0 and pointer < pointers[pointers.count] do valid = false
                                    append pointers pointer
                                )
                            )
                            if valid do
                            (
                                for pass = 1 to pointers.count - 1 do
                                (
                                    local scan = sectorStart + pointers[pass] - 0x20
                                    local stop = amin sectorEnd (sectorStart + pointers[pass + 1] - 0x20)
                                    while scan + 0x50 <= stop do
                                    (
                                        local ipl = bit.and (img.atShort scan) 0x7FFF
                                        local resourceID = img.atShort (scan + 2)
                                        if resourceID > 0 and resourceID != 65535 do try
                                        (
                                            local transform = img.matrix (scan + 0x10)
                                            local xAxis = length transform.row1
                                            local yAxis = length transform.row2
                                            local zAxis = length transform.row3
                                            local translation = transform.row4 + origin
                                            if xAxis > 0.00001 and yAxis > 0.00001 and zAxis > 0.00001 and xAxis < 10000 and yAxis < 10000 and zAxis < 10000 and (length translation) < 100000 do
                                            (
                                                local identity = resourceID as string + ":" + ipl as string + ":" + pass as string + ":" + translation as string + ":" + transform.row1 as string + ":" + transform.row2 as string + ":" + transform.row3 as string
                                                if not (seen.ContainsKey identity) do
                                                (
                                                    seen.Add identity (placements.count + 1)
                                                    transform.row4 = translation
                                                    append placements #(resourceID, ipl, sectorIndex, pass, transform, #(#(scan,origin)))
                                                )
                                                else append placements[(seen.get_Item identity)][6] #(scan,origin)
                                            )
                                        ) catch ()
                                        scan += 0x50
                                    )
                                )
                            )
                        )
                    )
                    sectorIndex += 1
                )
            )
        )
        if placements.count == 0 do throw "No valid retail world placements were found in this LVZ and IMG pair."

        root = dummy name:(getFilenameFile lvzPath + " world") pos:[0,0,0] boxsize:[10,10,10]
        setUserProp root "MaxLeedsRoot" "true"
        setUserProp root "MaxLeedsGame" game
        setUserProp root "MaxLeedsLVZ" lvzPath
        setUserProp root "MaxLeedsIMG" imagePath
        setUserProp root "MaxLeedsIMGHash" (MLFileDigest imagePath)
        append nodes root
        local instances = dotNetObject "System.Collections.Hashtable"
        local failedKeys = dotNetObject "System.Collections.Hashtable"
        local imported = 0
        local skipped = 0
        local countLimit = if maxInstances == 0 then placements.count else amin placements.count maxInstances
        for positionIndex = 1 to countLimit do
        (
            local placement = placements[positionIndex]
            local key = placement[3] as string + ":" + placement[1] as string
            local source = if instances.ContainsKey key then nodes[(instances.get_Item key)] else undefined
            local fresh = false
            local reference = key
            if source == undefined and not (failedKeys.ContainsKey key) do
            (
                if not (resourceTable.ContainsKey key) do reference = ":" + placement[1] as string
                local parsed = undefined
                local resourceIndex = if resourceTable.ContainsKey reference then resourceTable.get_Item reference else 0
                if resourceIndex > 0 do
                (
                    local resource = resourceRecords[resourceIndex]
                    parsed = try (MLWorldReadMesh img resource[1] resource[2] placement[1] game) catch (undefined)
                    if parsed == undefined do
                    (
                        for offset = resource[1] + 4 to (amin (resource[2] - 32) (resource[1] + 0x180)) by 4 while parsed == undefined do
                            parsed = try (MLWorldReadMesh img offset resource[2] placement[1] game) catch (undefined)
                    )
                )
                if parsed == undefined do
                (
                    local master = MLWorldMasterResource lvz rows placement[1]
                    if master != undefined do
                    (
                        parsed = try (MLWorldReadMesh lvz master[1] master[2] placement[1] game) catch (undefined)
                        if parsed == undefined do
                            for offset = master[1] + 4 to (amin (master[2] - 32) (master[1] + 0x180)) by 4 while parsed == undefined do
                                parsed = try (MLWorldReadMesh lvz offset master[2] placement[1] game) catch (undefined)
                    )
                )
                if parsed != undefined do source = try (MLCreateMesh parsed[1] parsed[2]) catch (undefined)
                if source != undefined then
                (
                    source.parent = root
                    setUserProp source "MaxLeedsPlatform" parsed[3]
                    append nodes source
                    instances.Add key nodes.count
                    fresh = true
                )
                else failedKeys.Add key true
            )
            if source != undefined do
            (
                local node = if fresh then source else instance source
                if node != source do
                (
                    node.parent = root
                    append nodes node
                )
                node.name = "ipl_" + placement[2] as string + "_res_" + placement[1] as string
                node.transform = placement[5]
                setUserProp node "MaxLeedsResourceID" (placement[1] as string)
                setUserProp node "MaxLeedsIPLID" (placement[2] as string)
                setUserProp node "MaxLeedsSectorID" (placement[3] as string)
                setUserProp node "MaxLeedsPass" (placement[4] as string)
                local addresses = ""
                for entry in placement[6] do
                    addresses += entry[1] as string + "," + entry[2].x as string + "," + entry[2].y as string + "," + entry[2].z as string + ";"
                setUserProp node "MaxLeedsPlacementAddresses" addresses
                imported += 1
            )
            else skipped += 1
        )

        local textureCount = 0
        if loadTextures and imported > 0 do try
        (
            local textureFolder = (getFilenamePath lvzPath) + (getFilenameFile lvzPath) + "_textures"
            makeDir textureFolder all:true
            local sectorIDs = #()
            local groups = #()
            for node in nodes where isValidNode node do
            (
                local sector = getUserProp node "MaxLeedsSectorID"
                if sector != undefined do
                (
                    local sectorID = sector as integer
                    local groupIndex = findItem sectorIDs sectorID
                    if groupIndex == 0 do
                    (
                        append sectorIDs sectorID
                        append groups #()
                        groupIndex = groups.count
                    )
                    append groups[groupIndex] node
                )
            )
            for groupIndex = 1 to groups.count do
            (
                local sectorNodes = groups[groupIndex]
                local sectorFolder = textureFolder + "\\sector_" + sectorIDs[groupIndex] as string
                makeDir sectorFolder all:true
                local textureIDs = #()
                for node in sectorNodes where isProperty node #material and node.material != undefined do
                (
                    local materials = if (classof node.material) == MultiMaterial then node.material.materialList else #(node.material)
                    for material in materials where material != undefined do
                    (
                        if matchPattern material.name pattern:"tex_*" do
                        (
                            local id = try ((substring material.name 5 (material.name.count - 4)) as integer) catch (-1)
                            if id >= 0 and (findItem textureIDs id) == 0 do append textureIDs id
                        )
                    )
                )
                local images = #()
                for id in textureIDs do
                (
                    local record = MLWorldLoadTexture lvz img rows resourceTable resourceRecords id sectorFolder game sectorIDs[groupIndex] ps2:((getUserProp sectorNodes[1] "MaxLeedsPlatform") != "PSP")
                    if record != undefined do append images record
                )
                textureCount += MLApplyTextures images sectorNodes
            )
            try
            (
                for platform in #("PS2","PSP") do
                (
                    local platformNodes = for node in nodes where (getUserProp node "MaxLeedsPlatform") == platform collect node
                    if platformNodes.count > 0 do
                    (
                        local external = MLImportModelTextures lvzPath platform platformNodes
                        textureCount += external[2]
                    )
                )
            ) catch (format "MaxLeeds: no matching external world textures: %\n" (getCurrentException()))
        ) catch (format "MaxLeeds: world models imported; texture extraction was incomplete: %\n" (getCurrentException()))
        lvz.closeFile()
        img.closeFile()
        if decompressed[2] do deleteFile decompressed[1]
        select root
        #(imported, skipped, placements.count, sectorCount, textureCount, game)
    )
    catch
    (
        lvz.closeFile()
        img.closeFile()
        if decompressed[2] and doesFileExist decompressed[1] do deleteFile decompressed[1]
        for node in nodes where isValidNode node do delete node
        throw()
    )
)

fn MLReadWorldEffectsData dtzPath =
(
    if dtzPath == undefined or not (doesFileExist dtzPath) do return #(0, "No GAME.DTZ supplied")
    local decompressed = #(dtzPath, false)
    local reader = MLReader()
    local effectsRoot = undefined
    try
    (
        decompressed = MLInflateChunk dtzPath
        reader.openFile decompressed[1]
        if (reader.atLong 0) != 0x47544147 do throw "Not a retail GAME.DTZ resource image."
        local count = reader.atLong 0x54
        local pointer = reader.atLong 0x58
        if count < 1 or count > 50000 or pointer < 0x5C or pointer + count * 64 > reader.length do
            throw "The 2D effect table is not in the expected PS2 layout."

        effectsRoot = dummy name:"GAME.DTZ - C2DEffects" pos:[0,0,0] boxsize:[5,5,5]
        setUserProp effectsRoot "MaxLeedsEffectsLocal" "true"
        setUserProp effectsRoot "MaxLeedsEffectsSource" dtzPath
        setUserProp effectsRoot "MaxLeedsEffectsCount" (count as string)
        setUserProp effectsRoot "MaxLeedsEffectsTableOffset" (pointer as string)
        local imported = 0
        local invalid = 0
        for index = 0 to count - 1 do
        (
            local offset = pointer + index * 64
            local position = reader.atPoint offset
            reader.seek (offset + 20)
            local kind = reader.byte()
            local marker = undefined
            if kind <= 3 and (length position) < 1000000 do
            (
                try
                (
                    marker = MLWorldFXCreateNode kind index position effectsRoot
                    MLWorldFXProperty marker "OriginalType" kind
                    MLWorldFXProperty marker "RecordOffset" offset
                    setUserProp marker "MaxLeedsFXRawBytes" (MLWorldFXRawBytes reader offset)
                    reader.seek (offset + 16)
                    local red = reader.byte()
                    local green = reader.byte()
                    local blue = reader.byte()
                    local alpha = reader.byte()
                    MLWorldFXProperty marker "Red" red
                    MLWorldFXProperty marker "Green" green
                    MLWorldFXProperty marker "Blue" blue
                    MLWorldFXProperty marker "Alpha" alpha
                    marker.wirecolor = color red green blue
                    case kind of
                    (
                        0:
                        (
                            MLWorldFXProperty marker "LightDistance" (reader.atFloat (offset + 24))
                            MLWorldFXProperty marker "LightOuterRange" (reader.atFloat (offset + 28))
                            MLWorldFXProperty marker "LightSize" (reader.atFloat (offset + 32))
                            MLWorldFXProperty marker "LightInnerRange" (reader.atFloat (offset + 36))
                            reader.seek (offset + 40)
                            MLWorldFXProperty marker "LightFlash" (reader.byte())
                            MLWorldFXProperty marker "LightWet" (reader.byte())
                            MLWorldFXProperty marker "LightFlare" (reader.byte())
                            MLWorldFXProperty marker "LightShadow" (reader.byte())
                            MLWorldFXProperty marker "LightFlags" (reader.byte())
                            MLWorldFXProperty marker "LightCoronaPointer" (reader.atLong (offset + 48))
                            MLWorldFXProperty marker "LightShadowPointer" (reader.atLong (offset + 52))
                        )
                        1:
                        (
                            MLWorldFXProperty marker "ParticleType" (reader.atLong (offset + 24))
                            MLWorldFXProperty marker "ParticleX" (reader.atFloat (offset + 28))
                            MLWorldFXProperty marker "ParticleY" (reader.atFloat (offset + 32))
                            MLWorldFXProperty marker "ParticleZ" (reader.atFloat (offset + 36))
                            MLWorldFXProperty marker "ParticleScale" (reader.atFloat (offset + 40))
                        )
                        2:
                        (
                            MLWorldFXProperty marker "AttractorX" (reader.atFloat (offset + 24))
                            MLWorldFXProperty marker "AttractorY" (reader.atFloat (offset + 28))
                            MLWorldFXProperty marker "AttractorZ" (reader.atFloat (offset + 32))
                            reader.seek (offset + 36)
                            MLWorldFXProperty marker "AttractorSubtype" (reader.byte())
                            MLWorldFXProperty marker "AttractorProbability" (reader.byte())
                        )
                        3:
                        (
                            MLWorldFXProperty marker "PedDirectionX" (reader.atFloat (offset + 24))
                            MLWorldFXProperty marker "PedDirectionY" (reader.atFloat (offset + 28))
                            MLWorldFXProperty marker "PedDirectionZ" (reader.atFloat (offset + 32))
                            MLWorldFXProperty marker "PedRotationX" (reader.atFloat (offset + 36))
                            MLWorldFXProperty marker "PedRotationY" (reader.atFloat (offset + 40))
                            MLWorldFXProperty marker "PedRotationZ" (reader.atFloat (offset + 44))
                            reader.seek (offset + 48)
                            MLWorldFXProperty marker "PedBehaviour" (reader.byte())
                        )
                    )
                    if kind == 0 do MLWorldFXApplyLightNode marker
                    imported += 1
                )
                catch
                (
                    if marker != undefined and isValidNode marker do delete marker
                    invalid += 1
                    format "MaxLeeds: skipped invalid effect %: %\n" index (getCurrentException())
                )
            )
            else invalid += 1
        )
        reader.closeFile()
        if decompressed[2] and doesFileExist decompressed[1] do deleteFile decompressed[1]
        select effectsRoot
        #(imported, "Local positions; " + invalid as string + " unsupported/invalid descriptors")
    )
    catch
    (
        local failure = getCurrentException() as string
        reader.closeFile()
        if decompressed[2] and doesFileExist decompressed[1] do deleteFile decompressed[1]
        if effectsRoot != undefined and isValidNode effectsRoot do
        (
            local children = effectsRoot.children as array
            for child in children where isValidNode child do delete child
            delete effectsRoot
        )
        #(0, failure)
    )
)

fn MLReadWorldEffects dtzPath =
(
    local report = undefined
    undo "MaxLeeds import C2DEffects" on
    (
        with redraw off (report = MLReadWorldEffectsData dtzPath)
    )
    report
)

fn MLWorldFXPatchByte stream offset value =
(
    fseek stream offset #seek_set
    writeByte stream (amin 255 (amax 0 (value as integer))) #unsigned
)

fn MLWorldFXPatchFloat stream offset value =
(
    if value != value or (abs value) > 1000000.0 do throw "An effect float is outside the supported editing range."
    fseek stream offset #seek_set
    writeFloat stream value
)

fn MLWorldFXPatchLong stream offset value =
(
    fseek stream offset #seek_set
    writeLong stream value #signed
)

fn MLCompressChunk sourcePath destinationPath =
(
    local input = undefined
    local output = undefined
    local compressor = undefined
    local trailing = undefined
    try
    (
        input = (dotNetClass "System.IO.File").OpenRead sourcePath
        output = (dotNetClass "System.IO.File").Create destinationPath
        output.WriteByte 0x78
        output.WriteByte 0x9C
        compressor = dotNetObject "System.IO.Compression.DeflateStream" output ((dotNetClass "System.IO.Compression.CompressionMode").Compress)
        local buffer = (dotNetClass "System.Array").CreateInstance (dotNetClass "System.Byte") 65536
        local a = 1
        local b = 0
        local count = input.Read buffer 0 65536
        while count > 0 do
        (
            for blockStart = 0 to count - 1 by 2048 do
            (
                local blockEnd = amin (count - 1) (blockStart + 2047)
                for index = blockStart to blockEnd do
                (
                    a += (buffer.GetValue index) as integer
                    b += a
                )
                a = mod a 65521
                b = mod b 65521
            )
            compressor.Write buffer 0 count
            count = input.Read buffer 0 65536
        )
        compressor.Close()
        compressor = undefined
        output = undefined
        input.Close()
        input = undefined
        trailing = fopen destinationPath "ab"
        if trailing == undefined do throw "Cannot append the compressed DTZ checksum."
        writeByte trailing (bit.shift b -8) #unsigned
        writeByte trailing (bit.and b 255) #unsigned
        writeByte trailing (bit.shift a -8) #unsigned
        writeByte trailing (bit.and a 255) #unsigned
        fclose trailing
        trailing = undefined
        destinationPath
    )
    catch
    (
        if trailing != undefined do fclose trailing
        if compressor != undefined do compressor.Close()
        if output != undefined do output.Close()
        if input != undefined do input.Close()
        if doesFileExist destinationPath do deleteFile destinationPath
        throw()
    )
)

fn MLSaveWorldEffects root destinationPath =
(
    if root == undefined or not (isValidNode root) do throw "Select an imported GAME.DTZ effects group."
    local source = getUserProp root "MaxLeedsEffectsSource"
    if source == undefined or not (doesFileExist source) do throw "The original GAME.DTZ file was not found."
    local markers = MLWorldFXMarkers root
    if markers.count == 0 do throw "This 2D effects group contains no editable descriptors."
    local extension = toLower (getFilenameType destinationPath)
    if extension != ".dtz" and extension != ".dat" do throw "Save edited effects as GAME.DTZ or GAME.DAT."
    local unpacked = #(source, false)
    local rawFile = MLTemporaryFile (destinationPath + ".dat")
    local packedFile = MLTemporaryFile destinationPath
    local reader = MLReader()
    local stream = undefined
    try
    (
        unpacked = MLInflateChunk source
        reader.openFile unpacked[1]
        if (reader.atLong 0) != 0x47544147 do throw "The source is not a GAME.DTZ resource image."
        local count = reader.atLong 0x54
        local table = reader.atLong 0x58
        if count < 1 or count > 50000 or table < 0x5C or table + count * 64 > reader.length do throw "The source 2D effect table is invalid."
        local importedCount = getUserProp root "MaxLeedsEffectsCount"
        local importedTable = getUserProp root "MaxLeedsEffectsTableOffset"
        if importedCount == undefined or importedTable == undefined do throw "The effects group has no original table metadata. Reload GAME.DTZ."
        if count != (importedCount as integer) or table != (importedTable as integer) do
            throw "The source effects table changed after import. Reload GAME.DTZ before saving."
        local visited = #{}
        visited.count = count
        for marker in markers do
        (
            local index = MLWorldFXValue marker "Index" -1
            if index < 0 or index >= count do throw ("An effect has an invalid descriptor index: " + index as string)
            if visited[index + 1] do throw ("Duplicate descriptor index: " + index as string)
            visited[index + 1] = true
            local original = getUserProp marker "MaxLeedsFXRawBytes"
            if original == undefined or original != (MLWorldFXRawBytes reader (table + index * 64)) do
                throw ("Source descriptor " + index as string + " changed after import. Reload GAME.DTZ before saving.")
        )
        local rootInverse = inverse root.transform
        reader.closeFile()
        if not (copyFile unpacked[1] rawFile) do throw "Cannot create the editable GAME.DTZ image."
        stream = fopen rawFile "r+b"
        if stream == undefined do throw "Cannot open the temporary GAME.DTZ image for editing."
        local edited = 0
        for marker in markers do
        (
            local index = MLWorldFXValue marker "Index" -1
            local offset = table + index * 64
            local kind = MLWorldFXValue marker "Type" 0
            if kind < 0 or kind > 3 do throw ("Invalid 2D effect type at index " + index as string)
            local originalKind = MLWorldFXValue marker "OriginalType" kind
            if kind == 0 do MLWorldFXCaptureLightNode marker
            if originalKind != kind do
            (
                -- A class change must not retain fields or pointers from the old descriptor.
                fseek stream (offset + 24) #seek_set
                for byteIndex = 24 to 63 do writeByte stream 0 #unsigned
            )
            local position = marker.pos * rootInverse
            MLWorldFXPatchFloat stream (offset + 0) position.x
            MLWorldFXPatchFloat stream (offset + 4) position.y
            MLWorldFXPatchFloat stream (offset + 8) position.z
            MLWorldFXPatchByte stream (offset + 16) (MLWorldFXValue marker "Red" 255)
            MLWorldFXPatchByte stream (offset + 17) (MLWorldFXValue marker "Green" 255)
            MLWorldFXPatchByte stream (offset + 18) (MLWorldFXValue marker "Blue" 255)
            MLWorldFXPatchByte stream (offset + 19) (MLWorldFXValue marker "Alpha" 255)
            MLWorldFXPatchByte stream (offset + 20) kind
            case kind of
            (
                0:
                (
                    MLWorldFXPatchFloat stream (offset + 24) (MLWorldFXValue marker "LightDistance" 0.0)
                    MLWorldFXPatchFloat stream (offset + 28) (MLWorldFXValue marker "LightOuterRange" 0.0)
                    MLWorldFXPatchFloat stream (offset + 32) (MLWorldFXValue marker "LightSize" 0.0)
                    MLWorldFXPatchFloat stream (offset + 36) (MLWorldFXValue marker "LightInnerRange" 0.0)
                    MLWorldFXPatchByte stream (offset + 40) (MLWorldFXValue marker "LightFlash" 0)
                    MLWorldFXPatchByte stream (offset + 41) (MLWorldFXValue marker "LightWet" 0)
                    MLWorldFXPatchByte stream (offset + 42) (MLWorldFXValue marker "LightFlare" 0)
                    MLWorldFXPatchByte stream (offset + 43) (MLWorldFXValue marker "LightShadow" 0)
                    MLWorldFXPatchByte stream (offset + 44) (MLWorldFXValue marker "LightFlags" 0)
                )
                1:
                (
                    MLWorldFXPatchLong stream (offset + 24) (MLWorldFXValue marker "ParticleType" 0)
                    MLWorldFXPatchFloat stream (offset + 28) (MLWorldFXValue marker "ParticleX" 0.0)
                    MLWorldFXPatchFloat stream (offset + 32) (MLWorldFXValue marker "ParticleY" 0.0)
                    MLWorldFXPatchFloat stream (offset + 36) (MLWorldFXValue marker "ParticleZ" 0.0)
                    MLWorldFXPatchFloat stream (offset + 40) (MLWorldFXValue marker "ParticleScale" 1.0)
                )
                2:
                (
                    MLWorldFXPatchFloat stream (offset + 24) (MLWorldFXValue marker "AttractorX" 0.0)
                    MLWorldFXPatchFloat stream (offset + 28) (MLWorldFXValue marker "AttractorY" 0.0)
                    MLWorldFXPatchFloat stream (offset + 32) (MLWorldFXValue marker "AttractorZ" 0.0)
                    MLWorldFXPatchByte stream (offset + 36) (MLWorldFXValue marker "AttractorSubtype" 0)
                    MLWorldFXPatchByte stream (offset + 37) (MLWorldFXValue marker "AttractorProbability" 0)
                )
                3:
                (
                    MLWorldFXPatchFloat stream (offset + 24) (MLWorldFXValue marker "PedDirectionX" 0.0)
                    MLWorldFXPatchFloat stream (offset + 28) (MLWorldFXValue marker "PedDirectionY" 0.0)
                    MLWorldFXPatchFloat stream (offset + 32) (MLWorldFXValue marker "PedDirectionZ" 0.0)
                    MLWorldFXPatchFloat stream (offset + 36) (MLWorldFXValue marker "PedRotationX" 0.0)
                    MLWorldFXPatchFloat stream (offset + 40) (MLWorldFXValue marker "PedRotationY" 0.0)
                    MLWorldFXPatchFloat stream (offset + 44) (MLWorldFXValue marker "PedRotationZ" 0.0)
                    MLWorldFXPatchByte stream (offset + 48) (MLWorldFXValue marker "PedBehaviour" 0)
                )
            )
            edited += 1
        )
        fclose stream
        stream = undefined
        if extension == ".dtz" then
        (
            MLCompressChunk rawFile packedFile
            MLFinishFile packedFile destinationPath
            if doesFileExist rawFile do deleteFile rawFile
        )
        else MLFinishFile rawFile destinationPath
        if unpacked[2] and doesFileExist unpacked[1] do deleteFile unpacked[1]
        edited
    )
    catch
    (
        reader.closeFile()
        if stream != undefined do fclose stream
        if doesFileExist rawFile do deleteFile rawFile
        if doesFileExist packedFile do deleteFile packedFile
        if unpacked[2] and doesFileExist unpacked[1] do deleteFile unpacked[1]
        throw()
    )
)
