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

global MLWriteManhuntTextures, MLMhMipChain, MLMhWriteDxt
fn MLMhColorByte value = (amax 0 (amin 255 (floor (value + 0.5)))) as integer
fn MLMhWriteDds writer levels format =
(
    local width = levels[1][1]
    local height = levels[1][2]
    local compressed = format != "RGBA32"
    local pitch = if compressed then (((width + 3) / 4) as integer) * (((height + 3) / 4) as integer) * (if format == "DXT1" then 8 else 16) else width * 4
    local start = writer.tell()
    writer.zeros 128
    writer.patchLong start 0x20534444
    writer.patchLong (start + 4) 124
    local flags = bit.or 0x1007 (if compressed then 0x80000 else 8)
    if levels.count > 1 do flags = bit.or flags 0x20000
    writer.patchLong (start + 8) flags
    writer.patchLong (start + 12) height
    writer.patchLong (start + 16) width
    writer.patchLong (start + 20) pitch
    writer.patchLong (start + 28) levels.count
    writer.patchLong (start + 76) 32
    if compressed then
    (
        writer.patchLong (start + 80) 4
        writer.patchLong (start + 84) (case format of ("DXT1": 0x31545844; "DXT3": 0x33545844; "DXT5": 0x35545844))
    )
    else
    (
        writer.patchLong (start + 80) 0x41
        writer.patchLong (start + 88) 32
        writer.patchLong (start + 92) 0x00FF0000
        writer.patchLong (start + 96) 0x0000FF00
        writer.patchLong (start + 100) 0x000000FF
        writer.patchLong (start + 104) 0xFF000000
    )
    writer.patchLong (start + 108) (if levels.count > 1 then 0x401008 else 0x1000)
    for level in levels do
    (
        if compressed then MLMhWriteDxt writer level[1] level[2] level[3] format
        else for value in level[3] do
        (
            writer.byte (MLMhColorByte value.b); writer.byte (MLMhColorByte value.g)
            writer.byte (MLMhColorByte value.r); writer.byte (MLMhColorByte value.a)
        )
    )
    pitch
)
fn MLWriteManhuntTextures destination imagePaths platform depth mipmapsEnabled:false compression:"RGBA32" =
(
    if (findItem #("RGBA32","DXT1","DXT3","DXT5") compression) == 0 do throw "Unsupported DDS compression selection."
    if platform != "PC" and compression != "RGBA32" do throw "DXT compression is a PC option."
    if imagePaths.count == 0 or imagePaths.count > 4096 do throw "Choose between 1 and 4096 images."
    if (findItem #("PC","PS2","PSP") platform) == 0 do throw "Unknown Manhunt texture platform."
    if (findItem #(4,8,16,32) depth) == 0 do throw "Choose a supported texture depth."
    if platform == "PC" do depth = 32
    local names = #()
    for path in imagePaths do
    (
        local name = getFilenameFile path
        if name.count == 0 or name.count > 31 do throw "Manhunt texture names must contain 1 to 31 characters."
        for character = 1 to name.count do if (bit.charAsInt name[character]) < 32 or (bit.charAsInt name[character]) > 126 do throw "Use ASCII texture names."
        local normalized = toLower (MLSafeTextureStem name)
        if (findItem names normalized) > 0 do throw "Two images have the same texture name."
        append names normalized
    )
    local writer = MLWriter()
    local reader = MLReader()
    local image = undefined
    local temporary = MLTemporaryFile destination
    try
    (
        writer.openFile temporary
        writer.zeros (48 + imagePaths.count * 112)
        writer.patchLong 0 0x54444354
        writer.patchLong 4 1
        writer.patchLong 32 imagePaths.count
        writer.pointer 36 48
        writer.pointer 40 (48 + (imagePaths.count - 1) * 112)
        for imageIndex = 1 to imagePaths.count do
        (
            local path = imagePaths[imageIndex]
            local descriptor = 48 + (imageIndex - 1) * 112
            if imageIndex < imagePaths.count do writer.pointer descriptor (descriptor + 112)
            if imageIndex > 1 do writer.pointer (descriptor + 4) (descriptor - 112)
            local finish = writer.tell()
            writer.seek (descriptor + 8); writer.text (getFilenameFile path); writer.seek finish
            local width = 0
            local height = 0
            local pitch = 0
            local mipmaps = 1
            writer.align 16
            local raster = writer.tell()
            local palette = #()
            if platform == "PC" and (toLower (getFilenameType path)) == ".dds" then
            (
                reader.openFile path
                if reader.length < 128 or (reader.text 0 4) != "DDS " or (reader.atLong 4) != 124 or (reader.atLong 76) != 32 do throw "Invalid DDS image."
                width = reader.atLong 16; height = reader.atLong 12
                pitch = reader.atLong 20
                mipmaps = amax 1 (reader.atLong 28)
                if width < 1 or height < 1 or width > 16384 or height > 16384 or mipmaps > 15 do throw "DDS dimensions or mip count exceed the supported limits."
                if (reader.atLong 112) != 0 or (reader.text 84 4) == "DX10" do throw "Use a legacy 2D DDS rather than a cube, volume or DX10 image."
                local format = reader.text 84 4
                local bits = reader.atLong 88
                local compressed = (findItem #("DXT1","DXT3","DXT5") format) > 0
                if not compressed and ((reader.atLong 84) != 0 or (findItem #(8,16,24,32) bits) == 0) do throw "Unsupported legacy DDS pixel format."
                local maximumMips = 1
                local dimension = amax width height
                while dimension > 1 do (dimension = amax 1 ((dimension / 2) as integer); maximumMips += 1)
                if mipmaps > maximumMips do throw "DDS declares too many mip levels for its dimensions."
                local required = 128L
                for level = 0 to mipmaps - 1 do
                (
                    local mipWidth = amax 1 (bit.shift width (-level))
                    local mipHeight = amax 1 (bit.shift height (-level))
                    if compressed then
                        required += (((mipWidth + 3) / 4) as integer) * (((mipHeight + 3) / 4) as integer) * (if format == "DXT1" then 8 else 16)
                    else
                    (
                        local rowBytes = ((mipWidth * bits + 7) / 8) as integer
                        if level == 0 and (bit.and (reader.atLong 8) 8) != 0 do
                        (
                            if pitch < rowBytes do throw "DDS pitch is smaller than one pixel row."
                            rowBytes = pitch
                        )
                        -- A hostile 32-bit pitch must not wrap the size calculation.
                        required += (rowBytes as integer64) * mipHeight
                    )
                )
                if reader.length < required do throw "DDS pixel data or mip levels are truncated."
                MLMhCopyBytes reader 0 writer raster reader.length
                reader.closeFile()
            )
            else
            (
                image = openBitmap path
                width = image.width; height = image.height
                if width < 1 or height < 1 or width > 4096 or height > 4096 or width * height > 16777216 do throw "Bitmap dimensions must be between 1 and 4096."
                if platform != "PC" do
                (
                    local logWidth = 0
                    local logHeight = 0
                    while (bit.shift 1 logWidth) < width do logWidth += 1
                    while (bit.shift 1 logHeight) < height do logHeight += 1
                    if width < 8 or height < 8 or (bit.shift 1 logWidth) != width or (bit.shift 1 logHeight) != height do throw "Console textures require power-of-two dimensions of at least 8 pixels."
                )
                local pixels = #()
                for y = 0 to height - 1 do join pixels (getPixels image [0,y] width)
                close image; image = undefined
                if platform == "PC" then
                (
                    local levels = MLMhMipChain width height pixels mipmapsEnabled
                    mipmaps = levels.count
                    pitch = MLMhWriteDds writer levels compression
                )
                else
                (
                    local levels = MLMhMipChain width height pixels mipmapsEnabled
                    mipmaps = levels.count
                    local indices = #()
                    if depth <= 8 do
                    (
                        local allPixels = #()
                        for level in levels do join allPixels level[3]
                        local quantized = MLQuantize allPixels (bit.shift 1 depth)
                        palette = quantized[1]; indices = quantized[2]
                    )
                    local baseWidth = width
                    local baseHeight = height
                    local indexBase = 0
                    pitch = if platform == "PSP" then amax 16 (((width * depth + 7) / 8) as integer) else ((width * depth + 7) / 8) as integer
                    for level in levels do
                    (
                        width = level[1]; height = level[2]; pixels = level[3]
                        local levelPitch = if platform == "PSP" then amax 16 (((width * depth + 7) / 8) as integer) else ((width * depth + 7) / 8) as integer
                        local rasterSize = if platform == "PSP" then levelPitch * (MLAlign height 8) else (((width * height * depth + 7) / 8) as integer)
                        local levelStart = writer.tell()
                        writer.zeros rasterSize
                        for y = 0 to height - 1 do for x = 0 to width - 1 do
                        (
                            local pixel = x + y * width + 1
                            local byteX = ((x * depth) / 8) as integer
                            local address = levelStart + (if platform == "PSP" then MLPspAddress byteX y levelPitch else (((pixel - 1) * depth / 8) as integer))
                            writer.seek address
                            if depth == 4 then
                            (
                                if (if platform == "PSP" then (mod x 2) == 0 else (mod (pixel - 1) 2) == 0) do
                                (
                                    local packed = indices[indexBase + pixel]
                                    if (if platform == "PSP" then x + 1 < width else pixel < width * height) do packed += indices[indexBase + pixel + 1] * 16
                                    writer.byte packed
                                )
                            )
                            else if depth == 8 then writer.byte indices[indexBase + pixel]
                            else
                            (
                                local value = pixels[pixel]
                                if depth == 16 then
                                (
                                    local red = (floor (value.r * 31.0 / 255.0)) as integer
                                    local green = (floor (value.g * 31.0 / 255.0)) as integer
                                    local blue = (floor (value.b * 31.0 / 255.0)) as integer
                                    writer.short (red + (bit.shift green 5) + (bit.shift blue 10) + (if value.a >= 127.5 then 32768 else 0))
                                )
                                else
                                (
                                    writer.byte (MLMhColorByte value.r); writer.byte (MLMhColorByte value.g); writer.byte (MLMhColorByte value.b)
                                    writer.byte (if platform == "PS2" then (floor (value.a * 128.0 / 255.0 + 0.5)) as integer else MLMhColorByte value.a)
                                )
                            )
                        )
                        writer.seek (levelStart + rasterSize)
                        indexBase += width * height
                    )
                    width = baseWidth; height = baseHeight
                )
            )
            local rasterSize = writer.tell() - raster
            writer.pointer (descriptor + 96) raster
            writer.patchLong (descriptor + 104) rasterSize
            if palette.count > 0 do
            (
                writer.align 16
                local paletteStart = writer.tell()
                writer.zeros (palette.count * 4)
                for index = 0 to palette.count - 1 do
                (
                    local slot = index
                    if platform == "PS2" and depth == 8 do slot = bit.or (bit.and index (bit.not 24)) (bit.or (bit.shift (bit.and index 8) 1) (bit.shift (bit.and index 16) -1))
                    writer.seek (paletteStart + slot * 4)
                    local value = palette[index + 1]
                    writer.byte (MLMhColorByte value.r); writer.byte (MLMhColorByte value.g); writer.byte (MLMhColorByte value.b)
                    writer.byte (if platform == "PS2" then (floor (value.a * 128.0 / 255.0 + 0.5)) as integer else MLMhColorByte value.a)
                )
                writer.seek (paletteStart + palette.count * 4)
                writer.pointer (descriptor + 100) paletteStart
            )
            writer.patchLong (descriptor + 72) width
            writer.patchLong (descriptor + 76) height
            writer.patchLong (descriptor + 80) depth
            writer.patchLong (descriptor + 84) pitch
            finish = writer.tell()
            writer.seek (descriptor + 92); writer.byte mipmaps
            writer.seek finish
        )
        writer.align 4
        local table = writer.tell()
        sort writer.relocations
        for field in writer.relocations do writer.long field
        writer.patchLong 8 (writer.tell())
        writer.patchLong 12 table; writer.patchLong 16 table
        writer.patchLong 20 writer.relocations.count
        writer.closeFile()
        MLOpenResource reader temporary "TCDT"
        local records = MLMhTextureRecords reader
        if records.count != imagePaths.count do throw "Encoded texture dictionary failed structural validation."
        reader.closeFile()
        MLFinishFile temporary destination
        imagePaths.count
    )
    catch
    (
        if image != undefined do close image
        reader.closeFile(); writer.closeFile()
        if doesFileExist temporary do deleteFile temporary
        throw()
    )
)
