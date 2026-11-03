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

global MLWriteWorldPlacements
fn MLWriteWorldPlacements destination nodes =
(
    local roots = for node in nodes where MLUserFlag node "MaxLeedsRoot" collect node
    if roots.count != 1 do throw "Select one imported Stories world root."
    local source = getUserProp roots[1] "MaxLeedsIMG"
    local digest = getUserProp roots[1] "MaxLeedsIMGHash"
    if source == undefined or not doesFileExist source do throw "The original world IMG is missing."
    if digest == undefined or digest != (MLFileDigest source) do throw "Reimport the world: its source IMG is unverified or has changed."
    local temporary = MLTemporaryFile destination
    local reader = MLReader()
    local writer = MLWriter()
    try
    (
        reader.openFile source
        local changes = #()
        local occupied = #()
        for node in nodes where (getUserProp node "MaxLeedsPlacementAddresses") != undefined do
        (
            local entries = filterString (getUserProp node "MaxLeedsPlacementAddresses") ";"
            for entry in entries do
            (
                local fields = filterString entry ","
                if fields.count != 4 do throw "Invalid placement source metadata. Reimport the world."
                local address = fields[1] as integer
                if address == undefined do throw "Invalid placement address. Reimport the world."
                for previous in occupied do if address < previous + 80 and previous < address + 80 do throw "Scene placement records overlap in the source IMG. Remove duplicate objects or reimport the world."
                append occupied address
                reader.check address 80
                if (reader.atShort (address + 2)) != ((getUserProp node "MaxLeedsResourceID") as integer) or (bit.and (reader.atShort address) 32767) != ((getUserProp node "MaxLeedsIPLID") as integer) do throw "Placement metadata no longer matches the source IMG."
                local origin = [fields[2] as float,fields[3] as float,fields[4] as float]
                local transform = copy node.transform
                transform.row4 -= origin
                if (length (cross transform.row1 transform.row2)) < 0.0000001 or abs (dot (cross transform.row1 transform.row2) transform.row3) < 0.0000001 do throw "Cannot export a placement with a singular transform."
                for row = 1 to 4 do for axis = 1 to 3 do
                    if transform[row][axis] != transform[row][axis] or abs transform[row][axis] > 1.0e20 do throw "Placement transform is not finite."
                append changes #(address,transform)
            )
        )
        if changes.count == 0 do throw "No imported world placements were selected."
        MLCopyFileRange source 0 reader.length temporary
        writer.stream = fopen temporary "r+b"
        if writer.stream == undefined do throw "Cannot stage the world IMG."
        for change in changes do for row = 1 to 4 do
        (
            writer.seek (change[1] + 16 + (row - 1) * 16)
            writer.point change[2][row]
        )
        writer.closeFile(); reader.closeFile()
        reader.openFile temporary
        for change in changes do
        (
            local actual = reader.matrix (change[1] + 16)
            for row = 1 to 4 do if (distance actual[row] change[2][row]) > 0.01 do throw "A world placement failed read-back validation."
        )
        reader.closeFile()
        MLFinishFile temporary destination
        changes.count
    )
    catch
    (
        reader.closeFile(); writer.closeFile()
        if doesFileExist temporary do deleteFile temporary
        throw()
    )
)
