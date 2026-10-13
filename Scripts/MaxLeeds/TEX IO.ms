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

fileIn ((getFilenamePath (getSourceFileName())) + "Shared.ms")

global MLTEXWindow, MLTEXImagePaths, MLTEXExportReady
try (closeRolloutFloater MLTEXWindow) catch ()
try (destroyDialog MLTEXTools) catch ()
MLTEXImagePaths = #()
MLTEXExportReady = false

fn MLUIAddTexture path =
(
    if not doesFileExist path do throw ("Image not found: " + path)
    local stem = toLower (getFilenameFile path)
    for existing in MLTEXImagePaths do
    (
        if (toLower existing) == (toLower path) do return false
        if (toLower (getFilenameFile existing)) == stem do throw ("Two images have the same texture name: " + stem)
    )
    append MLTEXImagePaths path
    true
)

fn MLUIRefreshTextures =
(
    local displayNames = #()
    for imagePath in MLTEXImagePaths do append displayNames (filenameFromPath imagePath)
    if MLTEXExportReady == true do
    (
        MLTEXExport.images.items = displayNames
        MLTEXExport.exportTextures.enabled = MLTEXImagePaths.count > 0
        MLTEXExport.removeImage.enabled = MLTEXImagePaths.count > 0
        MLTEXExport.clearImages.enabled = MLTEXImagePaths.count > 0
    )
)

rollout MLTEXImport "Import TEX" width:214
(
    group "Source"
    (
        dropdownList platform "Platform:" items:#("PS2", "PSP") selection:1 width:188 align:#center
    )
    group "Import"
    (
        button importTextures "Import XTX / CHK" width:136 height:29 align:#center
    )
    label status "Ready" width:188 height:29 align:#center

    fn selectedPlatform = #("PS2", "PSP")[platform.selection]

    on importTextures pressed do
    (
        local path = getOpenFileName caption:"Import XTX / CHK" types:"Stories textures (*.xtx;*.chk)|*.xtx;*.chk|"
        if path != undefined do
        (
            local folder = getSavePath caption:"Choose a folder for decoded textures" initialDir:(getFilenamePath path)
            if folder != undefined do
            (
                try
                (
                    local records = MLReadTextures path (selectedPlatform()) folder
                    local nodes = #()
                    if selection.count > 0 do nodes = MLSelectedFamily()
                    local assigned = MLApplyTextures records nodes
                    for record in records do MLUIAddTexture record[2]
                    MLUIRefreshTextures()
                    status.text = "Imported " + records.count as string + " textures"
                    if assigned > 0 do status.text = status.text + ("; assigned " + assigned as string)
                )
                catch
                (
                    MLUIRefreshTextures()
                    status.text = "Import failed"
                    messageBox (getCurrentException()) title:"TEX IO"
                )
            )
        )
    )
)

rollout MLTEXExport "Export TEX" width:214
(
    group "Images"
    (
        listBox images "" items:#() height:7 width:188 align:#center
        button addImage "Add bitmap" width:136 height:25 align:#center
        button removeImage "Remove" width:65 height:24 align:#left across:2
        button clearImages "Clear" width:65 height:24 align:#right
        button selectedImages "From selected materials" width:160 height:25 align:#center
    )
    group "Options"
    (
        dropdownList platform "Platform:" items:#("PS2", "PSP") selection:1 width:188 align:#center
        dropdownList colors "Colors:" items:#("16 colors (4-bit)", "256 colors (8-bit)") selection:2 width:188 align:#center
        dropdownList containerType "File:" items:#("XTX", "CHK") selection:1 width:188 align:#center
    )
    group "Export"
    (
        button exportTextures "Export XTX / CHK" width:136 height:29 align:#center
    )
    label status "No images selected" width:188 height:29 align:#center

    fn selectedPlatform = #("PS2", "PSP")[platform.selection]

    on MLTEXExport close do MLTEXExportReady = false
    on images selected index do
    (
        if index > 0 and index <= MLTEXImagePaths.count do status.text = filenameFromPath MLTEXImagePaths[index]
    )
    on addImage pressed do
    (
        local path = getOpenFileName caption:"Add bitmap" types:"Images (*.tga;*.png;*.bmp;*.dds;*.jpg)|*.tga;*.png;*.bmp;*.dds;*.jpg|"
        if path != undefined do
        (
            try
            (
                MLUIAddTexture path
                MLUIRefreshTextures()
                status.text = MLTEXImagePaths.count as string + " images"
            )
            catch
            (
                status.text = "Could not add image"
                messageBox (getCurrentException()) title:"TEX IO"
            )
        )
    )
    on removeImage pressed do
    (
        local index = images.selection
        if index > 0 and index <= MLTEXImagePaths.count do
        (
            deleteItem MLTEXImagePaths index
            MLUIRefreshTextures()
            status.text = MLTEXImagePaths.count as string + " images"
        )
    )
    on clearImages pressed do
    (
        MLTEXImagePaths = #()
        MLUIRefreshTextures()
        status.text = "Image list cleared"
    )
    on selectedImages pressed do
    (
        try
        (
            local paths = MLMaterialImages (MLSelectedFamily())
            if paths.count == 0 do throw "The selected model has no bitmap textures in its diffuse materials."
            local added = 0
            for path in paths do if MLUIAddTexture path do added += 1
            MLUIRefreshTextures()
            status.text = "Added " + added as string + " images"
        )
        catch
        (
            MLUIRefreshTextures()
            status.text = "Could not add materials"
            messageBox (getCurrentException()) title:"TEX IO"
        )
    )
    on exportTextures pressed do
    (
        try
        (
            if MLTEXImagePaths.count == 0 do throw "Add bitmap images or use From selected materials."
            local extension = if containerType.selection == 1 then ".xtx" else ".chk"
            local types = if containerType.selection == 1 then "XTX (*.xtx)|*.xtx|" else "CHK (*.chk)|*.chk|"
            local path = getSaveFileName caption:"Export textures" filename:("textures" + extension) types:types
            if path != undefined do
            (
                if (getFilenameType path) == "" do path += extension
                if (toLower (getFilenameType path)) != extension do throw ("Choose a filename ending in " + extension)
                local count = MLWriteTextures path MLTEXImagePaths (selectedPlatform()) (if colors.selection == 1 then 4 else 8)
                status.text = "Exported " + count as string + " textures"
            )
        )
        catch
        (
            status.text = "Export failed"
            messageBox (getCurrentException()) title:"TEX IO"
        )
    )
)

rollout MLTEXAbout "About" width:214
(
    label heading "MaxLeeds - TEX IO" align:#center
    label games "Liberty City Stories / Vice City Stories" align:#center
    label source "PS2 / PSP textures" align:#center
    label credit "spicybung" align:#center
)

MLTEXWindow = newRolloutFloater "TEX IO" 248 640 320 90
addRollout MLTEXImport MLTEXWindow rolledup:false
addRollout MLTEXExport MLTEXWindow rolledup:false
MLTEXExportReady = true
MLUIRefreshTextures()
addRollout MLTEXAbout MLTEXWindow rolledup:true
