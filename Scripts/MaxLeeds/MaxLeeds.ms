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

global MLToolsWindow
try (closeRolloutFloater MLToolsWindow) catch ()
try (destroyDialog MLTools) catch ()

rollout MLToolMenu "Leeds tools" width:214
(
    group "Models and textures"
    (
        button mdlTools "MDL IO" width:136 height:28 align:#center
        button texTools "TEX IO" width:136 height:28 align:#center
    )
    group "Collision and world"
    (
        button colTools "COL2 IO" width:136 height:28 align:#center
        button wblTools "WBL IO" width:136 height:28 align:#center
    )
    on mdlTools pressed do MLRunTool "MDL IO.ms"
    on texTools pressed do MLRunTool "TEX IO.ms"
    on colTools pressed do MLRunTool "COL2 IO.ms"
    on wblTools pressed do MLRunTool "WBL IO.ms"
)

rollout MLAbout "About" width:214
(
    label title "MaxLeeds" align:#center
    label creator "by spicybung" align:#center
    label version "MAXScript - 3ds Max 2010+" align:#center
)

MLToolsWindow = newRolloutFloater "MaxLeeds" 248 420 50 75
addRollout MLToolMenu MLToolsWindow rolledup:false
addRollout MLAbout MLToolsWindow rolledup:true
