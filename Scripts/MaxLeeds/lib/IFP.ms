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

global MLReadIfpIndex, MLReadIfpClip, MLCloseAnimationSource, MLWriteManhuntAnimation
fn MLIfpTag reader expected =
(
    local offset = reader.tell()
    local actual = reader.text offset 4
    reader.seek (offset + 4)
    if actual != expected do throw ("Expected " + expected + " at byte " + offset as string + ", found " + actual + ".")
)
fn MLIfpName reader =
(
    local count = reader.long()
    if count < 1 or count > 1048576 do throw "Invalid Manhunt animation name length."
    local offset = reader.tell()
    reader.check offset count
    local name = reader.text offset count
    reader.seek (offset + count)
    name
)
fn MLIfpReadQuaternion reader =
(
    local value = quat (reader.signedShort() / 4096.0) (reader.signedShort() / 4096.0) (reader.signedShort() / 4096.0) (reader.signedShort() / 4096.0)
    local magnitude = value.x * value.x + value.y * value.y + value.z * value.z + value.w * value.w
    if magnitude < 0.000000000001 then quat 0 0 0 1 else MLAnimNormalizeQuat value
)
fn MLIfpTrack reader decode =
(
    local offset = reader.tell()
    local sequence = reader.text offset 4
    reader.seek (offset + 4)
    if sequence != "SEQU" and sequence != "SEQT" do throw "Expected a Manhunt SEQU or SEQT track."
    local id = reader.signedShort()
    local frameType = reader.byte()
    local count = reader.short()
    if frameType < 1 or frameType > 3 do throw "Unsupported Manhunt IFP frame type."
    local startOffset = reader.tell()
    local startTime = reader.short()
    if frameType < 3 and startTime == 0 do reader.seek startOffset
    local initial = quat 0 0 0 1
    if frameType == 3 do
    (
        if decode then initial = MLIfpReadQuaternion reader
        else reader.seek (reader.tell() + 8)
    )
    local track = if decode then MLAnimTrack flags:(if frameType > 1 then 19 else 17) boneID:id boneKey:id else undefined
    local seconds = 0.0
    local elapsed = 0
    local dataSize = (if frameType < 3 then 8 else 0) + (if frameType > 1 then 6 else 0)
    local minimumSize = count * dataSize + (if startTime == 0 then (amax 0 (count - (if frameType == 3 then 1 else 0))) * 2 else 0)
    reader.check (reader.tell()) (minimumSize + (if sequence == "SEQT" then 4 else 0))
    local conversion = rotateXMatrix 90
    if not decode and startTime != 0 then
    (
        reader.seek (reader.tell() + count * dataSize)
        if count > 0 do seconds = startTime / 2048.0 - 1.0 / 30.0 + (count - 1) / 30.0
    )
    else for index = 0 to count - 1 do
    (
        if startTime == 0 then
        (
            if frameType != 3 or index != 0 do elapsed += reader.short()
            seconds = elapsed / 2048.0
        )
        else seconds = startTime / 2048.0 - 1.0 / 30.0 + index / 30.0
        if decode then
        (
            local rotation = initial
            if frameType < 3 do rotation = MLIfpReadQuaternion reader
            local position = if frameType > 1 then [reader.signedShort(),reader.signedShort(),reader.signedShort()] / 2048.0 else [0,0,0]
            rotation = rotationPart (inverse conversion * (rotation as matrix3) * conversion)
            position *= conversion
            append track.keys (MLAnimKey seconds:seconds rotation:rotation position:position)
        )
        else reader.seek (reader.tell() + dataSize)
    )
    local duration = seconds
    if sequence == "SEQT" do duration = amax duration (reader.float())
    #(track,duration,count,sequence)
)
fn MLIfpClip reader blockName decode =
(
    local offset = reader.tell()
    MLIfpTag reader "NAME"
    local name = MLIfpName reader
    local count = reader.long()
    local chunkSize = reader.long()
    local declaredDuration = reader.float()
    if count > 65535 do throw "The Manhunt animation has too many bone tracks."
    local clip = MLAnimClip name:name blockName:blockName sourceOffset:offset trackCount:count sourceKind:"Manhunt" duration:0.0
    local start = reader.tell()
    local structuralBytes = 0
    for index = 1 to count do
    (
        local result = MLIfpTrack reader decode
        local trackGame = if result[4] == "SEQT" then "MH2" else "MH1"
        if clip.game != "" and clip.game != trackGame do throw "An IFP clip mixes MH1 and MH2 track layouts."
        clip.game = trackGame
        if decode do append clip.tracks result[1]
        clip.duration = amax clip.duration result[2]
        clip.keyCount += result[3]
        structuralBytes += 9 + (if result[4] == "SEQT" then 4 else 0)
    )
    local measuredSize = reader.tell() - start - structuralBytes
    if measuredSize != chunkSize do format "MaxLeeds IFP: % declares % payload bytes; decoded %.\n" name chunkSize measuredSize
    clip.particleOffset = reader.tell()
    local particleHeader = reader.long()
    local particleValue = reader.float()
    local particleStride = reader.long()
    local particleCount = reader.long()
    if particleCount > 0 do
    (
        if particleStride < 1 or particleCount > (reader.length - reader.tell()) / particleStride do throw "The Manhunt animation particle block is truncated."
        reader.seek (reader.tell() + particleStride * particleCount)
    )
    clip.sourceEnd = reader.tell()
    clip
)
fn MLReadIfpIndex path =
(
    local decoded = MLDecodeResource path #("ANCT") scanHeader:true
    local reader = MLReader()
    local result = MLAnimFile sourceDigest:(MLFileDigest path) sourcePath:path decodedPath:decoded[1] ownsDecoded:decoded[2] sourceKind:"Manhunt"
    try
    (
        reader.openFile decoded[1]
        MLIfpTag reader "ANCT"
        local blockCount = reader.long()
        if blockCount > 100000 do throw "The Manhunt IFP block count is invalid."
        for block = 1 to blockCount do
        (
            MLIfpTag reader "BLOC"
            local blockName = MLIfpName reader
            MLIfpTag reader "ANPK"
            local count = reader.long()
            if count > 1000000 do throw "The Manhunt IFP animation count is invalid."
            for index = 1 to count do append result.clips (MLIfpClip reader blockName false)
        )
        reader.closeFile()
        result
    )
    catch
    (
        reader.closeFile()
        if decoded[2] and doesFileExist decoded[1] do deleteFile decoded[1]
        throw()
    )
)
fn MLReadIfpClip source index =
(
    if index < 1 or index > source.clips.count do throw "Choose a valid animation clip."
    local reader = MLReader()
    try
    (
        reader.openFile source.decodedPath
        reader.seek source.clips[index].sourceOffset
        local clip = MLIfpClip reader source.clips[index].blockName true
        reader.closeFile()
        clip
    )
    catch (reader.closeFile(); throw())
)
fn MLCloseAnimationSource source =
(
    if source != undefined and source.ownsDecoded and doesFileExist source.decodedPath do deleteFile source.decodedPath
)
fn MLIfpWriteName writer value =
(
    if value.count == 0 or value.count > 1023 do throw "IFP names must contain 1 to 1023 printable ASCII characters."
    for index = 1 to value.count do if (bit.charAsInt value[index]) < 32 or (bit.charAsInt value[index]) > 126 do throw "IFP names must use printable ASCII."
    writer.long (value.count + 1)
    writer.text value
)
fn MLIfpQuantize value scale =
(
    if value != value or (abs value) > 1.0e20 do throw "An IFP key contains a non-finite value."
    local packed = MLAnimRoundEven (value * scale)
    if packed < -32768 or packed > 32767 do throw "An IFP transform exceeds its signed 16-bit range."
    packed
)
fn MLWriteManhuntAnimation destination clip blockName game =
(
    local writer = MLWriter()
    local temporary = MLTemporaryFile destination
    try
    (
        writer.openFile temporary
        writer.long 0x54434E41
        writer.long 1
        writer.long 0x434F4C42
        MLIfpWriteName writer blockName
        writer.long 0x4B504E41
        writer.long 1
        writer.long 0x454D414E
        MLIfpWriteName writer clip.name
        writer.long clip.tracks.count
        local chunkSizeOffset = writer.tell()
        writer.long 0
        writer.float clip.duration
        local start = writer.tell()
        local structuralBytes = 0
        local conversion = rotateXMatrix 90
        for track in clip.tracks do
        (
            if track.boneID < -32768 or track.boneID > 32767 do throw "An IFP bone ID exceeds the signed 16-bit range."
            if track.keys.count < 1 or track.keys.count > 65535 do throw "An IFP track must contain 1 to 65535 keys."
            local translate = (bit.and track.flags 2) != 0
            if (bit.and track.flags 4) != 0 do for key in track.keys do if (distance key.scaling [1,1,1]) > 0.001 do throw "Manhunt IFP does not support animated bone scale."
            writer.long (if game == "MH1" then 0x55514553 else 0x54514553)
            writer.signedShort track.boneID
            writer.byte (if translate then 2 else 1)
            writer.short track.keys.count
            local firstTicks = MLAnimRoundEven (track.keys[1].seconds * 2048.0)
            if firstTicks != 0 do throw "Exported IFP tracks must start at time zero."
            local previousTicks = 0
            local previousRotation = undefined
            for key in track.keys do
            (
                local ticks = MLAnimRoundEven (key.seconds * 2048.0)
                local delta = ticks - previousTicks
                if delta < 0 or delta > 65535 do throw "IFP key intervals must be ordered and no longer than 65535/2048 seconds."
                writer.short delta
                local rotation = MLAnimNormalizeQuat (rotationPart (conversion * (key.rotation as matrix3) * inverse conversion))
                if previousRotation != undefined and (rotation.x * previousRotation.x + rotation.y * previousRotation.y + rotation.z * previousRotation.z + rotation.w * previousRotation.w) < 0 do rotation = quat (-rotation.x) (-rotation.y) (-rotation.z) (-rotation.w)
                for value in #(rotation.x,rotation.y,rotation.z,rotation.w) do writer.signedShort (MLIfpQuantize value 4096.0)
                if translate do
                (
                    local position = key.position * inverse conversion
                    for axis = 1 to 3 do writer.signedShort (MLIfpQuantize position[axis] 2048.0)
                )
                previousTicks = ticks
                previousRotation = rotation
            )
            if game != "MH1" do writer.float (previousTicks / 2048.0)
            structuralBytes += 9 + (if game == "MH1" then 0 else 4)
        )
        writer.patchLong chunkSizeOffset (writer.tell() - start - structuralBytes)
        writer.long 16
        writer.float (if game == "MH1" then 2.0 else 3.0)
        writer.long (if game == "MH1" then 64 else 160)
        writer.long 0
        writer.closeFile()
        local checked = MLReadIfpIndex temporary
        if checked.clips.count != 1 or checked.clips[1].trackCount != clip.tracks.count do throw "The exported IFP failed structural validation."
        MLCloseAnimationSource checked
        MLFinishFile temporary destination
        clip.tracks.count
    )
    catch
    (
        writer.closeFile()
        if doesFileExist temporary do deleteFile temporary
        throw()
    )
)


fn MLReplaceManhuntAnimation destination source index clip =
(
    if source == undefined or source.sourceKind != "Manhunt" or index < 1 or index > source.clips.count do throw "Choose a loaded Manhunt IFP clip."
    if not doesFileExist source.sourcePath or source.sourceDigest != (MLFileDigest source.sourcePath) do throw "The source IFP changed. Reopen it before replacing a clip."
    local original = source.clips[index]
    if original.game == "" do throw "The original clip has no bone tracks to identify its game."
    local reader = MLReader()
    local encodedReader = MLReader()
    local writer = MLWriter()
    local temporary = MLTemporaryFile destination
    local encoded = MLTemporaryFile destination
    local packed = MLTemporaryFile destination
    local replacementIndex = undefined
    local checked = undefined
    try
    (
        reader.openFile source.sourcePath
        local wrapper = reader.text 0 4
        reader.closeFile()
        if wrapper != "ANCT" and wrapper != "Z2HM" do throw "Clip replacement currently supports raw ANCT or Z2HM containers."
        clip.name = original.name
        MLWriteManhuntAnimation encoded clip original.blockName original.game
        replacementIndex = MLReadIfpIndex encoded
        local replacement = replacementIndex.clips[1]
        reader.openFile source.decodedPath
        encodedReader.openFile encoded
        writer.openFile temporary
        MLMhCopyBytes reader 0 writer 0 original.sourceOffset
        MLMhCopyBytes encodedReader replacement.sourceOffset writer (writer.tell()) (replacement.particleOffset - replacement.sourceOffset)
        MLMhCopyBytes reader original.particleOffset writer (writer.tell()) (reader.length - original.particleOffset)
        writer.closeFile(); reader.closeFile(); encodedReader.closeFile()
        MLCloseAnimationSource replacementIndex; replacementIndex = undefined
        checked = MLReadIfpIndex temporary
        if checked.clips.count != source.clips.count or checked.clips[index].trackCount != clip.tracks.count do throw "The edited IFP failed structural validation."
        for clipIndex = 1 to checked.clips.count do
            if checked.clips[clipIndex].name != source.clips[clipIndex].name or checked.clips[clipIndex].blockName != source.clips[clipIndex].blockName do throw "IFP clip order changed during replacement."
        MLCloseAnimationSource checked; checked = undefined
        if wrapper == "Z2HM" then
        (
            MLMhWriteCompressed temporary packed
            checked = MLReadIfpIndex packed
            if (MLFileDigest checked.decodedPath) != (MLFileDigest temporary) do throw "Compressed IFP verification failed."
            MLCloseAnimationSource checked; checked = undefined
            MLFinishFile packed destination
        )
        else MLFinishFile temporary destination
        if doesFileExist temporary do deleteFile temporary
        deleteFile encoded
        clip.tracks.count
    )
    catch
    (
        reader.closeFile(); encodedReader.closeFile(); writer.closeFile()
        MLCloseAnimationSource replacementIndex
        MLCloseAnimationSource checked
        for path in #(temporary,encoded,packed) where doesFileExist path do deleteFile path
        throw()
    )
)
