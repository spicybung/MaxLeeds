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

global MLReadManhuntTextures, MLImportManhuntTextures
fn MLMhDdsAlpha reader offset size =
(
    local format = reader.text (offset + 84) 4
    if format == "DXT3" or format == "DXT5" do return true
    if format == "DXT1" then
    (
        for block = offset + 128 to offset + size - 8 by 8 do
        (
            local first = reader.atShort block
            local second = reader.atShort (block + 2)
            if first <= second do
            (
                local indices = reader.atLong (block + 4)
                for pixel = 0 to 15 do if (MLBits indices (pixel * 2) 2) == 3 do return true
            )
        )
        false
    )
    else (reader.atLong (offset + 104)) != 0
)
fn MLReadManhuntTextures path platform destination =
(
    local decoded = MLDecodeResource path #("TCDT")
    local reader = MLReader()
    local output = undefined
    local temporary = undefined
    local results = #()
    try
    (
        MLOpenResource reader decoded[1] "TCDT"
        local count = reader.atLong 32
        local current = reader.atLong 36
        if count > 65536 do throw "Invalid Manhunt texture count."
        local descriptors = #()
        local visited = #()
        local names = #()
        local detected = ""
        for index = 1 to count do
        (
            if (findItem visited current) != 0 do throw "The Manhunt texture list contains a cycle."
            append visited current
            reader.check current 112
            local name = reader.text (current + 8) 32
            if name == "" do name = "texture_" + index as string
            local stem = MLSafeTextureStem name
            if (findItem names (toLower stem)) != 0 do throw ("Two texture names resolve to the same output filename: " + stem)
            append names (toLower stem)
            local width = reader.atLong (current + 72)
            local height = reader.atLong (current + 76)
            local depth = reader.atLong (current + 80)
            local raster = reader.atLong (current + 96)
            local palette = reader.atLong (current + 100)
            local size = reader.atLong (current + 104)
            reader.seek (current + 93)
            local swizzle = reader.byte()
            local isDDS = raster >= 48 and raster + 4 <= reader.length and (reader.text raster 4) == "DDS "
            if isDDS then
            (
                reader.check raster size
                if size < 128 or (reader.atLong (raster + 4)) != 124 do throw "Invalid DDS header in the Manhunt texture."
                width = reader.atLong (raster + 16)
                height = reader.atLong (raster + 12)
                detected = "PC"
            )
            else if swizzle != 0 and detected != "PC" do detected = "PS2"
            if width < 1 or height < 1 or width > 16384 or height > 16384 or width > 16777216 / height do throw "Invalid Manhunt texture dimensions."
            if not isDDS and (findItem #(4,8,16,32) depth) == 0 do throw "Unsupported Manhunt texture depth."
            append descriptors #(name,stem,width,height,depth,raster,palette,size,swizzle,isDDS)
            current = reader.atLong current
        )
        if platform == "Auto" or platform == "AUTO" do
        (
            if detected == "" do
            (
                local stem = toLower (getFilenameFile path)
                if (findString stem "ps2") != undefined then detected = "PS2"
                else if (findString stem "psp") != undefined then detected = "PSP"
                else throw "This linear console dictionary has no reliable platform marker. Choose PS2 or PSP explicitly."
            )
            platform = detected
        )
        makeDir destination all:true
        for descriptor in descriptors do
        (
            local name = descriptor[1]
            local width = descriptor[3]
            local height = descriptor[4]
            local depth = descriptor[5]
            local raster = descriptor[6]
            local ps2 = platform == "PS2"
            if descriptor[10] then
            (
                local pathOut = destination + "\\" + descriptor[2] + ".dds"
                local alpha = MLMhDdsAlpha reader raster descriptor[8]
                MLCopyFileRange decoded[1] raster descriptor[8] pathOut
                append results #(name,pathOut,alpha)
            )
            else
            (
                if platform == "PC" do throw "A PC texture descriptor does not contain a DDS image."
                local palette = #()
                if depth <= 8 do
                (
                    reader.check descriptor[7] ((bit.shift 1 depth) * 4)
                    for index = 0 to (bit.shift 1 depth) - 1 do
                    (
                        local slot = index
                        if ps2 and depth == 8 do slot = bit.or (bit.and index (bit.not 24)) (bit.or (bit.shift (bit.and index 8) 1) (bit.shift (bit.and index 16) -1))
                        append palette (MLTextureColor reader (descriptor[7] + slot * 4) 32 0 ps2)
                    )
                )
                local logWidth = 0
                while (bit.shift 1 logWidth) < width do logWidth += 1
                if ps2 and (bit.and descriptor[9] 1) != 0 and (bit.shift 1 logWidth) != width do throw "A swizzled PS2 texture has a non-power-of-two width."
                local pitch = amax 16 (((width * depth + 7) / 8) as integer)
                if not ps2 and (mod pitch 16) != 0 do throw "The PSP texture row pitch is invalid."
                local pathOut = destination + "\\" + descriptor[2] + ".tga"
                temporary = MLTemporaryFile pathOut
                output = MLTgaWriter()
                output.openFile temporary width height
                local alpha = false
                for y = 0 to height - 1 do
                (
                    local pixels = #()
                    for x = 0 to width - 1 do
                    (
                        local pixelIndex = x + y * width
                        local address = raster
                        local nibble = bit.and x 1
                        if ps2 then
                        (
                            if depth <= 8 do
                            (
                                if (bit.and descriptor[9] 1) != 0 do
                                (
                                    pixelIndex = MLPs2Address x y logWidth
                                    if pixelIndex >= width * height do throw "PS2 swizzle addresses outside the texture raster."
                                    if depth == 4 do nibble = bit.and (bit.shift y -1) 1
                                )
                            )
                            address += ((pixelIndex * depth) / 8) as integer
                        )
                        else address += MLPspAddress (((x * depth) / 8) as integer) y pitch
                        local bytesNeeded = if depth <= 8 then 1 else depth / 8
                        if address < raster or address + bytesNeeded > raster + descriptor[8] do throw "A texture pixel lies outside its declared raster."
                        local value = undefined
                        if depth <= 8 then
                        (
                            reader.seek address
                            local index = reader.byte()
                            if depth == 4 do index = MLBits index (nibble * 4) 4
                            value = palette[index + 1]
                        )
                        else value = MLTextureColor reader address depth (if depth == 16 then 256 else 0) (ps2 and depth == 32)
                        if value.a < 255 do alpha = true
                        append pixels value
                    )
                    output.writeRow pixels
                )
                output.closeFile(); output = undefined
                MLFinishFile temporary pathOut
                temporary = undefined
                append results #(name,pathOut,alpha)
            )
        )
        reader.closeFile()
        if decoded[2] do deleteFile decoded[1]
        results
    )
    catch
    (
        if output != undefined do output.closeFile()
        if temporary != undefined and doesFileExist temporary do deleteFile temporary
        reader.closeFile()
        if decoded[2] and doesFileExist decoded[1] do deleteFile decoded[1]
        throw()
    )
)
fn MLImportManhuntTextures modelPath platform nodes =
(
    local directory = getFilenamePath modelPath
    local stem = toLower (getFilenameFile modelPath)
    local candidates = #()
    join candidates (getFiles (directory + "*.tex"))
    join candidates (getFiles (directory + "*.txd"))
    local preferred = #(stem, if platform == "PS2" then "texps2" else if platform == "PSP" then "texpsp" else "texpc", "textures")
    local selected = #()
    for wanted in preferred do for path in candidates where (toLower (getFilenameFile path)) == wanted and (findItem selected path) == 0 do append selected path
    if selected.count == 0 and candidates.count == 1 do append selected candidates[1]
    local imported = 0
    local assigned = 0
    for path in selected do
    (
        local folder = directory + (getFilenameFile modelPath) + "_textures\\" + (MLSafeTextureStem (getFilenameFile path))
        local records = MLReadManhuntTextures path platform folder
        imported += records.count
        assigned += MLApplyTextures records nodes onlyMissing:true
    )
    #(imported,assigned)
)
