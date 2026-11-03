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

global MLEffectsWindow, MLEffectsRoot, MLEffectsMarkers, MLEffectsFiltered, MLEffectsCurrent, MLFXRefresh, MLFXPopulate, MLFXChoose
try (closeRolloutFloater MLEffectsWindow) catch ()
MLEffectsRoot = undefined
MLEffectsMarkers = #()
MLEffectsFiltered = #()
MLEffectsCurrent = undefined

fn MLFXSetField marker field value = MLWorldFXProperty marker field value
fn MLFXGetField marker field defaultValue = MLWorldFXValue marker field defaultValue

fn MLFXPopulate =
(
    local marker = MLEffectsCurrent
    if marker == undefined or not (isValidNode marker) do return false
    if (MLFXGetField marker "Type" 0) == 0 do MLWorldFXCaptureLightNode marker
    local position = if MLEffectsRoot != undefined and isValidNode MLEffectsRoot then marker.pos * (inverse MLEffectsRoot.transform) else marker.pos
    MLEffectsCommon.positionX.value = position.x
    MLEffectsCommon.positionY.value = position.y
    MLEffectsCommon.positionZ.value = position.z
    MLEffectsCommon.descriptorType.selection = (MLFXGetField marker "Type" 0) + 1
    MLEffectsCommon.tint.color = if (MLFXGetField marker "Type" 0) == 0 then (MLWorldFXNativeColor marker) else (color (MLFXGetField marker "Red" 255) (MLFXGetField marker "Green" 255) (MLFXGetField marker "Blue" 255))
    local kind = MLFXGetField marker "Type" -1
    MLEffectsLight.applyLight.enabled = kind == 0
    MLEffectsParticle.applyParticle.enabled = kind == 1
    MLEffectsAttractor.applyAttractor.enabled = kind == 2
    MLEffectsPed.applyPed.enabled = kind == 3
    MLEffectsCommon.alpha.value = MLFXGetField marker "Alpha" 255
    MLEffectsCommon.status.text = "Descriptor " + (MLFXGetField marker "Index" 0) as string
    MLEffectsInspect.indexValue.text = "Index: " + (MLFXGetField marker "Index" 0) as string
    MLEffectsInspect.offsetValue.text = "Record offset: " + (MLFXGetField marker "RecordOffset" 0) as string + " (64 bytes)"
    MLEffectsInspect.sourceValue.text = "Original type: " + (MLWorldFXKindName (MLFXGetField marker "OriginalType" 0))
    MLEffectsInspect.rawData.text = MLWorldFXRawReadable marker
    MLEffectsBrowser.previewLights.checked = if (getUserProp marker "MaxLeedsFXLightNode") == "true" and isProperty marker #on then (getProperty marker #on) else false

    MLEffectsLight.distance.value = MLFXGetField marker "LightDistance" 0.0
    MLEffectsLight.outerRange.value = MLFXGetField marker "LightOuterRange" 0.0
    MLEffectsLight.lightSize.value = MLFXGetField marker "LightSize" 0.0
    MLEffectsLight.innerRange.value = MLFXGetField marker "LightInnerRange" 0.0
    MLEffectsLight.flash.value = MLFXGetField marker "LightFlash" 0
    MLEffectsLight.wet.value = MLFXGetField marker "LightWet" 0
    MLEffectsLight.flare.value = MLFXGetField marker "LightFlare" 0
    MLEffectsLight.shadow.value = MLFXGetField marker "LightShadow" 0
    MLEffectsLight.flags.value = MLFXGetField marker "LightFlags" 0
    MLEffectsLight.corona.text = "Corona pointer: " + (MLFXGetField marker "LightCoronaPointer" 0) as string
    MLEffectsLight.shadowTexture.text = "Shadow pointer: " + (MLFXGetField marker "LightShadowPointer" 0) as string

    MLEffectsParticle.particleType.value = MLFXGetField marker "ParticleType" 0
    MLEffectsParticle.strengthX.value = MLFXGetField marker "ParticleX" 0.0
    MLEffectsParticle.strengthY.value = MLFXGetField marker "ParticleY" 0.0
    MLEffectsParticle.strengthZ.value = MLFXGetField marker "ParticleZ" 0.0
    MLEffectsParticle.particleScale.value = MLFXGetField marker "ParticleScale" 1.0

    MLEffectsAttractor.directionX.value = MLFXGetField marker "AttractorX" 0.0
    MLEffectsAttractor.directionY.value = MLFXGetField marker "AttractorY" 0.0
    MLEffectsAttractor.directionZ.value = MLFXGetField marker "AttractorZ" 0.0
    MLEffectsAttractor.subtype.value = MLFXGetField marker "AttractorSubtype" 0
    MLEffectsAttractor.probability.value = MLFXGetField marker "AttractorProbability" 0

    MLEffectsPed.directionX.value = MLFXGetField marker "PedDirectionX" 0.0
    MLEffectsPed.directionY.value = MLFXGetField marker "PedDirectionY" 0.0
    MLEffectsPed.directionZ.value = MLFXGetField marker "PedDirectionZ" 0.0
    MLEffectsPed.rotationX.value = MLFXGetField marker "PedRotationX" 0.0
    MLEffectsPed.rotationY.value = MLFXGetField marker "PedRotationY" 0.0
    MLEffectsPed.rotationZ.value = MLFXGetField marker "PedRotationZ" 0.0
    MLEffectsPed.behaviour.value = MLFXGetField marker "PedBehaviour" 0
    true
)

fn MLFXRefresh =
(
    local root = MLEffectsRoot
    if root == undefined or not (isValidNode root) do root = MLWorldFXRoots()
    if root == undefined or not (isValidNode root) do
    (
        MLEffectsRoot = undefined
        MLEffectsMarkers = #()
        MLEffectsFiltered = #()
        MLEffectsCurrent = undefined
        MLEffectsBrowser.descriptors.items = #()
        MLEffectsBrowser.status.text = "No GAME.DTZ effects loaded"
        return false
    )
    MLEffectsRoot = root
    MLEffectsMarkers = MLWorldFXMarkers MLEffectsRoot
    MLEffectsFiltered = #()
    local descriptions = #()
    local searchText = toLower MLEffectsBrowser.filterText.text
    for marker in MLEffectsMarkers do
    (
        local index = MLFXGetField marker "Index" 0
        local kind = MLFXGetField marker "Type" 0
        local kindName = MLWorldFXKindName kind
        local label = index as string + " - " + kindName
        if searchText == "" or (findString (toLower label) searchText) != undefined do
        (
            append descriptions label
            append MLEffectsFiltered marker
        )
    )
    MLEffectsBrowser.descriptors.items = descriptions
    MLEffectsBrowser.status.text = MLEffectsMarkers.count as string + " descriptors"
    if MLEffectsFiltered.count > 0 then
    (
        local selected = findItem MLEffectsFiltered MLEffectsCurrent
        if selected == 0 do selected = 1
        MLEffectsBrowser.descriptors.selection = selected
        MLEffectsCurrent = MLEffectsFiltered[selected]
        MLFXPopulate()
    )
    else MLEffectsCurrent = undefined
    true
)

rollout MLEffectsBrowser "C2DEffects" width:284
(
    group "GAME.DTZ"
    (
        button importEffects "Load GAME.DTZ / DAT..." width:218 height:27 align:#center
        editText filterText "Find:" text:"" width:250 align:#center
        button findEffects "Find / Refresh" width:125 height:24 align:#center
        button fromSelection "Use selection" width:125 height:24 align:#center
        listBox descriptors "Descriptors:" items:#() height:9 width:250 align:#center
        button selectMarker "Select marker" width:110 height:25 align:#left across:2
        button showMarkers "Show effects" width:110 height:25 align:#right
        checkbox previewLights "Preview selected light" checked:false align:#left
        button previewOff "Turn off all point lights" width:218 height:25 align:#center
    )
    group "Save"
    (
        button saveEffects "Save edited GAME.DTZ / DAT..." width:218 height:30 align:#center
    )
    label status "Load GAME.DTZ or select an imported group" width:250 height:33 align:#center

    on importEffects pressed do
    (
        local path = getOpenFileName caption:"Load GAME.DTZ / DAT effects" types:"GAME images (*.dtz;*.dat)|*.dtz;*.dat|"
        if path != undefined do
        (
            local report = MLReadWorldEffects path
            MLEffectsRoot = MLWorldFXRoots()
            status.text = report[1] as string + " effects; " + report[2]
            if report[1] > 0 then
            (
                filterText.text = ""
                previewLights.checked = false
                MLFXRefresh()
            )
            else messageBox report[2] title:"MaxLeeds C2DEffects"
        )
    )
    on findEffects pressed do MLFXRefresh()
    on fromSelection pressed do
    (
        MLEffectsRoot = MLWorldFXRoots()
        filterText.text = ""
        MLFXRefresh()
        if selection.count > 0 do
        (
            local selectedNode = selection[1]
            local matchIndex = findItem MLEffectsFiltered selectedNode
            if matchIndex > 0 do
            (
                descriptors.selection = matchIndex
                MLEffectsCurrent = selectedNode
                MLFXPopulate()
            )
        )
    )
    on filterText entered text do MLFXRefresh()
    on descriptors selected index do
    (
        if index > 0 and index <= MLEffectsFiltered.count do
        (
            MLEffectsCurrent = MLEffectsFiltered[index]
            MLFXPopulate()
        )
    )
    on selectMarker pressed do
    (
        if MLEffectsCurrent != undefined and isValidNode MLEffectsCurrent do
        (
            if MLEffectsRoot != undefined do unhide MLEffectsRoot
            unhide MLEffectsCurrent
            select MLEffectsCurrent
        )
    )
    on showMarkers pressed do
    (
        if MLEffectsRoot != undefined and isValidNode MLEffectsRoot do
        (
            unhide MLEffectsRoot
            for marker in MLWorldFXMarkers MLEffectsRoot do unhide marker
            status.text = "2D effect helpers are visible"
        )
    )
    on previewLights changed state do
    (
        if MLEffectsCurrent != undefined and isValidNode MLEffectsCurrent and (getUserProp MLEffectsCurrent "MaxLeedsFXLightNode") == "true" then
        (
            MLWorldFXSetNativeProperty MLEffectsCurrent #on state
            MLWorldFXSetNativeProperty MLEffectsCurrent #enabled state
        )
        else previewLights.checked = false
    )
    on previewOff pressed do
    (
        for marker in MLEffectsMarkers where isValidNode marker and (getUserProp marker "MaxLeedsFXLightNode") == "true" do
        (
            MLWorldFXSetNativeProperty marker #on false
            MLWorldFXSetNativeProperty marker #enabled false
        )
        previewLights.checked = false
        status.text = "Point light previews disabled"
    )
    on saveEffects pressed do
    (
        try
        (
            if MLEffectsRoot == undefined or not (isValidNode MLEffectsRoot) do throw "Load a GAME.DTZ effects group first."
            local source = getUserProp MLEffectsRoot "MaxLeedsEffectsSource"
            local filename = (getFilenamePath source) + "GAME_edited.dtz"
            local path = getSaveFileName caption:"Save edited GAME.DTZ / DAT" filename:filename types:"Compressed GAME.DTZ (*.dtz)|*.dtz|Uncompressed GAME.DAT (*.dat)|*.dat|"
            if path != undefined do
            (
                if (getFilenameType path) == "" do path += ".dtz"
                local count = MLSaveWorldEffects MLEffectsRoot path
                status.text = "Saved " + count as string + " descriptors"
            )
        )
        catch
        (
            status.text = "Save failed"
            messageBox (getCurrentException() as string) title:"MaxLeeds C2DEffects"
        )
    )
)

rollout MLEffectsCommon "Position, color and type" width:284
(
    dropdownList descriptorType "Type:" items:#("Light", "Particle", "Attractor", "Ped behaviour") selection:1 width:250 align:#center
    spinner positionX "X:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner positionY "Y:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner positionZ "Z:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    colorPicker tint "Color:" color:(color 255 255 255) fieldwidth:95 align:#center
    spinner alpha "Alpha:" range:[0,255,255] type:#integer fieldwidth:95 align:#center
    button applyCommon "Apply descriptor" width:200 height:27 align:#center
    label status "" width:250 align:#center

    on applyCommon pressed do
    (
        if MLEffectsCurrent != undefined and isValidNode MLEffectsCurrent do undo "MaxLeeds edit 2D effect" on
        (
            local marker = MLWorldFXConvertNode MLEffectsCurrent (descriptorType.selection - 1)
            MLEffectsCurrent = marker
            local localPosition = [positionX.value, positionY.value, positionZ.value]
            marker.pos = if MLEffectsRoot != undefined and isValidNode MLEffectsRoot then localPosition * MLEffectsRoot.transform else localPosition
            MLFXSetField marker "Red" (tint.color.r as integer)
            MLFXSetField marker "Green" (tint.color.g as integer)
            MLFXSetField marker "Blue" (tint.color.b as integer)
            MLFXSetField marker "Alpha" alpha.value
            marker.wirecolor = tint.color
            if (descriptorType.selection - 1) == 0 do MLWorldFXApplyLightNode marker
            status.text = "Descriptor updated"
            MLFXRefresh()
        )
    )
)

rollout MLEffectsLight "Light" width:284
(
    spinner distance "Distance:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner outerRange "Outer range:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner lightSize "Size:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner innerRange "Inner range:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner flash "Flash:" range:[0,255,0] type:#integer fieldwidth:95 align:#center
    spinner wet "Wet:" range:[0,255,0] type:#integer fieldwidth:95 align:#center
    spinner flare "Flare:" range:[0,255,0] type:#integer fieldwidth:95 align:#center
    spinner shadow "Shadow intensity:" range:[0,255,0] type:#integer fieldwidth:95 align:#center
    spinner flags "Flags:" range:[0,255,0] type:#integer fieldwidth:95 align:#center
    label corona "Corona pointer:" width:250 align:#center
    label shadowTexture "Shadow pointer:" width:250 align:#center
    button applyLight "Apply light values" width:195 height:26 align:#center

    on applyLight pressed do
    (
        if MLEffectsCurrent != undefined and isValidNode MLEffectsCurrent and (MLFXGetField MLEffectsCurrent "Type" -1) == 0 do undo "MaxLeeds edit light" on
        (
            local marker = MLEffectsCurrent
            MLFXSetField marker "LightDistance" distance.value
            MLFXSetField marker "LightOuterRange" outerRange.value
            MLFXSetField marker "LightSize" lightSize.value
            MLFXSetField marker "LightInnerRange" innerRange.value
            MLFXSetField marker "LightFlash" flash.value
            MLFXSetField marker "LightWet" wet.value
            MLFXSetField marker "LightFlare" flare.value
            MLFXSetField marker "LightShadow" shadow.value
            MLFXSetField marker "LightFlags" flags.value
            MLWorldFXApplyLightNode marker
            MLEffectsCommon.tint.color = MLWorldFXNativeColor marker
        )
    )
)

rollout MLEffectsParticle "Particle" width:284
(
    spinner particleType "Particle ID:" range:[-100000,100000,0] type:#integer fieldwidth:95 align:#center
    spinner strengthX "Strength X:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner strengthY "Strength Y:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner strengthZ "Strength Z:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner particleScale "Scale:" range:[-1000000,1000000,1] type:#float scale:0.1 fieldwidth:95 align:#center
    button applyParticle "Apply particle values" width:195 height:26 align:#center

    on applyParticle pressed do
    (
        if MLEffectsCurrent != undefined and isValidNode MLEffectsCurrent and (MLFXGetField MLEffectsCurrent "Type" -1) == 1 do undo "MaxLeeds edit particle" on
        (
            local marker = MLEffectsCurrent
            MLFXSetField marker "ParticleType" particleType.value
            MLFXSetField marker "ParticleX" strengthX.value
            MLFXSetField marker "ParticleY" strengthY.value
            MLFXSetField marker "ParticleZ" strengthZ.value
            MLFXSetField marker "ParticleScale" particleScale.value
        )
    )
)

rollout MLEffectsAttractor "Attractor" width:284
(
    spinner directionX "Direction X:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner directionY "Direction Y:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner directionZ "Direction Z:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner subtype "Subtype:" range:[0,255,0] type:#integer fieldwidth:95 align:#center
    spinner probability "Probability:" range:[0,255,0] type:#integer fieldwidth:95 align:#center
    button applyAttractor "Apply attractor values" width:195 height:26 align:#center

    on applyAttractor pressed do
    (
        if MLEffectsCurrent != undefined and isValidNode MLEffectsCurrent and (MLFXGetField MLEffectsCurrent "Type" -1) == 2 do undo "MaxLeeds edit attractor" on
        (
            local marker = MLEffectsCurrent
            MLFXSetField marker "AttractorX" directionX.value
            MLFXSetField marker "AttractorY" directionY.value
            MLFXSetField marker "AttractorZ" directionZ.value
            MLFXSetField marker "AttractorSubtype" subtype.value
            MLFXSetField marker "AttractorProbability" probability.value
        )
    )
)

rollout MLEffectsPed "Pedestrian behaviour" width:284
(
    spinner directionX "Direction X:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner directionY "Direction Y:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner directionZ "Direction Z:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner rotationX "Rotation X:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner rotationY "Rotation Y:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner rotationZ "Rotation Z:" range:[-1000000,1000000,0] type:#float scale:0.1 fieldwidth:95 align:#center
    spinner behaviour "Behaviour:" range:[0,255,0] type:#integer fieldwidth:95 align:#center
    button applyPed "Apply behaviour values" width:195 height:26 align:#center

    on applyPed pressed do
    (
        if MLEffectsCurrent != undefined and isValidNode MLEffectsCurrent and (MLFXGetField MLEffectsCurrent "Type" -1) == 3 do undo "MaxLeeds edit behaviour" on
        (
            local marker = MLEffectsCurrent
            MLFXSetField marker "PedDirectionX" directionX.value
            MLFXSetField marker "PedDirectionY" directionY.value
            MLFXSetField marker "PedDirectionZ" directionZ.value
            MLFXSetField marker "PedRotationX" rotationX.value
            MLFXSetField marker "PedRotationY" rotationY.value
            MLFXSetField marker "PedRotationZ" rotationZ.value
            MLFXSetField marker "PedBehaviour" behaviour.value
        )
    )
)

rollout MLEffectsInspect "Original descriptor" width:284
(
    label indexValue "Index: -" width:250 align:#left
    label offsetValue "Record offset: -" width:250 align:#left
    label sourceValue "Original type: -" width:250 align:#left
    editText rawData "Original 64 bytes:" text:"" width:250 height:95 readOnly:true align:#center
    label note "Unknown bytes are retained when the type is unchanged." width:250 height:32 align:#center
)

MLEffectsWindow = newRolloutFloater "MaxLeeds - C2DEffects" 320 740 370 90
addRollout MLEffectsBrowser MLEffectsWindow rolledup:false
addRollout MLEffectsCommon MLEffectsWindow rolledup:false
addRollout MLEffectsLight MLEffectsWindow rolledup:true
addRollout MLEffectsParticle MLEffectsWindow rolledup:true
addRollout MLEffectsAttractor MLEffectsWindow rolledup:true
addRollout MLEffectsPed MLEffectsWindow rolledup:true
addRollout MLEffectsInspect MLEffectsWindow rolledup:true
MLFXRefresh()
