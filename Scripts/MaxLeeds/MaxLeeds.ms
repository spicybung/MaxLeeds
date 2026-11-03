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

rollout MLToolMenu "File formats" width:284
(
    group "Stories / Manhunt 2"
    (
        button mdlTools "Models (MDL)" width:232 height:32 align:#center
        button animTools "Animations (ANIM / IFP)" width:232 height:32 align:#center
        button texTools "Textures (CHK / XTX / TEX)" width:232 height:32 align:#center
        button worldTools "World (LVZ / IMG / BSP)" width:232 height:32 align:#center
        button effectsTools "2D Effects (GAME.DTZ)" width:232 height:32 align:#center
    )
    group "Other formats"
    (
        button colTools "Collision (COL2)" width:232 height:30 align:#center
        button wblTools "Chinatown Wars world (WBL)" width:232 height:30 align:#center
    )
    on mdlTools pressed do MLRunTool "MDL IO.ms"
    on animTools pressed do MLRunTool "ANIM IO.ms"
    on texTools pressed do MLRunTool "TEX IO.ms"
    on worldTools pressed do MLRunTool "LVZ IO.ms"
    on effectsTools pressed do MLRunTool "2D Effects IO.ms"
    on colTools pressed do MLRunTool "COL2 IO.ms"
    on wblTools pressed do MLRunTool "WBL IO.ms"
)

rollout MLAbout "About" width:284
(
    label title "MaxLeeds" align:#center
    label creator "by spicybung" align:#center
    label version ("Version " + MLVersion + "  |  3ds Max 2010+") align:#center
    button checkTools "Run built-in checks" width:232 height:28 align:#center
    on checkTools pressed do
    (
        try (messageBox (MLCheckTools()) title:"MaxLeeds checks")
        catch (messageBox (getCurrentException()) title:"MaxLeeds check failed")
    )
)

MLToolsWindow = newRolloutFloater "MaxLeeds" 316 505 50 75
addRollout MLToolMenu MLToolsWindow rolledup:false
addRollout MLAbout MLToolsWindow rolledup:true
