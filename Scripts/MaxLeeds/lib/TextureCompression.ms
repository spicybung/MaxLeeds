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

global MLMhMipChain, MLMhWriteDxt
fn MLMhMipChain width height pixels enabled =
(
    local levels = #(#(width,height,pixels))
    while enabled and (width > 1 or height > 1) do
    (
        local nextWidth = amax 1 ((width / 2) as integer)
        local nextHeight = amax 1 ((height / 2) as integer)
        local nextPixels = #()
        for y = 0 to nextHeight - 1 do for x = 0 to nextWidth - 1 do
        (
            local left = x * width as float / nextWidth
            local right = (x + 1) * width as float / nextWidth
            local top = y * height as float / nextHeight
            local bottom = (y + 1) * height as float / nextHeight
            local rgb = [0,0,0]
            local alpha = 0.0
            local area = 0.0
            for sourceY = (floor top) as integer to ((ceil bottom) as integer) - 1 do
                for sourceX = (floor left) as integer to ((ceil right) as integer) - 1 do
                (
                    local weight = (amin right (sourceX + 1) - amax left sourceX) * (amin bottom (sourceY + 1) - amax top sourceY)
                    local value = pixels[sourceX + sourceY * width + 1]
                    local opacity = value.a * weight
                    rgb += [value.r,value.g,value.b] * opacity
                    alpha += opacity
                    area += weight
                )
            if alpha > 0 then rgb /= alpha else rgb = [0,0,0]
            append nextPixels (color rgb.x rgb.y rgb.z (alpha / area))
        )
        width = nextWidth; height = nextHeight; pixels = nextPixels
        append levels #(width,height,pixels)
    )
    levels
)
fn MLMhPack565 value =
(
    local red = (floor (value.r * 31.0 / 255.0 + 0.5)) as integer
    local green = (floor (value.g * 63.0 / 255.0 + 0.5)) as integer
    local blue = (floor (value.b * 31.0 / 255.0 + 0.5)) as integer
    (bit.shift red 11) + (bit.shift green 5) + blue
)
fn MLMhUnpack565 value =
(
    local red = MLBits value 11 5
    local green = MLBits value 5 6
    local blue = MLBits value 0 5
    color ((bit.shift red 3) + (bit.shift red -2)) ((bit.shift green 2) + (bit.shift green -4)) ((bit.shift blue 3) + (bit.shift blue -2))
)
fn MLMhDxtColour writer pixels cutout =
(
    local minimum = color 255 255 255
    local maximum = color 0 0 0
    local transparent = false
    local opaque = 0
    for value in pixels do
    (
        if cutout and value.a < 128 then transparent = true
        else
        (
            opaque += 1
            for component = 1 to 3 do
            (
                minimum[component] = amin minimum[component] value[component]
                maximum[component] = amax maximum[component] value[component]
            )
        )
    )
    if opaque == 0 do (minimum = color 0 0 0; maximum = color 0 0 0)
    local first = MLMhPack565 maximum
    local second = MLMhPack565 minimum
    if first < second do (local swap = first; first = second; second = swap)
    if transparent then (local swap = first; first = second; second = swap)
    else if first == second do
    (
        if first < 65535 then first += 1 else second -= 1
    )
    local a = MLMhUnpack565 first
    local b = MLMhUnpack565 second
    local palette = #(a,b)
    if transparent then append palette ((a + b) * 0.5)
    else
    (
        append palette ((a * 2.0 + b) / 3.0)
        append palette ((a + b * 2.0) / 3.0)
    )
    local packed = 0
    for pixelIndex = 1 to 16 do
    (
        local value = pixels[pixelIndex]
        local selected = 3
        if not (transparent and value.a < 128) do
        (
            local best = 1.0e30
            for index = 1 to palette.count do
            (
                local candidate = palette[index]
                local error = (value.r - candidate.r)^2 + (value.g - candidate.g)^2 + (value.b - candidate.b)^2
                if error < best do (best = error; selected = index - 1)
            )
        )
        packed = bit.or packed (bit.shift selected ((pixelIndex - 1) * 2))
    )
    writer.short first; writer.short second; writer.long packed
)
fn MLMhDxtAlpha writer pixels format =
(
    if format == "DXT3" then
    (
        for index = 1 to 16 by 2 do
        (
            local first = (floor (pixels[index].a / 17.0 + 0.5)) as integer
            local second = (floor (pixels[index + 1].a / 17.0 + 0.5)) as integer
            writer.byte (first + second * 16)
        )
    )
    else
    (
        local low = 255
        local high = 0
        for value in pixels do (low = amin low (MLMhColorByte value.a); high = amax high (MLMhColorByte value.a))
        writer.byte high; writer.byte low
        local palette = #(high,low)
        if high > low then
        (
            for index = 1 to 6 do append palette (floor (((7 - index) * high + index * low) / 7.0))
        )
        else
        (
            for index = 1 to 4 do append palette (floor (((5 - index) * high + index * low) / 5.0))
            append palette 0; append palette 255
        )
        local bytes = #(0,0,0,0,0,0)
        for index = 1 to 16 do
        (
            local best = 1.0e30
            local selected = 0
            for candidate = 1 to 8 do
            (
                local error = abs (pixels[index].a - palette[candidate])
                if error < best do (best = error; selected = candidate - 1)
            )
            for bitIndex = 0 to 2 do
            (
                local position = (index - 1) * 3 + bitIndex
                local byteIndex = ((position / 8) as integer) + 1
                bytes[byteIndex] = bit.or bytes[byteIndex] (bit.shift (MLBits selected bitIndex 1) (mod position 8))
            )
        )
        for value in bytes do writer.byte value
    )
)
fn MLMhWriteDxt writer width height pixels format =
(
    for blockY = 0 to height - 1 by 4 do for blockX = 0 to width - 1 by 4 do
    (
        local block = #()
        for y = 0 to 3 do for x = 0 to 3 do
            append block pixels[(amin (width - 1) (blockX + x)) + (amin (height - 1) (blockY + y)) * width + 1]
        if format != "DXT1" do MLMhDxtAlpha writer block format
        MLMhDxtColour writer block (format == "DXT1")
    )
)
