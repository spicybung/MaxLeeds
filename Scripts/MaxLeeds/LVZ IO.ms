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

global MLLVZWindow
try (closeRolloutFloater MLLVZWindow) catch ()

rollout MLLVZImport "World import" width:284
(
    group "Source"
    (
        dropdownList game "Game:" items:#("Automatic", "Liberty City Stories", "Vice City Stories") selection:1 width:250 align:#center
        checkbox textures "Load world textures" checked:true align:#left
        checkbox effects "Read GAME.DTZ 2D effects, if available" checked:true align:#left
        spinner maxInstances "Maximum placements (0 = all):" range:[0,250000,0] type:#integer fieldwidth:75 align:#center
    )
    group "Import"
    (
        button openWorld "Import LVZ + IMG..." width:220 height:34 align:#center
        button exportPlacements "Export placement edits to IMG..." width:220 height:30 align:#center
        button editEffects "C2DEffects..." width:220 height:27 align:#center
    )
    group "Manhunt 2 world"
    (
        button openMhWorld "Import PS2 / PSP BSP..." width:220 height:30 align:#center
    )
    label status "Ready" width:250 height:42 align:#center

    fn selectedGame = #("Auto", "LCS", "VCS")[game.selection]

    on exportPlacements pressed do
    (
        local destination = getSaveFileName caption:"Export world placement transforms" types:"IMG archives (*.img)|*.img|"
        if destination != undefined do try
        (
            if (getFilenameType destination) == "" do destination += ".img"
            local count = MLWriteWorldPlacements destination (MLSelectedFamily())
            status.text = "Exported " + count as string + " placement transforms"
        ) catch (messageBox (getCurrentException()) title:"World placement export")
    )

    on editEffects pressed do MLRunTool "2D Effects IO.ms"

    on openMhWorld pressed do
    (
        local path = getOpenFileName caption:"Import Manhunt 2 world" types:"Manhunt worlds (*.bsp)|*.bsp|All files|*.*|"
        if path != undefined do try
        (
            local model = MLReadManhuntWorld path
            local count = 0
            undo "MaxLeeds Manhunt world import" on
            (
                with redraw off count = MLBuildModel model
            )
            local assigned = 0
            if textures.checked do try
            (
                local report = MLImportManhuntTextures path model.platform (MLSelectedFamily())
                assigned = report[2]
            ) catch (format "MaxLeeds: world imported; accompanying textures failed: %\n" (getCurrentException()))
            status.text = count as string + " nodes / " + model.platform + "; " + assigned as string + " textures"
            redrawViews()
        ) catch (messageBox (getCurrentException()) title:"Manhunt world import")
    )

    on openWorld pressed do
    (
        local path = getOpenFileName caption:"Import Stories LVZ" types:"World archives (*.lvz)|*.lvz|"
        if path != undefined do
        (
            local imagePath = MLWorldFindImageFile path
            if imagePath == undefined do imagePath = getOpenFileName caption:"Choose the companion IMG" initialDir:(getFilenamePath path) types:"IMG archives (*.img)|*.img|"
            if imagePath != undefined do
            (
                try
                (
                    local report = #()
                    undo "MaxLeeds LVZ import" on
                    (
                        with redraw off
                        (
                            report = MLReadWorld path imagePath (selectedGame()) maxInstances.value textures.checked
                        )
                    )
                    status.text = report[1] as string + " models / " + report[4] as string + " sectors\n" + report[5] as string + " textured; " + report[2] as string + " unsupported"
                    if effects.checked do
                    (
                        local dtzPath = MLWorldFindDtz path
                        if dtzPath != undefined do try
                        (
                            local effectReport = MLReadWorldEffects dtzPath
                            format "MaxLeeds GAME.DTZ: % effects; %\n" effectReport[1] effectReport[2]
                            if effectReport[1] > 0 do status.text += "\n" + effectReport[1] as string + " unbound 2D effects"
                        )
                        catch
                        (
                            format "MaxLeeds: the LVZ / IMG world loaded, but GAME.DTZ effects failed: %\n" (getCurrentException())
                            status.text += "\nGAME.DTZ effects could not be read"
                        )
                    )
                    redrawViews()
                )
                catch
                (
                    status.text = "World import failed"
                    messageBox (getCurrentException() as string) title:"LVZ / IMG"
                )
            )
        )
    )
)

rollout MLLVZAbout "About" width:284
(
    label heading "MaxLeeds - World IO" align:#center
    label source "Stories PS2 + PSP LVZ / Manhunt BSP" align:#center
    label note "2D effects are local until model binding is known" align:#center
)

MLLVZWindow = newRolloutFloater "MaxLeeds - World" 316 540 340 95
addRollout MLLVZImport MLLVZWindow rolledup:false
addRollout MLLVZAbout MLLVZWindow rolledup:true
