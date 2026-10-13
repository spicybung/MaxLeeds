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

global MLCOL2Window
try (closeRolloutFloater MLCOL2Window) catch ()
try (destroyDialog MLCOL2Tools) catch ()

rollout MLCOL2Import "Import COL2" width:214
(
    group "Collision"
    (
        button importCollision "Import COL2" width:136 height:29 align:#center
        label status "Ready" width:188 height:28 align:#center
    )
    on importCollision pressed do
    (
        local path = getOpenFileName caption:"Import COL2" types:"Collision (*.col2)|*.col2|"
        if path != undefined do
        (
            try
            (
                local count = 0
                undo "MaxLeeds COL2 import" on (count = MLReadCollision path)
                status.text = "Imported " + count as string + " objects"
            )
            catch
            (
                status.text = "Import failed"
                messageBox (getCurrentException()) title:"COL2 IO"
            )
        )
    )
)

rollout MLCOL2Export "Export COL2" width:214
(
    group "Selected objects"
    (
        button exportCollision "Export COL2" width:136 height:29 align:#center
        label status "Select collision meshes" width:188 height:28 align:#center
    )
    on exportCollision pressed do
    (
        try
        (
            if selection.count == 0 do throw "Select collision meshes to export."
            local path = getSaveFileName caption:"Export COL2" types:"Collision (*.col2)|*.col2|"
            if path != undefined do
            (
                if (getFilenameType path) == "" do path += ".col2"
                local count = MLWriteCollision path (selection as array)
                status.text = "Exported " + count as string + " objects"
            )
        )
        catch
        (
            status.text = "Export failed"
            messageBox (getCurrentException()) title:"COL2 IO"
        )
    )
)

rollout MLCOL2About "About" width:214
(
    label heading "MaxLeeds - COL2 IO" align:#center
    label credit "spicybung" align:#center
)

MLCOL2Window = newRolloutFloater "COL2 IO" 248 320 320 90
addRollout MLCOL2Import MLCOL2Window rolledup:false
addRollout MLCOL2Export MLCOL2Window rolledup:false
addRollout MLCOL2About MLCOL2Window rolledup:true
