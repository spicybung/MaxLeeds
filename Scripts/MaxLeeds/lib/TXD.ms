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

global MLReadMobileTextures, MLMobileTxdHeader
-- Mobile dictionaries use grammar-delimited containers, including zero-size wrappers.
-- Leaf sizes remain authoritative. This decoder supports linear PSP-tagged rasters.
fn MLMobileTxdHeader reader offset kind =
(
    reader.check offset 12
    if reader.atLong offset != kind do throw "Unexpected Mobile TXD chunk type."
    local size = reader.atLong (offset + 4)
    if size < 0 do throw "Invalid Mobile TXD chunk size."
    reader.check (offset + 12) size
    #(offset + 12, offset + 12 + size, size)
)
fn MLReadMobileTextures path destination level:0 =
(
    local reader = MLReader()
    local output = MLTgaWriter()
    local temporary = undefined
    local results = #()
    try
    (
        reader.openFile path
        MLMobileTxdHeader reader 0 0x16
        local header = MLMobileTxdHeader reader 12 1
        if header[3] != 4 do throw "Invalid Mobile TXD dictionary header."
        local count = reader.atShort header[1]
        if count > 4096 do throw "Too many Mobile textures."
        local cursor = header[2]
        local entries = #()
        -- Validate the complete dictionary before creating output files.
        for entry = 1 to count do
        (
            header = MLMobileTxdHeader reader cursor 0x15
            header = MLMobileTxdHeader reader header[1] 1
            if header[3] != 8 or (reader.text header[1] 4) != "PSP" do throw "Mobile TXD currently requires PSP-tagged linear rasters; PS2 GIF uploads are not supported."
            header = MLMobileTxdHeader reader header[2] 2
            local name = reader.text header[1] header[3]
            header = MLMobileTxdHeader reader header[2] 2
            header = MLMobileTxdHeader reader header[2] 1
            header = MLMobileTxdHeader reader header[1] 1
            if header[3] != 20 do throw "Invalid Mobile raster header."
            local width = reader.atLong header[1]
            local height = reader.atLong (header[1] + 4)
            local depth = reader.atLong (header[1] + 8)
            local mips = reader.atLong (header[1] + 12)
            local flags = reader.atLong (header[1] + 16)
            if width < 1 or width > 8192 or height < 1 or height > 8192 or (findItem #(4,8,32) depth) == 0 or mips < 1 or mips > 14 do throw "Invalid Mobile raster dimensions or format."
            if flags != 0 do throw "Unsupported Mobile raster layout flags."
            if level < 0 or level >= mips do throw "Requested Mobile mip level is unavailable."
            header = MLMobileTxdHeader reader header[2] 1
            local raster = header[1]
            local bytes = 0
            local selected = raster
            local mipWidth = width
            local mipHeight = height
            local selectedWidth = width
            local selectedHeight = height
            for mip = 0 to mips - 1 do
            (
                if mip == level do (selected = raster + bytes; selectedWidth = mipWidth; selectedHeight = mipHeight)
                -- A final 1x1 4-bit mip still occupies one byte.
                bytes += (ceil (mipWidth * mipHeight * depth / 8.0)) as integer
                mipWidth = amax 1 (bit.shift mipWidth -1)
                mipHeight = amax 1 (bit.shift mipHeight -1)
            )
            local paletteSize = if depth == 32 then 0 else (bit.shift 1 depth) * 4
            if header[3] != bytes + paletteSize and not (depth == 32 and header[3] == bytes + 4) do throw "Mobile raster byte count does not match its mipmaps and palette."
            append entries #(name,selectedWidth,selectedHeight,depth,selected,raster + bytes)
            header = MLMobileTxdHeader reader header[2] 3
            cursor = header[2]
        )
        header = MLMobileTxdHeader reader cursor 3
        reader.seek header[2]
        while reader.tell() < reader.length do if reader.byte() != 0 do throw "Unexpected data after Mobile TXD."
        makeDir destination all:true
        for entry in entries do
        (
            local name = MLSafeTextureStem entry[1]
            local imagePath = destination + "\\" + name + ".tga"
            -- Never silently overwrite another sanitized texture name.
            local occupied = false
            for prior in results where (toLower prior[2]) == (toLower imagePath) do occupied = true
            if occupied do throw "Mobile texture names collide after filename sanitization."
            temporary = MLTemporaryFile imagePath
            output.openFile temporary entry[2] entry[3]
            local palette = #()
            if entry[4] < 32 do for index = 0 to (bit.shift 1 entry[4]) - 1 do append palette (MLTextureColor reader (entry[6] + index * 4) 32 0 false)
            local transparent = false
            for y = 0 to entry[3] - 1 do
            (
                local row = #()
                for x = 0 to entry[2] - 1 do
                (
                    local pixel = y * entry[2] + x
                    local value = undefined
                    if entry[4] == 32 then value = MLTextureColor reader (entry[5] + pixel * 4) 32 0 false
                    else
                    (
                        reader.seek (entry[5] + (if entry[4] == 8 then pixel else bit.shift pixel -1))
                        local index = reader.byte()
                        if entry[4] == 4 do index = if mod pixel 2 == 0 then bit.and index 15 else bit.shift index -4
                        value = palette[index + 1]
                    )
                    if value.a < 255 do transparent = true
                    append row value
                )
                output.writeRow row
            )
            output.closeFile()
            MLFinishFile temporary imagePath
            temporary = undefined
            append results #(entry[1],imagePath,transparent)
        )
        reader.closeFile()
        results
    )
    catch
    (
        output.closeFile()
        reader.closeFile()
        if temporary != undefined and doesFileExist temporary do deleteFile temporary
        throw()
    )
)
