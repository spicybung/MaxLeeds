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

global MLDecodeResource, MLOpenResource, MLSafeTextureStem, MLCopyFileRange
fn MLSafeTextureStem value =
(
    local name = getFilenameFile (filenameFromPath value)
    for character in #("<",">",":","\"","/","\\","|","?","*") do name = substituteString name character "_"
    for code = 1 to 31 do name = substituteString name (bit.intAsChar code) "_"
    name = trimRight name " ."
    if name == "" or name == "." or name == ".." do name = "texture"
    local reserved = #("con","prn","aux","nul","com1","com2","com3","com4","com5","com6","com7","com8","com9","lpt1","lpt2","lpt3","lpt4","lpt5","lpt6","lpt7","lpt8","lpt9")
    if (findItem reserved (toLower name)) > 0 do name = "texture_" + name
    name
)
fn MLDecodeResource path accepted scanHeader:false =
(
    local probe = MLReader()
    local offsets = #()
    local expected = 0
    try
    (
        probe.openFile path
        local magic = probe.text 0 4
        if (findItem accepted magic) > 0 do (probe.closeFile(); return #(path,false))
        if magic == "Z2HM" then
        (
            expected = probe.atLong 4
            if expected > 536870912 do throw "The resource declares more than 512 MiB of decompressed data."
            append offsets 8
        )
        else if scanHeader then
        (
            for offset = 0 to (amin 127 (probe.length - 2)) do
            (
                probe.seek offset
                local first = probe.byte()
                local second = probe.byte()
                if (bit.and first 15) == 8 and first < 128 and (mod (first * 256 + second) 31) == 0 and (bit.and second 32) == 0 do append offsets offset
            )
        )
        else append offsets 0
        probe.closeFile()
    )
    catch (probe.closeFile(); throw())
    local reason = "No supported compressed resource was found."
    for offset in offsets do
    (
        local temporary = MLTemporaryFile ((getDir #temp) + "\\MaxLeeds-resource.bin")
        local input = undefined
        local output = undefined
        local inflater = undefined
        local check = MLReader()
        try
        (
            input = (dotNetClass "System.IO.File").OpenRead path
            input.Position = offset
            local first = input.ReadByte()
            local second = input.ReadByte()
            if first < 0 or second < 0 or (bit.and first 15) != 8 or first >= 128 or (mod (first * 256 + second) 31) != 0 or (bit.and second 32) != 0 do throw "Invalid zlib resource header."
            inflater = dotNetObject "System.IO.Compression.DeflateStream" input ((dotNetClass "System.IO.Compression.CompressionMode").Decompress)
            output = (dotNetClass "System.IO.File").Create temporary
            local buffer = (dotNetClass "System.Array").CreateInstance (dotNetClass "System.Byte") 65536
            local total = 0
            local amount = inflater.Read buffer 0 65536
            while amount > 0 do
            (
                total += amount
                if total > 536870912 do throw "The decompressed resource exceeds 512 MiB."
                output.Write buffer 0 amount
                amount = inflater.Read buffer 0 65536
            )
            output.Close(); output = undefined
            inflater.Close(); inflater = undefined
            input.Close(); input = undefined
            if expected != 0 and total != expected do throw "The decoded resource size does not match the Z2HM header."
            check.openFile temporary
            local magic = check.text 0 4
            check.closeFile()
            if (findItem accepted magic) == 0 do throw "The decoded resource signature does not match this file type."
            return #(temporary,true)
        )
        catch
        (
            reason = getCurrentException()
            check.closeFile()
            if output != undefined do output.Close()
            if inflater != undefined do inflater.Close()
            if input != undefined do input.Close()
            if doesFileExist temporary do deleteFile temporary
        )
    )
    throw reason
)
fn MLOpenResource reader path magic =
(
    reader.openFile path
    reader.check 0 48
    if (reader.text 0 4) != magic do throw ("Expected a " + magic + " resource.")
    local end = reader.atLong 16
    local relocations = reader.atLong 20
    if end < 48 or end > reader.length or relocations > (reader.length - end) / 4 do throw "The resource relocation table is invalid."
    for index = 0 to relocations - 1 do
    (
        local field = reader.atLong (end + index * 4)
        if field < 0 or field > end - 4 do throw "A resource relocation field is outside its payload."
        local target = reader.atLong field
        if target != 0 and (target < 0 or target >= end) do throw "A resource relocation target is outside its payload."
    )
    reader.length = end
    true
)
fn MLCopyFileRange inputPath offset count destination =
(
    local input = undefined
    local output = undefined
    local temporary = MLTemporaryFile destination
    try
    (
        input = (dotNetClass "System.IO.File").OpenRead inputPath
        if offset < 0 or count < 0 or offset > input.Length - count do throw "The output range is outside the source file."
        input.Position = offset
        output = (dotNetClass "System.IO.File").Create temporary
        local buffer = (dotNetClass "System.Array").CreateInstance (dotNetClass "System.Byte") 65536
        local remaining = count
        while remaining > 0 do
        (
            local amount = input.Read buffer 0 (amin remaining 65536)
            if amount == 0 do throw "The input file changed or ended during extraction."
            output.Write buffer 0 amount
            remaining -= amount
        )
        output.Close(); output = undefined
        input.Close(); input = undefined
        MLFinishFile temporary destination
    )
    catch
    (
        if output != undefined do output.Close()
        if input != undefined do input.Close()
        if doesFileExist temporary do deleteFile temporary
        throw()
    )
)
