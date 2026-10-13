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

macroScript OpenTools
category:"MaxLeeds"
tooltip:"MaxLeeds tools"
buttonText:"MaxLeeds"
(
    on execute do
    (
        local path = (getDir #userScripts) + "\\MaxLeeds\\MaxLeeds.ms"
        if doesFileExist path then fileIn path
        else messageBox "Reinstall MaxLeeds by dropping the MZP into a viewport." title:"MaxLeeds"
    )
)
macroScript MDLIO
category:"MaxLeeds"
tooltip:"MDL IO"
buttonText:"MDL IO"
(
    on execute do
    (
        local path = (getDir #userScripts) + "\\MaxLeeds\\MDL IO.ms"
        if doesFileExist path then fileIn path
        else messageBox "Reinstall MaxLeeds to restore MDL IO.ms." title:"MaxLeeds"
    )
)
macroScript COL2IO
category:"MaxLeeds"
tooltip:"COL2 IO"
buttonText:"COL2 IO"
(
    on execute do
    (
        local path = (getDir #userScripts) + "\\MaxLeeds\\COL2 IO.ms"
        if doesFileExist path then fileIn path
        else messageBox "Reinstall MaxLeeds to restore COL2 IO.ms." title:"MaxLeeds"
    )
)
macroScript TEXIO
category:"MaxLeeds"
tooltip:"TEX IO"
buttonText:"TEX IO"
(
    on execute do
    (
        local path = (getDir #userScripts) + "\\MaxLeeds\\TEX IO.ms"
        if doesFileExist path then fileIn path
        else messageBox "Reinstall MaxLeeds to restore TEX IO.ms." title:"MaxLeeds"
    )
)
macroScript WBLIO
category:"MaxLeeds"
tooltip:"WBL IO"
buttonText:"WBL IO"
(
    on execute do
    (
        local path = (getDir #userScripts) + "\\MaxLeeds\\WBL IO.ms"
        if doesFileExist path then fileIn path
        else messageBox "Reinstall MaxLeeds to restore WBL IO.ms." title:"MaxLeeds"
    )
)
