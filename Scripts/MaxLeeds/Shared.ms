-- MaxLeeds - spicybung
-- GPL-3.0-or-later

global MLRoot, MLVersion, MLRunTool
MLRoot = getFilenamePath (getSourceFileName())
MLVersion = "0.1.3"
if (maxVersion())[1] < 12000 do throw "MaxLeeds requires 3ds Max 2010 or later."
for file in #("Binary.ms","TEX.ms","COL2.ms","PS2.ms","MDL.ms","Manhunt.ms","WBL.ms","Scene.ms","Check.ms") do
(
    local path = MLRoot + "lib\\" + file
    if not doesFileExist path do throw ("MaxLeeds is missing " + file + ". Reinstall the MZP.")
    fileIn path
)
fn MLRunTool filename =
(
    local path = MLRoot + filename
    if not doesFileExist path do throw ("MaxLeeds is missing " + filename + ". Reinstall the MZP.")
    fileIn path
)
