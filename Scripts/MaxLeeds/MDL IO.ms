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

rollout MLMDLImport "Model import" width:284
(
    group "Source game"
    (
        dropdownList game "Game:" items:#("Liberty City Stories", "Vice City Stories", "Manhunt 2") selection:1 width:250 align:#center
        dropdownList platform "Platform:" items:#("PlayStation 2", "PSP", "Mobile (DFF)") selection:1 width:250 align:#center
    )
    group "Import settings"
    (
        checkbox loadTextures "Load matching textures" checked:true align:#left
        checkbox showBones "Show skeleton after import" checked:true align:#left
        button importModel "Import model..." width:225 height:32 align:#center
    )
    label status "Ready" width:250 height:35 align:#center

    fn selectedGame = #("LCS", "VCS", "MH2")[game.selection]
    fn selectedPlatform = #("PS2", "PSP", "Mobile")[platform.selection]

    on game selected index do
    (
        platform.enabled = (index != 3)
        if index != 1 and platform.selection == 3 do platform.selection = 1
        if index == 3 then status.text = "Manhunt 2 PC / PS2 / PSP models" else status.text = "Ready"
    )

    on platform selected index do
    (
        if index == 3 do game.selection = 1
        status.text = if index == 3 then "LCS Mobile DFF import" else "Ready"
    )

    on importModel pressed do
    (
        local mobile = game.selection == 1 and platform.selection == 3
        local path = if mobile then getOpenFileName caption:"Import LCS Mobile DFF" types:"Mobile models (*.dff)|*.dff|" else getOpenFileName caption:"Import MDL / PMLC" types:"Models (*.mdl;*.pmlc)|*.mdl;*.pmlc|"
        if path != undefined do
        (
            status.text = "Ready"
            try
            (
                local count = 0
                undo "MaxLeeds MDL import" on
                (
                    with redraw off
                    (
                        local models = if mobile then MLReadMobileDff path else if game.selection == 3 then MLReadManhuntModels path else #(MLReadModel path (selectedGame()) (selectedPlatform()))
                        local created = #()
                        local roots = #()
                        local assigned = 0
                        try
                        (
                            for model in models do
                            (
                                MLMergeModelParts model
                                count += MLBuildModel model
                                local importedNodes = MLSelectedFamily()
                                join created importedNodes
                                for node in importedNodes where (MLUserFlag node "MaxLeedsRoot") do append roots node
                                if not showBones.checked do MLSetBonesVisible importedNodes false
                                if loadTextures.checked do
                                (
                                    try
                                    (
                                        local textureCounts = if mobile then MLImportMobileImages path importedNodes else if game.selection == 3 then MLImportManhuntTextures path model.platform importedNodes else MLImportModelTextures path model.platform importedNodes
                                        assigned += textureCounts[2]
                                    )
                                    catch (format "MaxLeeds: model imported; accompanying textures failed: %\n" (getCurrentException()))
                                )
                                if model.modelID >= 0 and model.modelID <= 65534 do MLMDLExport.modelID.value = model.modelID
                            )
                            select roots
                            status.text = models.count as string + " models / " + count as string + " nodes; " + assigned as string + " textures"
                        )
                        catch
                        (
                            for node in created where isValidNode node do delete node
                            throw()
                        )
                        if status.text == "Ready" do status.text = "Imported " + count as string + " nodes"
                    )
                )
                redrawViews()
            )
            catch
            (
                status.text = "Import failed"
                messageBox (getCurrentException()) title:"MDL IO"
            )
        )
    )
)

rollout MLMDLExport "Model export" width:284
(
    group "Destination game"
    (
        dropdownList game "Game:" items:#("Liberty City Stories", "Vice City Stories") selection:1 width:250 align:#center
        dropdownList platform "Platform:" items:#("PlayStation 2", "PSP") selection:2 width:250 align:#center
    )
    group "Model ID"
    (
        checkbox useImportedID "Use imported model ID" checked:true align:#left
        spinner modelID "ID:" range:[0,65534,0] type:#integer fieldwidth:85 enabled:false align:#center
    )
    group "Export"
    (
        button exportModel "Export selected model..." width:225 height:32 align:#center
    )
    label status "Objects, weapons and skinned characters" width:250 height:30 align:#center

    fn selectedGame = #("LCS", "VCS")[game.selection]

    fn updateOptions =
    (
        modelID.enabled = not useImportedID.checked
        exportModel.enabled = true
        status.text = "Objects, weapons and skinned characters"
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
                for node in nodes where (MLUserFlag node "MaxLeedsRoot") do
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
                local count = if platform.selection == 1 then MLWritePs2Object path nodes (selectedGame()) id else MLWritePspObject path nodes (selectedGame()) id
                local parts = 0
                for node in nodes where (superclassof node) == GeometryClass and (classof node) != BoneGeometry do parts += 1
                status.text = "Exported " + count as string + " triangles / " + parts as string + " parts"
            )
        )
        catch
        (
            status.text = "Export failed"
            messageBox (getCurrentException()) title:"MDL IO"
        )
    )
)

rollout MLMDLManhuntEdits "Manhunt 2 PC edits" width:284
(
    group "Manhunt 2 PC edits"
    (
        button exportMh "Export positions / UVs..." width:225 height:30 align:#center
        label mhHelp "Requires the original vertex and face topology." width:250 height:28 align:#center
        checkbox rebuildSkeleton "Rebuild skeleton from current bind pose" checked:false align:#left tooltip:"Required when adding Skin to a previously rigid PC mesh. Use the current bind pose."
        checkbox rebuildMaterials "Rebuild material slots from scene" checked:false align:#left
        button rebuildMh "Rebuild edited PC meshes..." width:225 height:30 align:#center
        label rebuildHelp "Topology, UVs, normals, colours and weights." width:250 height:28 align:#center
        label mhScope "Both write mesh-local edits and retain source bones and material slots." width:250 height:38 align:#center
    )
    label status "" width:250 height:30 align:#center
    on rebuildMh pressed do try
    (
        local path = getSaveFileName caption:"Rebuild Manhunt PC meshes" types:"Models (*.mdl)|*.mdl|"
        if path != undefined do
        (
            if (getFilenameType path) == "" do path += ".mdl"
            local report = MLWriteManhuntPcRebuild path (MLSelectedFamily()) rebuildMaterials:rebuildMaterials.checked rebuildSkeleton:rebuildSkeleton.checked
            status.text = "Rebuilt " + report[1] as string + " meshes / " + report[3] as string + " faces"
        )
    ) catch (messageBox (getCurrentException()) title:"MaxLeeds Manhunt rebuild")

    on exportMh pressed do try
    (
        local path = getSaveFileName caption:"Export Manhunt PC position / UV edits" types:"Models (*.mdl)|*.mdl|"
        if path != undefined do
        (
            if (getFilenameType path) == "" do path += ".mdl"
            local report = MLWriteManhuntPcEdits path (MLSelectedFamily())
            status.text = "Exported " + report[1] as string + " meshes / " + report[2] as string + " vertices"
        )
    ) catch (messageBox (getCurrentException()) title:"MaxLeeds Manhunt export")

)

rollout MLMDLBones "Skeleton / skin" width:284
(
    label heading "Select a model or one of its parts" width:250 align:#center
    group "Bone visibility"
    (
        button showSkeleton "Show bones" width:118 height:26 align:#left across:2
        button hideSkeleton "Hide bones" width:118 height:26 align:#right
    )
    group "Skin weights"
    (
        button inspectWeights "Inspect skin" width:118 height:26 align:#left across:2
        button reduceWeights "Limit to 4 influences" width:118 height:26 align:#right
    )
    label result "" width:250 height:43 align:#center

    on showSkeleton pressed do
    (
        try (result.text = "Visible bones: " + (MLSetBonesVisible (MLSelectedFamily()) true) as string) catch (messageBox (getCurrentException()) title:"MaxLeeds")
    )
    on hideSkeleton pressed do
    (
        try (result.text = "Hidden bones: " + (MLSetBonesVisible (MLSelectedFamily()) false) as string) catch (messageBox (getCurrentException()) title:"MaxLeeds")
    )
    on inspectWeights pressed do
    (
        try
        (
            local report = MLAuditSkin (MLSelectedFamily())
            result.text = report[1] as string + " skin meshes / " + report[2] as string + " vertices\n" + report[3] as string + " unweighted; " + report[4] as string + " >4 influences; " + report[5] as string + " not normalized"
        )
        catch (messageBox (getCurrentException()) title:"MaxLeeds")
    )
    on reduceWeights pressed do
    (
        try
        (
            local changed = 0
            undo "MaxLeeds limit skin weights" on (changed = MLLimitSkinWeights (MLSelectedFamily()))
            result.text = "Normalized / reduced " + changed as string + " vertices"
        )
        catch (messageBox (getCurrentException()) title:"MaxLeeds")
    )
)

rollout MLMDLAbout "About" width:284
(
    label heading "MaxLeeds - MDL IO" align:#center
    label games "LCS / VCS / Manhunt 2" align:#center
    label source "PS2 / PSP MDL | Mobile DFF | MH2 PMLC" align:#center
    label credit "spicybung" align:#center
)

MLMDLWindow = newRolloutFloater "MaxLeeds - Models" 316 760 320 90
addRollout MLMDLImport MLMDLWindow rolledup:false
addRollout MLMDLExport MLMDLWindow rolledup:false
addRollout MLMDLBones MLMDLWindow rolledup:true
addRollout MLMDLManhuntEdits MLMDLWindow rolledup:true
addRollout MLMDLAbout MLMDLWindow rolledup:true
