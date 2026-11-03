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

global MLAnimKey, MLAnimTrack, MLAnimClip, MLAnimFile
struct MLAnimKey (seconds = 0.0, rotation = (quat 0 0 0 1), position = [0,0,0], scaling = [1,1,1])
struct MLAnimTrack (flags = 17, boneKey = 0, boneID = -1, keys = #())
struct MLAnimClip (blockName = "", sourceOffset = 0, sourceEnd = 0, particleOffset = 0, game = "", trackCount = 0, keyCount = 0, sourceKind = "ANIM", name = "animation", duration = 0.0, unknown = 0, tracks = #())
struct MLAnimFile (sourceDigest = "", decodedPath = "", ownsDecoded = false, sourceKind = "ANIM", header = #(), clips = #(), sourcePath = "")

global MLAnimHalf, MLAnimPackHalf, MLReadAnimations, MLWriteAnimations, MLApplyAnimation, MLSampleAnimation
fn MLAnimHalf packed =
(
    local sign = if (bit.and packed 0x8000) == 0 then 1.0 else -1.0
    local exponent = MLBits packed 10 5
    local fraction = bit.and packed 1023
    if exponent == 31 do throw "ANIM contains a non-finite half float."
    if exponent == 0 then sign * fraction * (2.0 ^ -24)
    else sign * (1.0 + fraction / 1024.0) * (2.0 ^ (exponent - 15))
)
fn MLAnimRoundEven value =
(
    local lower = floor value
    local fraction = value - lower
    if fraction > 0.5 or (fraction == 0.5 and (mod lower 2) != 0) do lower += 1
    lower as integer
)
fn MLAnimPackHalf value =
(
    if value != value or (abs value) > 65504.0 do throw "ANIM value exceeds the finite half-float range."
    local sign = if value < 0 then 0x8000 else 0
    local magnitude = abs value
    if magnitude < (2.0 ^ -14) do return (bit.or sign (MLAnimRoundEven (magnitude * (2.0 ^ 24))))
    local exponent = 0
    local normalized = magnitude
    while normalized >= 2.0 do (normalized /= 2.0; exponent += 1)
    while normalized < 1.0 do (normalized *= 2.0; exponent -= 1)
    local fraction = MLAnimRoundEven ((normalized - 1.0) * 1024.0)
    if fraction == 1024 do (fraction = 0; exponent += 1)
    bit.or sign (bit.or (bit.shift (exponent + 15) 10) fraction)
)
fn MLAnimBoneID flags boneKey =
(
    local low = bit.and boneKey 65535
    local hash = MLBits boneKey 16 16
    if (bit.and flags 16) != 0 or ((bit.and flags 8) != 0 and hash != 0 and low <= 255) do return low
    local hashes = #(0xDF9E,0xB88A,0x9A64,0xBCFC,0xE97B,0x6E99,0x8935,0x1157,0x7A50,0xFE09,0xC8F4,0x5E16,0xB052,0x2830,0x1E52,0xC7D5,0xA1C5,0x3A14,0xCDD3,0xCCEC,0x2938,0xFA32,0xF530,0x10E4)
    local ids = #(0,1,2,3,4,5,21,22,23,24,25,25,31,32,33,34,35,35,41,42,43,51,52,53)
    local index = findItem hashes hash
    if index > 0 then ids[index] else -1
)
fn MLAnimReadVector reader = [MLAnimHalf (reader.short()), MLAnimHalf (reader.short()), MLAnimHalf (reader.short())]
fn MLReadAnimations path =
(
    local reader = MLReader()
    local result = MLAnimFile sourcePath:path
    try
    (
        reader.openFile path
        reader.check 0 32
        if (reader.text 0 4) != "mina" do throw "Choose a Leeds ANIM file."
        reader.seek 0
        for index = 1 to 32 do append result.header (reader.byte())
        local logicalEnd = reader.atLong 8
        if logicalEnd >= 32 and logicalEnd <= reader.length do reader.length = logicalEnd
        local reloc = reader.atLong 12
        local frameEnd = if reloc >= 32 and reloc <= reader.length then reloc else reader.length
        local cursor = 32
        local tableEnd = frameEnd
        local offsets = #()
        while cursor + 4 <= tableEnd do
        (
            local offset = reader.atLong cursor
            if offset == 0 do exit
            if offset < 32 or offset + 36 > frameEnd do exit
            if (findItem offsets offset) != 0 do throw "ANIM has duplicate clip pointers."
            local table = reader.atLong offset
            if table < 32 or table >= frameEnd do exit
            local name = reader.text (offset + 4) 24
            if name.count == 0 do exit
            local printable = true
            for charIndex = 1 to name.count do if (bit.charAsInt name[charIndex]) < 32 or (bit.charAsInt name[charIndex]) > 126 do printable = false
            if not printable do exit
            append offsets offset
            tableEnd = amin tableEnd offset
            cursor += 4
        )
        if offsets.count == 0 do throw "ANIM has no valid animation clips."
        for offset in offsets do
        (
            local table = reader.atLong offset
            local clip = MLAnimClip name:(reader.text (offset + 4) 24)
            local count = reader.atShort (offset + 28)
            clip.unknown = reader.atShort (offset + 30)
            clip.duration = reader.atFloat (offset + 32)
            if clip.duration < 0 do throw "ANIM has a negative duration."
            if table + count * 12 > frameEnd do throw "ANIM bone table overlaps relocation data."
            reader.check table (count * 12)
            for index = 0 to count - 1 do
            (
                local item = table + index * 12
                local track = MLAnimTrack flags:(reader.atShort item) boneKey:(reader.atLong (item + 8))
                if (bit.and track.flags (bit.not 31)) != 0 do throw "ANIM has unsupported track flags."
                track.boneID = MLAnimBoneID track.flags track.boneKey
                local keyCount = reader.atShort (item + 2)
                local frames = reader.atLong (item + 4)
                local stride = 2
                if (bit.and track.flags 1) != 0 do stride += 8
                if (bit.and track.flags 2) != 0 do stride += 6
                if (bit.and track.flags 4) != 0 do stride += 6
                if keyCount > 0 do
                (
                    if frames < 32 or frames + keyCount * stride > frameEnd do throw "ANIM keyframe data is truncated."
                    reader.seek frames
                    local seconds = 0.0
                    for keyIndex = 1 to keyCount do
                    (
                        local key = MLAnimKey()
                        if (bit.and track.flags 1) != 0 do key.rotation = quat (MLAnimHalf (reader.short())) (MLAnimHalf (reader.short())) (MLAnimHalf (reader.short())) (MLAnimHalf (reader.short()))
                        local delta = MLAnimHalf (reader.short())
                        if delta < 0 do throw "ANIM has a negative key time."
                        seconds += delta
                        key.seconds = seconds
                        if (bit.and track.flags 2) != 0 do key.position = MLAnimReadVector reader
                        if (bit.and track.flags 4) != 0 do key.scaling = MLAnimReadVector reader
                        append track.keys key
                    )
                    clip.duration = amax clip.duration seconds
                )
                append clip.tracks track
            )
            append result.clips clip
        )
        reader.closeFile()
        result
    )
    catch (reader.closeFile(); throw())
)
fn MLWriteAnimations destination source =
(
    if source.clips.count == 0 do throw "There are no animation clips to export."
    local writer = MLWriter()
    local temporary = MLTemporaryFile destination
    try
    (
        writer.openFile temporary
        if source.header.count == 32 then for value in source.header do writer.byte value
        else (writer.long 0x616E696D; writer.zeros 28)
        writer.zeros ((source.clips.count + 1) * 4)
        for clipIndex = 1 to source.clips.count do
        (
            local clip = source.clips[clipIndex]
            if clip.name.count < 1 or clip.name.count > 24 do throw "Animation names must contain 1 to 24 ASCII characters."
            for charIndex = 1 to clip.name.count do if (bit.charAsInt clip.name[charIndex]) < 32 or (bit.charAsInt clip.name[charIndex]) > 126 do throw "Animation names must use printable ASCII."
            if clip.tracks.count > 65535 do throw "Too many ANIM bone tracks."
            writer.align 4
            local entry = writer.tell()
            writer.pointer (32 + (clipIndex - 1) * 4) entry
            writer.zeros 36
            writer.seek (entry + 4)
            for charIndex = 1 to clip.name.count do writer.byte (bit.charAsInt clip.name[charIndex])
            writer.seek (entry + 28)
            writer.short clip.tracks.count
            writer.short clip.unknown
            writer.float clip.duration
            local table = writer.tell()
            writer.pointer entry table
            writer.zeros (clip.tracks.count * 12)
            local duration = clip.duration
            if duration < 0 or duration != duration do throw "Invalid animation duration."
            for trackIndex = 1 to clip.tracks.count do
            (
                local track = clip.tracks[trackIndex]
                if track.keys.count > 65535 do throw "Too many keyframes in an ANIM track."
                if (bit.and track.flags (bit.not 31)) != 0 do throw "Unsupported animation track flags."
                local item = table + (trackIndex - 1) * 12
                local endOffset = writer.tell()
                writer.seek item
                writer.short track.flags
                writer.short track.keys.count
                writer.long 0
                writer.long track.boneKey
                writer.seek endOffset
                if track.keys.count > 0 do
                (
                    writer.align 4
                    writer.pointer (item + 4) (writer.tell())
                    local previous = 0.0
                    local encoded = 0.0
                    for key in track.keys do
                    (
                        if key.seconds < previous do throw "Animation key times are not ordered."
                        if (bit.and track.flags 1) != 0 do for component in #(key.rotation.x,key.rotation.y,key.rotation.z,key.rotation.w) do writer.short (MLAnimPackHalf component)
                        local packedTime = MLAnimPackHalf (key.seconds - previous)
                        writer.short packedTime
                        encoded += MLAnimHalf packedTime
                        if (bit.and track.flags 2) != 0 do for axis = 1 to 3 do writer.short (MLAnimPackHalf key.position[axis])
                        if (bit.and track.flags 4) != 0 do for axis = 1 to 3 do writer.short (MLAnimPackHalf key.scaling[axis])
                        previous = key.seconds
                    )
                    duration = amax duration encoded
                )
            )
            local endOffset = writer.tell()
            writer.seek (entry + 32)
            writer.float duration
            writer.seek endOffset
        )
        writer.align 4
        local reloc = writer.tell()
        for offset in writer.relocations do writer.long offset
        writer.patchLong 8 (writer.tell())
        writer.patchLong 12 reloc
        writer.patchLong 16 reloc
        writer.patchLong 20 writer.relocations.count
        writer.closeFile()
        local checked = MLReadAnimations temporary
        if checked.clips.count != source.clips.count do throw "Animation output validation failed."
        for index = 1 to source.clips.count do
        (
            if checked.clips[index].tracks.count != source.clips[index].tracks.count do throw "Animation track validation failed."
            for trackIndex = 1 to source.clips[index].tracks.count do
                if checked.clips[index].tracks[trackIndex].keys.count != source.clips[index].tracks[trackIndex].keys.count do throw "Animation key validation failed."
        )
        MLFinishFile temporary destination
        source.clips.count
    )
    catch
    (
        writer.closeFile()
        if doesFileExist temporary do deleteFile temporary
        throw()
    )
)
fn MLAnimNormalizeQuat value =
(
    local magnitude = sqrt (value.x * value.x + value.y * value.y + value.z * value.z + value.w * value.w)
    if magnitude < 0.000001 do throw "Animation contains a zero-length quaternion."
    quat (value.x / magnitude) (value.y / magnitude) (value.z / magnitude) (value.w / magnitude)
)
fn MLAnimTargets nodes =
(
    local result = #()
    local ids = #()
    local roots = 0
    for node in nodes where isValidNode node do
    (
        if (MLUserFlag node "MaxLeedsRoot") do roots += 1
        local value = getUserProp node "MaxLeedsBoneID"
        if value != undefined and (value as integer) >= 0 do
        (
            local id = value as integer
            if (findItem ids id) != 0 do throw ("Duplicate animation bone ID " + id as string + ". Select one skeleton.")
            append ids id
            append result #(id,node)
        )
    )
    if roots > 1 do throw "Select one model skeleton for animation."
    if result.count == 0 do throw "Select a MaxLeeds model with bone IDs."
    result
)
fn MLApplyAnimation clip nodes startFrame replaceKeys rootMotion =
(
    local targets = MLAnimTargets nodes
    local mapped = #()
    local used = #()
    local missing = #()
    for track in clip.tracks where track.keys.count > 0 do
    (
        local target = undefined
        for pair in targets where track.boneID >= 0 and pair[1] == track.boneID do target = pair[2]
        if target == undefined then append missing track.boneID
        else
        (
            if (findItem used target) != 0 do throw "Two animation tracks resolve to the same bone."
            if (bit.and track.flags 1) != 0 do for key in track.keys do MLAnimNormalizeQuat key.rotation
            append used target
            local channels = #()
            if (bit.and track.flags 1) != 0 do append channels target.rotation.controller
            if (bit.and track.flags 2) != 0 and (rootMotion or (track.boneID != 0 and (clip.sourceKind != "Manhunt" or (track.boneID != 1000 and track.boneID != 8889)))) do append channels target.position.controller
            if (bit.and track.flags 4) != 0 do append channels target.scale.controller
            if not replaceKeys do for controller in channels do
                if (numKeys controller) != 0 do throw "A target channel already has keys or a procedural controller. Enable Replace keyed channels to replace it."
            append mapped #(track,target,copy target.transform.controller)
        )
    )
    if mapped.count == 0 do throw "None of this clip's bone IDs match the selected skeleton."
    local keyCount = 0
    local earliest = 0.0
    local latest = clip.duration
    for item in mapped do for key in item[1].keys do
    (
        earliest = amin earliest key.seconds
        latest = amax latest key.seconds
    )
    try
    (
        with animate off for item in mapped do
        (
            local track = item[1]
            local node = item[2]
            if (bit.and track.flags 1) != 0 do node.rotation.controller = Linear_Rotation()
            if (bit.and track.flags 2) != 0 and (rootMotion or (track.boneID != 0 and (clip.sourceKind != "Manhunt" or (track.boneID != 1000 and track.boneID != 8889)))) do node.position.controller = Linear_Position()
            if (bit.and track.flags 4) != 0 do node.scale.controller = Linear_Scale()
        )
        with animate on for item in mapped do
        (
            local track = item[1]
            local node = item[2]
            for key in track.keys do
            (
                local timeValue = (startFrame + key.seconds * frameRate) * 1f
                at time timeValue
                (
                    if (bit.and track.flags 1) != 0 do node.rotation.controller.value = (MLAnimNormalizeQuat key.rotation)
                    if (bit.and track.flags 2) != 0 and (rootMotion or (track.boneID != 0 and (clip.sourceKind != "Manhunt" or (track.boneID != 1000 and track.boneID != 8889)))) do node.position.controller.value = key.position
                    if (bit.and track.flags 4) != 0 do node.scale.controller.value = key.scaling
                )
                keyCount += 1
            )
        )
    )
    catch
    (
        for item in mapped do item[2].transform.controller = item[3]
        throw()
    )
    local lastTime = (startFrame + latest * frameRate) * 1f
    animationRange = interval (amin animationRange.start ((startFrame + earliest * frameRate) * 1f)) (amax animationRange.end lastTime)
    format "MaxLeeds ANIM %: % tracks, % keys, % unmatched tracks (IDs: %)\n" clip.name mapped.count keyCount missing.count missing
    #(mapped.count,keyCount,missing.count)
)
fn MLSampleAnimation nodes clipName firstFrame lastFrame stepFrames =
(
    if lastFrame < firstFrame or stepFrames <= 0 do throw "The animation frame range is invalid."
    local targets = MLAnimTargets nodes
    local sampleCount = (ceil ((lastFrame - firstFrame) / stepFrames)) as integer
    if sampleCount + 1 > 65535 do throw "The animation range exceeds 65535 samples per bone."
    local clip = MLAnimClip name:clipName duration:((lastFrame - firstFrame) / frameRate)
    for pair in targets do
    (
        if pair[1] > 65535 do throw "Bone ID exceeds the ANIM direct-ID range."
        local track = MLAnimTrack flags:23 boneKey:pair[1] boneID:pair[1]
        local previous = undefined
        for index = 0 to sampleCount do
        (
            local frame = amin lastFrame (firstFrame + index * stepFrames)
            at time (frame * 1f)
            (
                local node = pair[2]
                local transform = node.transform
                if node.parent != undefined do transform *= inverse node.parent.transform
                local rotation = MLAnimNormalizeQuat (rotationPart transform)
                if previous != undefined and (rotation.x * previous.x + rotation.y * previous.y + rotation.z * previous.z + rotation.w * previous.w) < 0 do rotation = quat (-rotation.x) (-rotation.y) (-rotation.z) (-rotation.w)
                append track.keys (MLAnimKey seconds:((frame - firstFrame) / frameRate) rotation:rotation position:transform.row4 scaling:(scalePart transform))
                previous = rotation
            )
        )
        append clip.tracks track
    )
    MLAnimFile clips:#(clip)
)
