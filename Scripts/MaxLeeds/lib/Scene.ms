-- MaxLeeds - spicybung
-- GPL-3.0-or-later

global MLSelectedFamily, MLApplyTextures, MLMaterialImages
fn MLVisitFamilyNode node result =
(
    if (findItem result node) == 0 do append result node
    for child in node.children do MLVisitFamilyNode child result
)
fn MLSelectedFamily =
(
    if selection.count == 0 do throw "Select a model or its mesh parts."
    local roots = #()
    for node in selection do
    (
        local root = node
        local ancestor = node
        while ancestor != undefined do
        (
            if (getUserProp ancestor "MaxLeedsRoot") == "true" do root = ancestor
            ancestor = ancestor.parent
        )
        if (findItem roots root) == 0 do append roots root
    )
    local result = #()
    for root in roots do MLVisitFamilyNode root result
    result
)
fn MLApplyTextures images nodes =
(
    local assigned = 0
    for node in nodes where node.material != undefined do
    (
        local materials = if (classof node.material) == MultiMaterial then node.material.materialList else #(node.material)
        for material in materials where material != undefined do
        (
            for record in images where (toLower material.name) == (toLower record[1]) do
            (
                material.diffuseMap = bitmapTexture filename:record[2]
                showTextureMap material true
                assigned += 1
            )
        )
    )
    assigned
)
fn MLMaterialImages nodes =
(
    local paths = #()
    for node in nodes where node.material != undefined do
    (
        local materials = if (classof node.material) == MultiMaterial then node.material.materialList else #(node.material)
        for material in materials where material != undefined and isProperty material #diffuseMap do
        (
            local texture = material.diffuseMap
            if texture != undefined and isProperty texture #filename do
            (
                local path = texture.filename
                if path != "" and doesFileExist path and (findItem paths path) == 0 do append paths path
            )
        )
    )
    paths
)
