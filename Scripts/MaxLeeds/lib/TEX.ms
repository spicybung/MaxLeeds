-- MaxLeeds - spicybung
-- GPL-3.0-or-later

global MLReadTextures, MLWriteTextures, MLPspAddress, MLPs2Address, MLTextureColor, MLQuantize, MLQuantAxis, MLCompareColors, MLQuantCode
fn MLPspAddress x y stride = (((floor (y / 8.0)) as integer) * (stride / 16) + ((floor (x / 16.0)) as integer)) * 128 + (mod y 8) * 16 + mod x 16
fn MLPs2Address x y logWidth =
(
    local nx = bit.xor (bit.and x 7) (bit.shift (bit.xor (bit.shift y -1) (bit.shift y -2)) 2)
    nx = bit.or (bit.and nx 7) (bit.and (bit.shift x -1) (bit.not 7))
    local ny = bit.or (bit.and y 1) (bit.and (bit.shift y -1) (bit.not 1))
    local n = bit.or (bit.and (bit.shift y -1) 1) (bit.shift (bit.and (bit.shift x -3) 1) 1)
    bit.or n (bit.or (bit.shift nx 2) (bit.shift ny (logWidth + 1)))
)
fn MLTextureColor reader offset depth format ps2 =
(
    reader.seek offset
    local value = undefined
    if depth == 32 then value = MLColor (reader.long())
    else
    (
        local packed = reader.short()
        case format of
        (
            0x0200: value = color ((MLBits packed 0 5) * 255 / 31) ((MLBits packed 5 6) * 255 / 63) ((MLBits packed 11 5) * 255 / 31) 255
            0x0300: value = color ((MLBits packed 0 4) * 17) ((MLBits packed 4 4) * 17) ((MLBits packed 8 4) * 17) ((MLBits packed 12 4) * 17)
            0x0100: value = color ((MLBits packed 0 5) * 255 / 31) ((MLBits packed 5 5) * 255 / 31) ((MLBits packed 10 5) * 255 / 31) (if (bit.and packed 0x8000) != 0 then 255 else 0)
            0x0A00: value = color ((MLBits packed 0 5) * 255 / 31) ((MLBits packed 5 5) * 255 / 31) ((MLBits packed 10 5) * 255 / 31) 255
            default: throw "This 16-color-bit texture layout is not supported."
        )
    )
    if ps2 do value.a = amin 255 (value.a * 255.0 / 128.0)
    value
)
fn MLReadTextures path platform destination =
(
    local reader = MLReader()
    local results = #()
    local image = undefined
    try
    (
        reader.openFile path
        if (reader.text 0 4) != "xet" do throw "Choose a Stories XTX or CHK texture dictionary."
        local logicalEnd = reader.atLong 8
        reader.check 0 logicalEnd
        local slot = reader.atLong 0x2C
        local visited = #()
        local nodes = #()
        while slot != 0x28 and slot != 0 do
        (
            if (findItem visited slot) != 0 do throw "The texture list contains a cycle."
            append visited slot
            if visited.count > 4096 do throw "Too many texture resources."
            local base = slot - 8
            reader.check base 0x50
            local header = reader.atLong base
            reader.check header 16
            append nodes #(base, header, reader.text (base + 16) 32)
            slot = reader.atLong (base + 12)
        )
        if nodes.count == 0 do throw "The texture dictionary is empty."
        makeDir destination all:true
        for record in nodes do
        (
            local header = record[2]
            local raster = 0
            local width = 0
            local height = 0
            local depth = 0
            local stride = 0
            local paletteOffset = 0
            local swizzle = 0
            local colorFormat = 0
            local logWidth = 0
            if platform == "PSP" then
            (
                raster = reader.atLong (header + 4)
                stride = reader.atShort (header + 8)
                reader.seek (header + 10)
                logWidth = reader.byte()
                local logHeight = reader.byte()
                depth = reader.byte()
                local mipCount = reader.byte()
                colorFormat = bit.and (reader.short()) 0x0F00
                if logWidth > 12 or logHeight > 12 do throw "Texture dimensions are invalid."
                width = bit.shift 1 logWidth
                height = bit.shift 1 logHeight
                if (findItem #(4,8,16,32) depth) == 0 do throw "Texture color depth is invalid."
                if mipCount > 8 do throw "Texture mip count is invalid."
                paletteOffset = raster
                local mipWidth = width
                local mipHeight = height
                for level = 0 to (amax 1 mipCount) - 1 do
                (
                    local pitch = ((ceil (mipWidth * depth / 8.0)) as integer)
                    if stride > 0 do pitch = amax 16 pitch (bit.shift stride (-level))
                    if stride > 0 and (mod pitch 16) != 0 do throw "Texture row size is invalid."
                    paletteOffset += pitch * mipHeight
                    mipWidth = amax 1 ((floor (mipWidth / 2.0)) as integer)
                    mipHeight = amax 1 ((floor (mipHeight / 2.0)) as integer)
                )
                if stride == 0 do paletteOffset = MLAlign paletteOffset 16
                swizzle = if stride > 0 then 1 else 0
            )
            else
            (
                raster = reader.atLong (header + 8)
                local flags = reader.atLong (header + 12)
                logWidth = MLBits flags 26 6
                local logHeight = MLBits flags 20 6
                depth = MLBits flags 14 6
                swizzle = bit.and flags 1
                if logWidth > 12 or logHeight > 12 or (findItem #(4,8,16,32) depth) == 0 do
                (
                    logWidth = MLBits flags 0 6
                    logHeight = MLBits flags 6 6
                    depth = MLBits flags 12 6
                    swizzle = bit.and (bit.shift flags -24) 1
                )
                if logWidth > 12 or logHeight > 12 or (findItem #(4,8,32) depth) == 0 do throw "This PS2 texture layout is not supported."
                width = bit.shift 1 logWidth
                height = bit.shift 1 logHeight
                paletteOffset = raster + ((ceil (width * height * depth / 8.0)) as integer)
                local nextData = reader.length
                for other in nodes do
                (
                    for candidate in #(other[1], other[2], reader.atLong (other[2] + 8)) where candidate > raster do nextData = amin nextData candidate
                )
                if depth < 16 do paletteOffset = nextData - (bit.shift 1 depth) * 4
            )
            local rowBytes = ((ceil (width * depth / 8.0)) as integer)
            local pitch = if stride > 0 then amax 16 rowBytes stride else rowBytes
            reader.check raster (pitch * height)
            local palette = #()
            if depth < 16 do
            (
                reader.check paletteOffset ((bit.shift 1 depth) * 4)
                for index = 0 to (bit.shift 1 depth) - 1 do append palette (MLTextureColor reader (paletteOffset + index * 4) 32 0 (platform == "PS2"))
            )
            local safeName = record[3]
            for char in #("/", "\\", ":", "*", "?", "\"", "<", ">", "|") do safeName = substituteString safeName char "_"
            if safeName == "" do safeName = "texture" + (results.count + 1) as string
            local imagePath = destination + "\\" + safeName + ".tga"
            if doesFileExist imagePath do throw "The texture folder already contains this image. Choose an empty folder."
            image = bitmap width height filename:imagePath
            for y = 0 to height - 1 do
            (
                local row = #()
                for x = 0 to width - 1 do
                (
                    local pixel = x + y * width
                    if platform == "PS2" and swizzle != 0 and depth < 16 do pixel = MLPs2Address x y logWidth
                    local byteOffset = ((floor (pixel * depth / 8.0)) as integer)
                    if platform == "PSP" then
                    (
                        local byteX = ((floor (x * depth / 8.0)) as integer)
                        byteOffset = if swizzle != 0 then MLPspAddress byteX y pitch else y * pitch + byteX
                    )
                    if depth < 16 then
                    (
                        reader.seek (raster + byteOffset)
                        local paletteIndex = reader.byte()
                        if depth == 4 do paletteIndex = if (mod pixel 2) == 0 then bit.and paletteIndex 15 else bit.shift paletteIndex -4
                        if platform == "PS2" and depth == 8 do paletteIndex = bit.or (bit.and paletteIndex (bit.not 0x18)) (#(0,16,8,24)[(MLBits paletteIndex 3 2) + 1])
                        append row palette[paletteIndex + 1]
                    )
                    else append row (MLTextureColor reader (raster + byteOffset) depth colorFormat (platform == "PS2"))
                )
                setPixels image [0,y] row
            )
            save image
            close image
            image = undefined
            append results #(record[3], imagePath)
        )
        reader.closeFile()
        results
    )
    catch
    (
        local reason = getCurrentException()
        if image != undefined do close image
        reader.closeFile()
        throw()
    )
)
fn MLCompareColors left right =
(
    if left[MLQuantAxis] < right[MLQuantAxis] then -1 else if left[MLQuantAxis] > right[MLQuantAxis] then 1 else 0
)
fn MLQuantCode value =
(
    bit.or (bit.shift ((value.r / 8) as integer) 0) (bit.or (bit.shift ((value.g / 8) as integer) 5) (bit.or (bit.shift ((value.b / 8) as integer) 10) (bit.shift ((value.a / 8) as integer) 15)))
)
fn MLQuantize pixels maximum =
(
    local table = dotNetObject "System.Collections.Hashtable"
    local samples = #()
    for value in pixels do
    (
        local code = MLQuantCode value
        if table.ContainsKey code then
        (
            local index = (table.get_Item code)
            samples[index][5] += 1
            for component = 1 to 4 do samples[index][component] += value[component]
        )
        else
        (
            append samples #(value.r, value.g, value.b, value.a, 1, code)
            table.Add code samples.count
        )
    )
    for sample in samples do for component = 1 to 4 do sample[component] /= sample[5]
    local boxes = #(samples)
    while boxes.count < maximum do
    (
        local selected = 0
        local axis = 1
        local best = -1.0
        for index = 1 to boxes.count where boxes[index].count > 1 do
        (
            local minimum = #(255.0,255.0,255.0,255.0)
            local maximumValues = #(0.0,0.0,0.0,0.0)
            for value in boxes[index] do for component = 1 to 4 do
            (
                minimum[component] = amin minimum[component] value[component]
                maximumValues[component] = amax maximumValues[component] value[component]
            )
            for component = 1 to 4 do
            (
                local score = (maximumValues[component] - minimum[component]) * boxes[index].count
                if score > best do (best = score; selected = index; axis = component)
            )
        )
        if selected == 0 do exit
        local values = boxes[selected]
        MLQuantAxis = axis
        qsort values MLCompareColors
        local halfway = ((floor (values.count / 2.0)) as integer)
        boxes[selected] = for index = 1 to halfway collect values[index]
        append boxes (for index = halfway + 1 to values.count collect values[index])
    )
    local palette = #()
    for values in boxes do
    (
        local total = 0.0
        local sums = #(0.0,0.0,0.0,0.0)
        for value in values do
        (
            total += value[5]
            for component = 1 to 4 do sums[component] += value[component] * value[5]
        )
        append palette (color (sums[1] / total) (sums[2] / total) (sums[3] / total) (sums[4] / total))
    )
    table.Clear()
    for value in samples do
    (
        local selected = 1
        local best = 1.0e30
        for index = 1 to palette.count do
        (
            local candidate = palette[index]
            local distanceSquared = 0.0
            for component = 1 to 4 do distanceSquared += (value[component] - candidate[component]) ^ 2
            if distanceSquared < best do (best = distanceSquared; selected = index)
        )
        table.Add value[6] (selected - 1)
    )
    local indices = for value in pixels collect (table.get_Item (MLQuantCode value))
    while palette.count < maximum do append palette (color 0 0 0 0)
    #(palette, indices)
)
fn MLWriteTextures destination imagePaths platform depth =
(
    if imagePaths.count == 0 do throw "Choose one or more bitmap images."
    if imagePaths.count > 4096 do throw "A texture dictionary can contain at most 4096 images."
    local seenNames = #()
    for path in imagePaths do
    (
        local name = toLower (getFilenameFile path)
        if (findItem seenNames name) != 0 do throw ("Two images have the same texture name: " + name)
        append seenNames name
    )
    if (findItem #(4,8) depth) == 0 do throw "Choose 16 or 256 colors."
    local writer = MLWriter()
    local temporary = MLTemporaryFile destination
    local image = undefined
    try
    (
        writer.openFile temporary
        writer.zeros (if platform == "PSP" then 0x30 else 0x44)
        writer.patchLong 0 0x00746578
        writer.patchLong 0x20 (if platform == "PSP" then 0x106 else if toLower (getFilenameType destination) == ".chk" then 0x8606 else 0xCC06)
        if platform == "PS2" do
        (
            if toLower (getFilenameType destination) == ".chk" then
            (
                writer.patchLong 0x30 1; writer.patchLong 0x34 0x0012FD70
                writer.patchLong 0x38 0x3B5; writer.patchLong 0x3C 0x0012FDB8
            )
            else
            (
                writer.patchLong 0x30 0xCCCCCCCC; writer.patchLong 0x34 0xCCCCCCCC
                writer.patchLong 0x3C 0x001D3B1C; writer.patchLong 0x40 0x07070040
            )
        )
        local nodes = #()
        for imagePath in imagePaths do
        (
            image = openBitmap imagePath
            local width = image.width
            local height = image.height
            local logWidth = 0
            local logHeight = 0
            while (bit.shift 1 logWidth) < width do logWidth += 1
            while (bit.shift 1 logHeight) < height do logHeight += 1
            if (bit.shift 1 logWidth) != width or (bit.shift 1 logHeight) != height or width < 8 or height < 8 or width > 4096 or height > 4096 do throw "Images must have power-of-two dimensions, from 8 through 4096."
            local name = getFilenameFile imagePath
            if name.count > (if platform == "PSP" then 31 else 63) do throw "A texture name is too long."
            local pixels = #()
            for y = 0 to height - 1 do join pixels (getPixels image [0,y] width)
            close image
            image = undefined
            local quantized = MLQuantize pixels (bit.shift 1 depth)
            local indices = quantized[2]
            if platform == "PS2" and depth == 8 do
                for index = 1 to indices.count do indices[index] = bit.or (bit.and indices[index] (bit.not 0x18)) (#(0,16,8,24)[(MLBits indices[index] 3 2) + 1])
            writer.align 16
            local raster = writer.tell()
            if depth == 8 then for value in indices do writer.byte value
            else for index = 1 to indices.count by 2 do writer.byte (bit.or indices[index] (bit.shift (if index + 1 <= indices.count then indices[index + 1] else 0) 4))
            if platform == "PSP" do writer.align 16
            for value in quantized[1] do
            (
                writer.byte (value.r as integer); writer.byte (value.g as integer); writer.byte (value.b as integer)
                writer.byte ((if platform == "PS2" then value.a * 128.0 / 255.0 else value.a) as integer)
            )
            writer.align 16
            local node = writer.tell()
            writer.zeros (if platform == "PSP" then 0x50 else 0x60)
            writer.align 16
            local header = writer.tell()
            if platform == "PSP" then
            (
                writer.long 0; writer.long raster; writer.short 0
                writer.byte logWidth; writer.byte logHeight; writer.byte depth; writer.byte 1
                writer.short (if depth == 4 then 0x4500 else 0x2500)
                append writer.relocations (header + 4)
            )
            else
            (
                writer.long 0
                writer.long (bit.or (if depth == 4 then 0x00450000 else 0x00250000) (if depth == 4 then width / 2 else width))
                writer.long raster
                writer.long (bit.or logWidth (bit.or (bit.shift logHeight 6) (bit.or (bit.shift depth 12) 0x00100000)))
                append writer.relocations (header + 8)
            )
            writer.pointer node header
            writer.pointer (node + 4) 0x20
            local end = writer.tell()
            writer.seek (node + 16)
            writer.text name
            writer.seek end
            append nodes node
        )
        writer.pointer 0x28 (nodes[nodes.count] + 8)
        writer.pointer 0x2C (nodes[1] + 8)
        for index = 1 to nodes.count do
        (
            writer.pointer (nodes[index] + 8) (if index == 1 then 0x28 else nodes[index - 1] + 8)
            writer.pointer (nodes[index] + 12) (if index == nodes.count then 0x28 else nodes[index + 1] + 8)
        )
        writer.align 4
        local relocationOffset = writer.tell()
        for offset in writer.relocations do writer.long offset
        local logicalEnd = writer.tell()
        writer.patchLong 8 logicalEnd
        writer.patchLong 12 relocationOffset
        writer.patchLong 16 relocationOffset
        writer.patchLong 20 writer.relocations.count
        writer.align 2048
        writer.closeFile()
        MLFinishFile temporary destination
        imagePaths.count
    )
    catch
    (
        local reason = getCurrentException()
        if image != undefined do close image
        writer.closeFile()
        if doesFileExist temporary do deleteFile temporary
        throw()
    )
)
