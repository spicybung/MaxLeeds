-- MaxLeeds - spicybung
-- GPL-3.0-or-later

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
