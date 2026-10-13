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

global MLMDLWindow
try (closeRolloutFloater MLMDLWindow) catch ()
try (destroyDialog MLMDLTools) catch ()

rollout MLMDLImport "Import MDL" width:214
(
    group "Source"
    (
        dropdownList game "Game:" items:#("Liberty City Stories", "Vice City Stories", "Manhunt 2") selection:2 width:188 align:#center
        dropdownList platform "Platform:" items:#("PS2", "PSP") selection:1 width:188 align:#center
    )
    group "Import"
    (
        button importModel "Import MDL" width:136 height:29 align:#center
    )
    label status "Ready" width:188 height:27 align:#center

    fn selectedGame = #("LCS", "VCS", "MH2")[game.selection]
    fn selectedPlatform = #("PS2", "PSP")[platform.selection]

    on game selected index do
    (
        platform.enabled = (index != 3)
        if index == 3 then status.text = "Manhunt 2 - PC" else status.text = "Ready"
    )

    on importModel pressed do
    (
        local path = getOpenFileName caption:"Import MDL" types:"Models (*.mdl)|*.mdl|"
        if path != undefined do
        (
            try
            (
                local count = 0
                undo "MaxLeeds MDL import" on
                (
                    with redraw off
                    (
                        local model = if game.selection == 3 then MLReadManhunt path else MLReadModel path (selectedGame()) (selectedPlatform())
                        count = MLBuildModel model
                        if game.selection != 3 do
                        (
                            local importedNodes = MLSelectedFamily()
                            try
                            (
                                local textureCounts = MLImportModelTextures path (selectedPlatform()) importedNodes
                                if textureCounts[2] > 0 do status.text = "Applied " + textureCounts[2] as string + " textures"
                            )
                            catch
                            (
                                format "MaxLeeds: accompanying textures could not be loaded: %\n" (getCurrentException())
                                status.text = "Model loaded; textures unavailable"
                            )
                        )
                        if model.modelID >= 0 and model.modelID <= 65534 do MLMDLExport.modelID.value = model.modelID
                    )
                )
                redrawViews()
                if status.text == "Ready" do status.text = "Imported " + count as string + " objects"
            )
            catch
            (
                status.text = "Import failed"
                messageBox (getCurrentException()) title:"MDL IO"
            )
        )
    )
)

rollout MLMDLExport "Export MDL" width:214
(
    group "Destination"
    (
        dropdownList game "Game:" items:#("Liberty City Stories", "Vice City Stories") selection:2 width:188 align:#center
        dropdownList platform "Platform:" items:#("PS2", "PSP") selection:2 width:188 align:#center
    )
    group "Model ID"
    (
        checkbox useImportedID "Use imported model ID" checked:true align:#left
        spinner modelID "ID:" range:[0,65534,0] type:#integer fieldwidth:65 enabled:false align:#center
    )
    group "Export"
    (
        button exportModel "Export MDL" width:136 height:29 align:#center
    )
    label status "Select a model to export" width:188 height:29 align:#center

    fn selectedGame = #("LCS", "VCS")[game.selection]

    fn updateOptions =
    (
        modelID.enabled = not useImportedID.checked
        exportModel.enabled = platform.selection == 2
        if platform.selection == 1 then status.text = "PS2 export is not available" else status.text = "Select a model to export"
    )

    on MLMDLExport open do updateOptions()
    on platform selected index do updateOptions()
    on useImportedID changed value do updateOptions()

    on exportModel pressed do
    (
        try
        (
            local nodes = MLSelectedFamily()
            local id = if useImportedID.checked then -1 else modelID.value
            if useImportedID.checked do
            (
                for node in nodes where (getUserProp node "MaxLeedsRoot") == "true" do
                (
                    local importedID = getUserProp node "MaxLeedsModelID"
                    if importedID != undefined do id = importedID as integer
                )
                if id < 0 or id > 65534 do throw "This model has no imported ID. Turn off Use imported model ID and enter its game ID."
            )
            local path = getSaveFileName caption:"Export MDL" types:"Models (*.mdl)|*.mdl|"
            if path != undefined do
            (
                if (getFilenameType path) == "" do path += ".mdl"
                local count = MLWritePspObject path nodes (selectedGame()) id
                status.text = "Exported " + count as string + " triangles"
            )
        )
        catch
        (
            status.text = "Export failed"
            messageBox (getCurrentException()) title:"MDL IO"
        )
    )
)

rollout MLMDLAbout "About" width:214
(
    label heading "MaxLeeds - MDL IO" align:#center
    label games "Liberty City Stories / Vice City Stories" align:#center
    label source "PS2 / PSP model tools" align:#center
    label credit "spicybung" align:#center
)

MLMDLWindow = newRolloutFloater "MDL IO" 248 575 320 90
addRollout MLMDLImport MLMDLWindow rolledup:false
addRollout MLMDLExport MLMDLWindow rolledup:false
addRollout MLMDLAbout MLMDLWindow rolledup:true
