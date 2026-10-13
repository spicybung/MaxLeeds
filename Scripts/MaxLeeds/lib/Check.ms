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
fn MLCheckTools =
(
    local node = undefined
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
    try
    (
        makeDir folder all:true
        writer.openFile binaryPath
        writer.long 0x7F123456
        writer.signedShort -1234
        writer.float 1.25
        writer.closeFile()
        reader.openFile binaryPath
        if reader.long() != 0x7F123456 or reader.signedShort() != -1234 or (abs (reader.float() - 1.25)) > 0.00001 do throw "Binary stream checks failed."
        reader.closeFile()
        local layout = MLPspLayout 0x1FF
        if layout[3] != 36 do throw "PSP vertex stride checks failed."
        if MLPspAddress 16 8 32 != 384 do throw "PSP raster addressing checks failed."
        node = mesh name:"MaxLeeds_check_triangle" vertices:#([0,0,0],[1,0,0],[0,1,0]) faces:#([1,2,3])
        MLWritePspObject modelPath #(node) "VCS" 100
        local model = MLReadModel modelPath "VCS" "PSP"
        if model.parts.count != 1 or model.parts[1].vertices.count != 3 or model.modelID != 100 do throw "PSP model write/read checks failed."
        if distance model.parts[1].vertices[2] [1,0,0] > 0.00001 do throw "PSP model scale checks failed."
        MLWriteCollision collisionPath #(node)
        reader.openFile collisionPath
        if (reader.text 0 4) != "2loc" do throw "Collision header checks failed."
        local pointer = reader.atLong 0x24
        if (reader.atShort (pointer + 0x34)) != 1 do throw "Collision triangle count checks failed."
        if (mod reader.length 2048) != 0 do throw "Collision sector padding checks failed."
        reader.closeFile()
        delete node
        node = undefined
        for path in #(binaryPath,modelPath,collisionPath) where doesFileExist path do deleteFile path
        (dotNetClass "System.IO.Directory").Delete folder
        select savedSelection
        "Binary streams, PSP addressing, model round trip and COL2 checks passed."
    )
    catch
    (
        local reason = getCurrentException()
        reader.closeFile(); writer.closeFile()
        if node != undefined and isValidNode node do delete node
        for path in #(binaryPath,modelPath,collisionPath) where doesFileExist path do deleteFile path
        try ((dotNetClass "System.IO.Directory").Delete folder) catch ()
        select savedSelection
        throw()
    )
)
