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

(
    local sourceRoot = getFilenamePath (getSourceFileName())
    local scriptsRoot = (getDir #userScripts) + "\\MaxLeeds"
    local macrosRoot = getDir #userMacros
    local startupRoot = getDir #userStartupScripts

    fn MaxLeedsInstallFolder sourceFolder destinationFolder =
    (
        makeDir destinationFolder all:true
        for sourceFile in (getFiles (sourceFolder + "\\*")) do
        (
            local targetFile = destinationFolder + "\\" + filenameFromPath sourceFile
            if doesFileExist targetFile do deleteFile targetFile
            if not copyFile sourceFile targetFile do throw ("Cannot copy " + sourceFile)
        )
        for sourceDirectory in (getDirectories (sourceFolder + "\\*")) do
        (
            local directoryName = filenameFromPath (trimRight sourceDirectory "\\/")
            MaxLeedsInstallFolder sourceDirectory (destinationFolder + "\\" + directoryName)
        )
    )

    try
    (
        if (maxVersion())[1] < 12000 do throw "MaxLeeds requires 3ds Max 2010 or later."
        MaxLeedsInstallFolder (sourceRoot + "Scripts\\MaxLeeds") scriptsRoot
        makeDir macrosRoot all:true
        makeDir startupRoot all:true
        local macroFile = macrosRoot + "\\MaxLeeds.mcr"
        if doesFileExist macroFile do deleteFile macroFile
        if not copyFile (sourceRoot + "MacroScripts\\MaxLeeds.mcr") macroFile do throw "Cannot install MaxLeeds menu actions."
        local startupFile = startupRoot + "\\MaxLeeds.ms"
        if doesFileExist startupFile do deleteFile startupFile
        if not copyFile (sourceRoot + "Scripts\\Startup\\MaxLeeds.ms") startupFile do throw "Cannot install MaxLeeds startup actions."
        local licenseFile = scriptsRoot + "\\LICENSE"
        if doesFileExist licenseFile do deleteFile licenseFile
        copyFile (sourceRoot + "LICENSE") licenseFile
        for oldName in #("Binary.ms", "Models.ms", "Textures.ms", "Collision.ms", "Ps2.ms", "Manhunt.ms", "Chinatown.ms", "Check.ms", "Interface.ms") do
        (
            local oldFile = scriptsRoot + "\\" + oldName
            if doesFileExist oldFile do deleteFile oldFile
        )
        fileIn macroFile
        macros.run "MaxLeeds" "OpenTools"
    )
    catch
    (
        messageBox (getCurrentException() as string) title:"MaxLeeds installation failed"
    )
)
