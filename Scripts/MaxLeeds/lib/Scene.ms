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

global MLSelectedFamily, MLApplyTextures, MLMaterialImages, MLFindModelTextures, MLTextureDictionaryNames, MLImportModelTextures
fn MLVisitFamilyNode node result =
(
    if (findItem result node) == 0 do append result node
    for child in node.children do MLVisitFamilyNode child result
)
fn MLSelectedFamily =
(
    if selection.count == 0 do throw "Select a model or its mesh parts."
    local roots = #()
    for node in selection do
    (
        local root = node
        local ancestor = node
        while ancestor != undefined do
        (
            if (getUserProp ancestor "MaxLeedsRoot") == "true" do root = ancestor
            ancestor = ancestor.parent
        )
        if (findItem roots root) == 0 do append roots root
    )
    local result = #()
    for root in roots do MLVisitFamilyNode root result
    result
)
fn MLApplyTextures images nodes =
(
    local assigned = 0
    for node in nodes where node.material != undefined do
    (
        local materials = if (classof node.material) == MultiMaterial then node.material.materialList else #(node.material)
        for material in materials where material != undefined do
        (
            local materialName = toLower material.name
            for record in images do
            (
                local textureName = toLower record[1]
                if materialName == textureName or (getFilenameFile materialName) == textureName do
                (
                    material.diffuseMap = bitmapTexture filename:record[2]
                    showTextureMap material true
                    assigned += 1
                )
            )
        )
    )
    assigned
)
fn MLMaterialImages nodes =
(
    local paths = #()
    for node in nodes where node.material != undefined do
    (
        local materials = if (classof node.material) == MultiMaterial then node.material.materialList else #(node.material)
        for material in materials where material != undefined and isProperty material #diffuseMap do
        (
            local texture = material.diffuseMap
            if texture != undefined and isProperty texture #filename do
            (
                local path = texture.filename
                if path != "" and doesFileExist path and (findItem paths path) == 0 do append paths path
            )
        )
    )
    paths
)

fn MLTextureDictionaryNames path =
(
    local reader = MLReader()
    local names = #()
    try
    (
        reader.openFile path
        if (reader.text 0 4) == "xet" do
        (
            local slot = reader.atLong 0x2C
            local visited = #()
            while slot != 0x28 and slot != 0 do
            (
                if (findItem visited slot) != 0 do throw "Texture dictionary contains a cycle."
                append visited slot
                if visited.count > 4096 do throw "Texture dictionary contains too many entries."
                local base = slot - 8
                reader.check base 0x50
                append names (toLower (reader.text (base + 16) 32))
                slot = reader.atLong (base + 12)
            )
        )
        reader.closeFile()
        names
    )
    catch
    (
        reader.closeFile()
        #()
    )
)

fn MLFindModelTextures modelPath nodes =
(
    local directory = getFilenamePath modelPath
    local stem = toLower (getFilenameFile modelPath)
    local candidates = #()
    join candidates (getFiles (directory + "*.xtx"))
    join candidates (getFiles (directory + "*.chk"))
    local result = #()
    local remaining = #()
    for candidate in candidates do
    (
        if (toLower (getFilenameFile candidate)) == stem then append result candidate
        else append remaining candidate
    )
    local materialNames = #()
    for node in nodes where node.material != undefined do
    (
        local materials = if (classof node.material) == MultiMaterial then node.material.materialList else #(node.material)
        for material in materials where material != undefined do
        (
            local materialName = toLower material.name
            if (findItem materialNames materialName) == 0 do append materialNames materialName
        )
    )
    for candidate in remaining do
    (
        local dictionaryNames = MLTextureDictionaryNames candidate
        local matched = false
        for name in dictionaryNames where (findItem materialNames name) != 0 do matched = true
        if matched do append result candidate
    )
    if result.count == 0 and candidates.count == 1 do append result candidates[1]
    result
)

fn MLImportModelTextures modelPath platform nodes =
(
    local textures = MLFindModelTextures modelPath nodes
    local imported = 0
    local applied = 0
    for dictionary in textures do
    (
        local output = (getFilenamePath modelPath) + (getFilenameFile modelPath) + "_textures\\" + (getFilenameFile dictionary) + "_" + (substring (getFilenameType dictionary) 2 3) + "\\"
        makeDir output all:true
        local records = MLReadTextures dictionary platform output
        imported += records.count
        applied += MLApplyTextures records nodes
    )
    #(imported, applied)
)
