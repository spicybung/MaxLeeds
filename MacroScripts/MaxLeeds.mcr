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
