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

global MLRoot, MLVersion, MLRunTool
MLRoot = getFilenamePath (getSourceFileName())
MLVersion = "0.7.4.1"
if (maxVersion())[1] < 12000 do throw "MaxLeeds requires 3ds Max 2010 or later."
for file in #("Binary.ms","Resource.ms","TEX.ms","MHTEX.ms","COL2.ms","VIF.ms","PS2.ms","MDL.ms","DFF.ms","TXD.ms","Manhunt.ms","ManhuntExport.ms","ManhuntTextureReplace.ms","ManhuntTextureEncode.ms","TextureCompression.ms","ManhuntRebuild.ms","ManhuntSkeleton.ms","WBL.ms","Scene.ms","ManhuntWorld.ms","ANIM.ms","IFP.ms","LVZ.ms","WorldExport.ms","Check.ms") do
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
