component = require("component")
local geolyzer = component.geolyzer
local sides = require("sides")
local robot = require("robot")
local inventory = component.inventory_controller
local shell = require("shell")

local function getFarScan(side)
    local offsetx = nil
    local offsetz = 0
    local offsety = -2

    local sizex = 12
    local sizez = 1
    local sizey = 5
    if side == sides.left then
        offsetx = -12

    elseif side == sides.right then
        offsetx = 0
    else
        error("Function getScan needs a sides left or right as argument")
        return
    end

    local map = {}
    local scanData = geolyzer.scan(offsetx, offsetz, offsety, sizex, sizez, sizey)
    local i = 1
    for y = 0, sizey - 1 do
        for z = 0, sizez - 1 do
            for x = 0, sizex - 1 do
                -- alternatively when thinking in terms of 3-dimensional table: map[offsety + y][offsetz + z][offsetx + x] = scanData[i]
                if (scanData[i] > 2.30) then
                    table.insert(map, {posx = offsetx + x, posy = offsety + y, posz = offsetz + z, hardness = scanData[i]})
                end
                i = i + 1
            end
        end
    end

    return map
end

local function getCubeScan()
    local offsetx = -1
    local offsetz = -1
    local offsety = -1

    local sizex = 3
    local sizez = 3
    local sizey = 3

    local map = {}
    local scanData = geolyzer.scan(offsetx, offsetz, offsety, sizex, sizez, sizey)
    local i = 1
    for y = 0, sizey - 1 do
        for z = 0, sizez - 1 do
            for x = 0, sizex - 1 do
                -- alternatively when thinking in terms of 3-dimensional table: map[offsety + y][offsetz + z][offsetx + x] = scanData[i]
                if (scanData[i] > 2.30) then
                    table.insert(map, {posx = offsetx + x, posy = offsety + y, posz = offsetz + z, hardness = scanData[i]})
                end
                i = i + 1
            end
        end
    end

    return map
end

--The table that will contain path historic
local movement_history = {}

local index_functions = {
    robot.forward,
    robot.back,
    robot.turnLeft,
    robot.turnRight,
    robot.turnAround,
    robot.up,
    robot.down
}

local function goBackToStart()
    for i= #movement_history, 1, -1 do
        index_functions[movement_history[i]]()
    end
    movement_history = {}
end

local function goBackToHistory(backing_amount)
    for i= #movement_history, #movement_history - backing_amount, -1 do
        index_functions[movement_history[i]]()
        table.remove(movement_history, i)
    end
end

local move_indexes = {
    [robot.forward] = 2,
    [robot.back] = 1,
    [robot.turnLeft] = 4,
    [robot.turnRight] = 3,
    [robot.turnAround] = 5,
    [robot.up] = 7,
    [robot.down] = 6
}

local function getDistance(x1,y1,z1, x2,y2,z2)
    return math.sqrt((x2-x1)^2 + (y2-y1)^2 + (z2-z1)^2)
end


movement_funcs = {
    [sides.up] = {robot.up, robot.swingUp, robot.detectUp},
    [sides.front] = {robot.forward, robot.swing, robot.detect},
    [sides.down] = {robot.down, robot.swingDown, robot.detectDown},
    [sides.back] = {robot.back}
}

local global_no_move = false
local global_no_history = true

local broken_blocks = {}

local x, y, z = 0, 0, 0

local function tryMove(side)
    if global_no_move == true then return end

    local broke_something = false
    --Detects if can go to direction
    while (movement_funcs[side][3]() == true) do
        if side ~= sides.back then
            --Try to break blocks
            local swing, type = movement_funcs[side][2]()
            if swing == true and type == 'block' then
                broke_something = true
            end

        elseif side == sides.back then
            robot.turnAround()
            local swing, type = robot.swing()
            if swing == true and type == 'block' then
                broke_something = true
            end
            robot.turnAround()

        else
            error("Unhandled error on tryMove: " .. side)
        end
        --Todo add a number of tentatives and make robot follow path historic
    end
    --Moves
    if broke_something then
        table.insert(broken_blocks, {x = x,y = y,z = z})
    end
    movement_funcs[side][1]()

    if global_no_history == false then table.insert(movement_history, move_indexes[movement_funcs[side][1]]) end
end

local turns_sequence = {
    ["front"] = {
        [sides.left] = robot.turnRight,
        [sides.right] = robot.turnLeft,
        [sides.back] = robot.turnAround
    },
    ["left"] = {
        [sides.front] = robot.turnLeft,
        [sides.back] = robot.turnRight,
        [sides.right] = robot.turnAround
    },
    ["right"] = {
        [sides.front] = robot.turnRight,
        [sides.back] = robot.turnLeft,
        [sides.left] = robot.turnAround
    },
    ["back"] = {
        [sides.left] = robot.turnLeft,
        [sides.right] = robot.turnRight,
        [sides.front] = robot.turnAround
    }
}

local function orient_facing(side, robot_facing)
    turns_sequence[side][robot_facing]()
    if global_no_history == false then table.insert(movement_history, move_indexes[turns_sequence[side][robot_facing]]) end
end

local function moveRobot(side, robot_facing)
    if side == sides.up then tryMove(sides.up) return robot_facing end
    if side == sides.down then tryMove(sides.down) return robot_facing end

    if side == sides.front then
        if robot_facing == sides.front then tryMove(sides.front) return sides.front end

        orient_facing("front", robot_facing)
        tryMove(sides.front)
        return sides.front
    end

    if side == sides.back then
        if robot_facing == sides.back then tryMove(sides.front) return sides.back end

        orient_facing("back", robot_facing)
        tryMove(sides.front)
        return sides.back
    end

    if side == sides.left then
        if robot_facing == sides.left then tryMove(sides.front) return sides.left end

        orient_facing("left", robot_facing)
        tryMove(sides.front)
        return sides.left
    end

    if side == sides.right then
        if robot_facing == sides.right then tryMove(sides.front) return sides.right end

        orient_facing("right", robot_facing)
        tryMove(sides.front)
        return sides.right
    end

    error("Invalid side passed to moveRobot: " .. side .. " | " .. robot_facing)
end

local offsets = {
    {x = 1, y = 0, z = 0, side = sides.right},
    {x =-1, y = 0, z = 0, side = sides.left},
    {x = 0, y = 1, z = 0, side = sides.up},
    {x = 0, y =-1, z = 0, side = sides.down},
    {x = 0, y = 0, z = 1, side = sides.back},
    {x = 0, y = 0, z =-1, side = sides.front}
}
local robot_facing = sides.front

local function goToPos(xD, yD, zD, reset_rotation)
    reset_rotation = reset_rotation or false

    while (x ~= xD or y ~= yD or z ~= zD) do
        local best_distance = 999999
        local offset_index = 0

        --Gets the best offset to move
        for i=1,6 do
            local distance = getDistance(xD,yD,zD, x+offsets[i].x,y+offsets[i].y,z+offsets[i].z)
            if distance < best_distance then
                best_distance = distance
                offset_index = i
            end
        end

        --Apply the movement
        --print("Going " .. sides[offsets[offset_index].side])
        x = x + offsets[offset_index].x
        y = y + offsets[offset_index].y
        z = z + offsets[offset_index].z
        --print(x .. " " .. y .. " " .. z .. " => " .. xD .. " " .. yD .. " " .. zD)
        robot_facing = moveRobot(offsets[offset_index].side, robot_facing)


    end

    --This resets the rotation as the same that started with
    if reset_rotation then
        global_no_move = true
        robot_facing = moveRobot(sides.front, robot_facing)
        global_no_move = false
    end
end

local function rotate(rotation)
    global_no_move = true
    robot_facing = moveRobot(rotation, robot_facing)
    global_no_move = false
end

local function getClosestOre(map)
    if #map == 0 then return end
    local best = 9999
    local best_index = nil

    for i,j in pairs(map) do
        local distance = getDistance(j.posx,j.posy,j.posz, x,y,z)
        if distance < best then
            best = distance
            best_index = i
        end
    end

    --todo Usar 00 como refenrencia
    local posx,posy,posz = map[best_index].posx, map[best_index].posy, map[best_index].posz
    table.remove(map, best_index)
    return posx,posy,posz
end

local function compareScans(back_scan, to_be_cleaned)
    local cleaned_scan = {}
    local copy_index = {}

    for i=1, #to_be_cleaned do
        local detected = false
        for j=1, #back_scan do
            --Found a copy on to_be_cleaned
            if back_scan[j].posx == to_be_cleaned[i].posx and  back_scan[j].posy == to_be_cleaned[i].posy and back_scan[j].posz == to_be_cleaned[i].posz then
                detected = true
                --print("Copy detected")
            end
        end
        if detected == true then
            table.insert(copy_index, true)
        else
            table.insert(copy_index, false)
        end
    end

    for i=1, #to_be_cleaned do
        if copy_index[i] == false then
            table.insert(cleaned_scan, to_be_cleaned[i])
        end
    end

    return cleaned_scan
end

local function convertCubeScan(cubeScan)
    for i=1,#cubeScan do
        cubeScan[i].posx = cubeScan[i].posx + x
        cubeScan[i].posy = cubeScan[i].posy + y
        cubeScan[i].posz = cubeScan[i].posz + z
    end
end

local function AlreadyBroken(x,y,z)
    for i=1,#broken_blocks do
        if broken_blocks[i].x == x and broken_blocks[i].y == y and broken_blocks[i].z == z then
            return true
        end
    end
    return false
end

local ores_count = 0

local function cubeScanLookOut(depth, now_depth, back_scan)
    local back_scan = back_scan or {}
    local cube_scan = getCubeScan()
    convertCubeScan(cube_scan)
    cube_scan = compareScans(back_scan, cube_scan)

    if #cube_scan > 0 then
        print("Found " .. #cube_scan .. " ores by cube scan")
    end

    for j=1, #cube_scan do
        local xO, yO, zO = getClosestOre(cube_scan)
        --print(xO .. " " .. yO .. " " .. zO .. " <---- Ore position")
        if not AlreadyBroken(xO,yO,zO) then
            goToPos(xO , yO, zO, false)
            ores_count = ores_count + 1
        end

        --io.write("Continue : ")
        if now_depth < depth then
            local bx, by, bz = x,y,z
            cubeScanLookOut(depth, now_depth+1, cube_scan)
            goToPos(bx, by, bz, false)
        end
    end
end

local function scanSection(depth)
    global_no_history = true
    local oldx, oldy, oldz = x,y,z

    local m = getFarScan(sides.left)
    print("Found " .. #m .. " ores by scan")
    for i=1, #m do
        local xO, yO, zO = getClosestOre(m)
        if not AlreadyBroken(xO,yO,zO+z) then
            goToPos(xO, yO, zO+z)
            ores_count = ores_count+ 1
        end
        cubeScanLookOut(depth, 1)
    end

    goToPos(oldx, oldy, oldz, true)

    m = getFarScan(sides.right)
    print("Found " .. #m .. " ores by scan")
    for i=1, #m do
        local xO, yO, zO = getClosestOre(m)
        if not AlreadyBroken(xO,yO,zO+z) then
            goToPos(xO, yO, zO+z)
            ores_count = ores_count + 1
        end
        cubeScanLookOut(depth, 1)
    end

    goToPos(oldx, oldy, oldz, true)
end

local function mineInTunnel(blocks_amount, depth)
    for i=1, blocks_amount do
        goToPos(x, y+1, z)
        goToPos(x, y, z-1)
        goToPos(x, y-1, z)
        scanSection(tonumber(depth))
        print("Found " .. ores_count .. " Ores -> " .. 3%i)
        ores_count = 0
        if 3 % i == 3 or i == 3 then
            broken_blocks = {}
            print("Cleaned buffer")
        end
        print(#broken_blocks .. " <-- Blocks buffer size")
    end
end

local function depositInventory()
    for i=1,robot.inventorySize() do
        if robot.count(i) > 0 then
            robot.select(i)
            local l,k = inventory.getInventorySize(sides.front)
            l = l or 0
            for j=1,l do
                inventory.dropIntoSlot(sides.front, j, 64)
            end
        end
    end
    robot.select(1)
end

local startx, starty,startz = x,y,z

local args, ops = shell.parse(...)
if #args < 3 then
    io.write("Usage: miner <steps> <start_offset> <cube_scan_depth>")
    return
end

local steps = tonumber(args[1])
local start_offset = tonumber(args[2])

goToPos(x, y, z-start_offset)
mineInTunnel(steps, args[3])
goToPos(startx,starty,startz,true)
rotate(sides.back)
depositInventory()
rotate(sides.front)


