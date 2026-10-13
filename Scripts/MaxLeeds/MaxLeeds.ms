-- MaxLeeds - spicybung
-- GPL-3.0-or-later

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
    label motto "Fast lights, drug life, iffy nights" align:#center
    label creator "by spicybung" align:#center
    label version "MAXScript - 3ds Max 2010+" align:#center
)

MLToolsWindow = newRolloutFloater "MaxLeeds" 248 420 50 75
addRollout MLToolMenu MLToolsWindow rolledup:false
addRollout MLAbout MLToolsWindow rolledup:true
