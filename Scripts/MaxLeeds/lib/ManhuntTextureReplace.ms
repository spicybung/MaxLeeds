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

global MLReplaceManhuntTextures, MLMhTextureRecords

-- Source-preserving replacement: layout and all mip levels must already match.
-- Offsets, relocation tables, unknown metadata and unrelated textures stay intact.
fn MLMhTextureRecords reader =
(
    local count = reader.atLong 32
    if count > 65536 do throw "Invalid texture count."
    local current = reader.atLong 36
    local records = #()
    local visited = #()
    local names = #()
    for index = 1 to count do
    (
        if current < 48 or (findItem visited current) > 0 do throw "Invalid or cyclic texture list."
        append visited current
        reader.check current 112
        local name = toLower (MLSafeTextureStem (reader.text (current + 8) 32))
        if (findItem names name) > 0 do throw ("Ambiguous texture name: " + name)
        append names name
        local raster = reader.atLong (current + 96)
        local palette = reader.atLong (current + 100)
        local size = reader.atLong (current + 104)
        local depth = reader.atLong (current + 80)
        if raster < 48 or size < 1 do throw "Invalid texture raster."
        reader.check raster size
        local paletteSize = if depth == 4 or depth == 8 then (bit.shift 1 depth) * 4 else 0
        local dds = size >= 128 and (reader.text raster 4) == "DDS "
        if dds do paletteSize = 0
        if paletteSize > 0 do
        (
            if palette < 48 do throw "Invalid texture palette."
            reader.check palette paletteSize
        )
        append records #(name,current,raster,size,palette,paletteSize,dds)
        current = reader.atLong current
    )
    if count > 0 and (reader.atLong 40) != visited[visited.count] do throw "The texture list tail does not match its count."
    records
)
fn MLMhSameBytes first firstOffset second secondOffset count =
(
    first.check firstOffset count
    second.check secondOffset count
    first.seek firstOffset
    second.seek secondOffset
    for index = 1 to count do if first.byte() != second.byte() do return false
    true
)
fn MLMhCopyBytes reader offset writer destination count =
(
    reader.check offset count
    reader.seek offset
    writer.seek destination
    for index = 1 to count do writer.byte (reader.byte())
)
fn MLReplaceManhuntTextures source replacement destination =
(
    local decoded = undefined
    local donorDecoded = undefined
    local reader = MLReader()
    local donor = MLReader()
    local verified = MLReader()
    local writer = MLWriter()
    local temporary = MLTemporaryFile destination
    local packed = MLTemporaryFile destination
    local verificationDecoded = undefined
    try
    (
        decoded = MLDecodeResource source #("TCDT")
        MLOpenResource reader decoded[1] "TCDT"
        local payloadEnd = reader.length
        local relocationReader = MLReader()
        local relocationFields = #()
        try
        (
            relocationReader.openFile decoded[1]
            local relocationCount = relocationReader.atLong 20
            for index = 0 to relocationCount - 1 do append relocationFields (relocationReader.atLong (payloadEnd + index * 4))
            relocationReader.closeFile()
        )
        catch (relocationReader.closeFile(); throw())
        local records = MLMhTextureRecords reader
        donor.openFile replacement
        local isDDS = (donor.text 0 4) == "DDS "
        local donors = #()
        if isDDS then
        (
            if donor.length < 128 or (donor.atLong 4) != 124 do throw "Invalid DDS header."
            append donors #((toLower (MLSafeTextureStem (getFilenameFile replacement))),0,0,donor.length,0,0,true)
        )
        else
        (
            donor.closeFile()
            donorDecoded = MLDecodeResource replacement #("TCDT")
            MLOpenResource donor donorDecoded[1] "TCDT"
            donors = MLMhTextureRecords donor
        )
        if donors.count == 0 do throw "The replacement dictionary is empty."
        local ranges = #()
        for entry in donors do
        (
            local target = undefined
            for record in records where record[1] == entry[1] do target = record
            if target == undefined do throw ("Replacement has no matching source texture: " + entry[1])
            if target[4] != entry[4] or target[6] != entry[6] or target[7] != entry[7] do throw ("Raster size or format differs for " + entry[1] + ". Preserve the original format and mip chain.")
            if isDDS then
            (
                if not target[7] do throw "A DDS can only replace a PC DDS texture."
            )
            else if not (MLMhSameBytes reader (target[2] + 72) donor (entry[2] + 72) 24) do
                throw ("Texture dimensions, format, mip count or swizzle differ for " + entry[1])
            if target[7] and not (MLMhSameBytes reader target[3] donor entry[3] 128) do
                throw ("DDS headers differ for " + entry[1] + ". Export using the original dimensions, pixel format and mip settings.")
            append ranges #(target[3],entry[3],entry[4])
            if entry[6] > 0 do append ranges #(target[5],entry[5],entry[6])
        )
        -- Aliased payloads could silently alter another texture or its metadata.
        for range in ranges do
        (
            if range[1] < 48 do throw "A replacement overlaps the resource header."
            for field in relocationFields do
                if range[1] < field + 4 and range[1] + range[3] > field do throw "A replacement overlaps a relocation pointer."
            for record in records do
            (
                if range[1] < record[2] + 112 and range[1] + range[3] > record[2] do throw "A replacement overlaps a texture descriptor."
                for occupied in #(#(record[3],record[4]),#(record[5],record[6])) where occupied[2] > 0 do
                    if range[1] < occupied[1] + occupied[2] and range[1] + range[3] > occupied[1] do
                    (
                        if range[1] != occupied[1] or range[3] != occupied[2] do throw "Texture payloads overlap. Replacement is unsafe."
                        local owners = 0
                        for other in records do
                        (
                            if other[3] == range[1] do owners += 1
                            if other[6] > 0 and other[5] == range[1] do owners += 1
                        )
                        if owners != 1 do throw "Shared texture payloads must be separated before replacement."
                    )
            )
        )
        MLCopyFileRange decoded[1] 0 ((getFileSize decoded[1]) as integer) temporary
        writer.stream = fopen temporary "r+b"
        if writer.stream == undefined do throw "Cannot stage the texture dictionary."
        for range in ranges do MLMhCopyBytes donor range[2] writer range[1] range[3]
        writer.closeFile()
        MLOpenResource verified temporary "TCDT"
        local checked = MLMhTextureRecords verified
        if checked.count != records.count do throw "Texture replacement changed the dictionary structure."
        for range in ranges do if not (MLMhSameBytes verified range[1] donor range[2] range[3]) do throw "Texture payload failed read-back validation."
        verified.closeFile(); reader.closeFile(); donor.closeFile()
        if decoded[2] then
        (
            MLMhWriteCompressed temporary packed
            verificationDecoded = MLDecodeResource packed #("TCDT")
            if (MLFileDigest temporary) != (MLFileDigest verificationDecoded[1]) do throw "Compressed texture dictionary failed verification."
            deleteFile verificationDecoded[1]; verificationDecoded = undefined
            MLFinishFile packed destination
        )
        else MLFinishFile temporary destination
        if doesFileExist temporary do deleteFile temporary
        if decoded[2] do deleteFile decoded[1]
        if donorDecoded != undefined and donorDecoded[2] do deleteFile donorDecoded[1]
        donors.count
    )
    catch
    (
        reader.closeFile(); donor.closeFile(); verified.closeFile(); writer.closeFile()
        if doesFileExist temporary do deleteFile temporary
        if doesFileExist packed do deleteFile packed
        if decoded != undefined and decoded[2] and doesFileExist decoded[1] do deleteFile decoded[1]
        if donorDecoded != undefined and donorDecoded[2] and doesFileExist donorDecoded[1] do deleteFile donorDecoded[1]
        if verificationDecoded != undefined and verificationDecoded[2] and doesFileExist verificationDecoded[1] do deleteFile verificationDecoded[1]
        throw()
    )
)
