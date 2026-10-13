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

global MLWBLWindow
try (closeRolloutFloater MLWBLWindow) catch ()
try (destroyDialog MLWBLTools) catch ()

rollout MLWBLImport "Import WBL" width:214
(
    group "Chinatown Wars"
    (
        button importWorld "Import WBL" width:136 height:29 align:#center
        label status "World geometry and lights" width:188 height:28 align:#center
    )
    on importWorld pressed do
    (
        local path = getOpenFileName caption:"Import WBL" types:"Worldblocks (*.wbl)|*.wbl|"
        if path != undefined do
        (
            try
            (
                local count = 0
                undo "MaxLeeds WBL import" on (with redraw off (count = MLReadWorldblock path))
                redrawViews()
                status.text = "Imported " + count as string + " objects"
            )
            catch
            (
                status.text = "Import failed"
                messageBox (getCurrentException()) title:"WBL IO"
            )
        )
    )
)

rollout MLWBLAbout "About" width:214
(
    label heading "MaxLeeds - WBL IO" align:#center
    label credit "spicybung" align:#center
)

MLWBLWindow = newRolloutFloater "WBL IO" 248 238 320 90
addRollout MLWBLImport MLWBLWindow rolledup:false
addRollout MLWBLAbout MLWBLWindow rolledup:true
