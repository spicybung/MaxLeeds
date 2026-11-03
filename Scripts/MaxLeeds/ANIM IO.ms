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
global MLAnimationWindow
try (closeRolloutFloater MLAnimationWindow) catch ()
rollout MLAnimationTools "Animations" width:310
(
    local source = undefined
    local clipIndices = #()
    button openFile "Open ANIM / Manhunt IFP..." width:275 height:30
    editText filterText "Find:" text:"" width:280
    dropdownList clips "Animation:" items:#() width:280
    label detail "No file loaded" width:280 height:38
    spinner startFrame "Start frame:" range:[-1000000,1000000,0] type:#float
    checkbox rootMotion "Apply root motion" checked:true
    checkbox replaceKeys "Replace keyed channels" checked:false
    button importClip "Apply clip to selected model" width:275 height:32
    button saveContainer "Save loaded ANIM clips..." width:275 height:27 enabled:false
    group "Export selected skeleton"
    (
        dropdownList formatType "Format:" items:#("Stories ANIM","Manhunt 2 IFP","Manhunt 1 IFP") selection:1 width:280
        editText clipName "Name:" text:"animation" width:280
        editText blockName "IFP block:" text:"MaxLeeds" width:280 enabled:false
        spinner firstFrame "First frame:" range:[-1000000,1000000,0] type:#float
        spinner lastFrame "Last frame:" range:[-1000000,1000000,100] type:#float
        spinner stepFrames "Sample every N frames:" range:[0.01,1000,1] type:#float
        button replaceSourceClip "Replace loaded IFP clip from scene..." width:275 height:30
        button exportClip "Export scene animation..." width:275 height:30
    )
    label status "Select a model root or a mesh belonging to it." width:280 height:45
    fn updateClip =
    (
        if source != undefined and clips.selection > 0 and clips.selection <= clipIndices.count do
        (
            local clip = source.clips[clipIndices[clips.selection]]
            local count = if source.sourceKind == "Manhunt" then clip.trackCount else clip.tracks.count
            detail.text = count as string + " tracks / " + clip.duration as string + " seconds"
        )
    )
    fn filterClips =
    (
        clipIndices = #()
        local names = #()
        if source != undefined do for index = 1 to source.clips.count do
        (
            local clip = source.clips[index]
            local name = if clip.blockName != "" then clip.blockName + " / " + clip.name else clip.name
            if filterText.text == "" or (findString (toLower name) (toLower filterText.text)) != undefined do
            (
                append clipIndices index
                append names name
            )
        )
        clips.items = names
        if names.count > 0 then (clips.selection = 1; updateClip()) else detail.text = "No matching clips"
    )
    on openFile pressed do
    (
        local path = getOpenFileName caption:"Open animation" types:"Animations (*.anim;*.ifp)|*.anim;*.ifp|All files|*.*|"
        if path != undefined do try
        (
            local reader = MLReader()
            local magic = ""
            try (reader.openFile path; magic = reader.text 0 4; reader.closeFile()) catch (reader.closeFile(); throw())
            local parsed = if magic == "mina" then MLReadAnimations path else MLReadIfpIndex path
            MLCloseAnimationSource source
            source = parsed
            filterText.text = ""
            filterClips()
            saveContainer.enabled = source.sourceKind == "ANIM"
            status.text = "Loaded " + source.clips.count as string + " clips"
        ) catch (messageBox (getCurrentException()) title:"MaxLeeds Animations")
    )
    on filterText changed text do filterClips()
    on clips selected index do updateClip()
    on formatType selected index do blockName.enabled = index > 1
    on importClip pressed do try
    (
        if source == undefined or clips.selection < 1 or clips.selection > clipIndices.count do throw "Choose an animation clip first."
        local clipIndex = clipIndices[clips.selection]
        local clip = if source.sourceKind == "Manhunt" then MLReadIfpClip source clipIndex else source.clips[clipIndex]
        local report
        undo "MaxLeeds animation import" on
        (
            with redraw off report = MLApplyAnimation clip (MLSelectedFamily()) startFrame.value replaceKeys.checked rootMotion.checked
        )
        status.text = report[1] as string + " tracks / " + report[2] as string + " keys; " + report[3] as string + " unmatched tracks"
        redrawViews()
    ) catch (messageBox (getCurrentException()) title:"MaxLeeds Animations")
    on saveContainer pressed do try
    (
        if source == undefined or source.sourceKind != "ANIM" do throw "Open a Stories ANIM file first."
        local path = getSaveFileName caption:"Save animation container" types:"Stories ANIM (*.anim)|*.anim|"
        if path != undefined do
        (
            if (getFilenameType path) == "" do path += ".anim"
            MLWriteAnimations path source
            status.text = "Saved all loaded clips"
        )
    ) catch (messageBox (getCurrentException()) title:"MaxLeeds Animations")
    on replaceSourceClip pressed do try
    (
        if source == undefined or source.sourceKind != "Manhunt" or clips.selection < 1 or clips.selection > clipIndices.count do throw "Open a Manhunt IFP and choose the clip to replace."
        local index = clipIndices[clips.selection]
        local sampled = MLSampleAnimation (MLSelectedFamily()) source.clips[index].name firstFrame.value lastFrame.value stepFrames.value
        local path = getSaveFileName caption:"Save IFP with replaced bone animation" types:"Manhunt IFP (*.ifp)|*.ifp|"
        if path != undefined do
        (
            if (getFilenameType path) == "" do path += ".ifp"
            local count = MLReplaceManhuntAnimation path source index sampled.clips[1]
            status.text = "Replaced " + count as string + " tracks; retained other clips and particles"
        )
    ) catch (messageBox (getCurrentException()) title:"Manhunt animation replacement")

    on exportClip pressed do try
    (
        local sampled = MLSampleAnimation (MLSelectedFamily()) clipName.text firstFrame.value lastFrame.value stepFrames.value
        if source != undefined and source.sourceKind == "ANIM" do sampled.header = copy source.header
        local extension = if formatType.selection == 1 then ".anim" else ".ifp"
        local types = if formatType.selection == 1 then "Stories ANIM (*.anim)|*.anim|" else "Manhunt IFP (*.ifp)|*.ifp|"
        local path = getSaveFileName caption:"Export scene animation" types:types
        if path != undefined do
        (
            if (getFilenameType path) == "" do path += extension
            if formatType.selection == 1 then MLWriteAnimations path sampled
            else MLWriteManhuntAnimation path sampled.clips[1] blockName.text (if formatType.selection == 2 then "MH2" else "MH1")
            status.text = "Exported " + sampled.clips[1].tracks.count as string + " bone tracks"
        )
    ) catch (messageBox (getCurrentException()) title:"MaxLeeds Animations")
    on MLAnimationTools close do MLCloseAnimationSource source
)
MLAnimationWindow = newRolloutFloater "MaxLeeds - Animations" 340 750 360 100
addRollout MLAnimationTools MLAnimationWindow
