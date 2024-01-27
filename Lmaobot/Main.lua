--[[ Annotations ]]
---@alias NavConnection { count: integer, connections: integer[] }
---@alias NavNode { id: integer, x: number, y: number, z: number, c: { [1]: NavConnection, [2]: NavConnection, [3]: NavConnection, [4]: NavConnection } }

--[[ Imports ]]
local Common = require("Lmaobot.Common")
local Navigation = require("Lmaobot.Navigation")
local Lib = Common.Lib
---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")

-- Unload package for debugging
Lib.Utils.UnloadPackages("Lmaobot")

local Notify, FS, Fonts, Commands, Timer = Lib.UI.Notify, Lib.Utils.FileSystem, Lib.UI.Fonts, Lib.Utils.Commands, Lib.Utils.Timer
local Log = Lib.Utils.Logger.new("Lmaobot")
Log.Level = 0

--[[ Variables ]]

local options = {
    memoryUsage = true, -- Shows memory usage in the top left corner
    drawNodes = true, -- Draws all nodes on the map
    drawPath = true, -- Draws the path to the current goal
    drawCurrentNode = true, -- Draws the current node
    lookatpath = false, -- Look at where we are walking
    smoothLookAtPath = true, -- Set this to true to enable smooth look at path
    autoPath = true, -- Automatically walks to the goal
    shouldfindhealth = true, -- Path to health
    SelfHealTreshold = 45, -- Health percentage to start looking for healthPacks
}

local smoothFactor = 0.05
local currentNodeIndex = 1
local currentNodeTicks = 0

---@type Vector3[]
local healthPacks = {}

local Tasks = table.readOnly {
    None = 0,
    Objective = 1,
    Health = 2,
    Follow = 3,
    Medic = 4,
}

local currentTask = Tasks.Objective
local taskTimer = Timer.new()
local jumptimer = 0;
local Math = lnxLib.Utils.Math
local WPlayer = lnxLib.TF2.WPlayer

--[[ Functions ]]

-- Loads the nav file of the current map
local function LoadNavFile()
    local mapFile = engine.GetMapName()
    local navFile = string.gsub(mapFile, ".bsp", ".nav")

    Navigation.LoadFile(navFile)
end


local function Draw3DBox(size, pos)
    local halfSize = size / 2
    if not corners then
        corners1 = {
            Vector3(-halfSize, -halfSize, -halfSize),
            Vector3(halfSize, -halfSize, -halfSize),
            Vector3(halfSize, halfSize, -halfSize),
            Vector3(-halfSize, halfSize, -halfSize),
            Vector3(-halfSize, -halfSize, halfSize),
            Vector3(halfSize, -halfSize, halfSize),
            Vector3(halfSize, halfSize, halfSize),
            Vector3(-halfSize, halfSize, halfSize)
        }
    end

    local linesToDraw = {
        {1, 2}, {2, 3}, {3, 4}, {4, 1},
        {5, 6}, {6, 7}, {7, 8}, {8, 5},
        {1, 5}, {2, 6}, {3, 7}, {4, 8}
    }

    local screenPositions = {}
    for _, cornerPos in ipairs(corners1) do
        local worldPos = pos + cornerPos
        local screenPos = client.WorldToScreen(worldPos)
        if screenPos then
            table.insert(screenPositions, { x = screenPos[1], y = screenPos[2] })
        end
    end

    for _, line in ipairs(linesToDraw) do
        local p1, p2 = screenPositions[line[1]], screenPositions[line[2]]
        if p1 and p2 then
            draw.Line(p1.x, p1.y, p2.x, p2.y)
        end
    end
end

local function Normalize(vec)
    local length = math.sqrt(vec.x * vec.x + vec.y * vec.y + vec.z * vec.z)
    return Vector3(vec.x / length, vec.y / length, vec.z / length)
end

local function L_line(start_pos, end_pos, secondary_line_size)
    if not (start_pos and end_pos) then
        return
    end
    local direction = end_pos - start_pos
    local direction_length = direction:Length()
    if direction_length == 0 then
        return
    end
    local normalized_direction = Normalize(direction)
    local perpendicular = Vector3(normalized_direction.y, -normalized_direction.x, 0) * secondary_line_size
    local w2s_start_pos = client.WorldToScreen(start_pos)
    local w2s_end_pos = client.WorldToScreen(end_pos)
    if not (w2s_start_pos and w2s_end_pos) then
        return
    end
    local secondary_line_end_pos = start_pos + perpendicular
    local w2s_secondary_line_end_pos = client.WorldToScreen(secondary_line_end_pos)
    if w2s_secondary_line_end_pos then
        draw.Line(w2s_start_pos[1], w2s_start_pos[2], w2s_end_pos[1], w2s_end_pos[2])
        draw.Line(w2s_start_pos[1], w2s_start_pos[2], w2s_secondary_line_end_pos[1], w2s_secondary_line_end_pos[2])
    end
end

--[[ Callbacks ]]

local function OnDraw()
    draw.SetFont(Fonts.Verdana)
    draw.Color(255, 0, 0, 255)

    local me = entities.GetLocalPlayer()
    if not me then return end

    local myPos = me:GetAbsOrigin()
    local currentPath = Navigation.GetCurrentPath()
    local currentY = 120

    -- Memory usage
    if options.memoryUsage then
        local memUsage = collectgarbage("count")
        draw.Text(20, currentY, string.format("Memory usage: %.2f MB", memUsage / 1024))
        currentY = currentY + 20
    end

    -- Auto path informaton
    if options.autoPath then
        draw.Text(20, currentY, string.format("Current Node: %d", currentNodeIndex))
        currentY = currentY + 20
    end

    --Draw all nodes and sub-nodes with connections
    local navNodes = Navigation.GetNodes()
    if options.drawNodes then
        draw.Color(0, 255, 0, 255)  -- Color for main nodes
        -- Iterate through each main node
        for id, node in pairs(navNodes) do
            local nodePos = Vector3(node.x, node.y, node.z)
            local dist = (myPos - nodePos):Length()
            if dist > 700 then goto continue_main_node end

            local screenPos = client.WorldToScreen(nodePos)
            if not screenPos then goto continue_main_node end

            local x, y = screenPos[1], screenPos[2]
            draw.FilledRect(x - 4, y - 4, x + 4, y + 4)  -- Draw a small square for main node

            -- Draw sub-nodes for this main node
            if node.subnodes then
                draw.Color(255, 0, 0, 255)  -- Color for sub-nodes
                for _, subnode in ipairs(node.subnodes) do
                    local subNodePos = Vector3(subnode.x, subnode.y, subnode.z)
                    local subScreenPos = client.WorldToScreen(subNodePos)
                    if not subScreenPos then goto continue_sub_node end

                    draw.FilledRect(subScreenPos[1] - 1, subScreenPos[2] - 1, subScreenPos[1] + 1, subScreenPos[2] + 1)  -- Draw a smaller square for sub-node

                    -- Draw connections between sub-nodes
                    if subnode.neighbors then
                        draw.Color(0, 0, 255, 255)  -- Color for connections
                        for _, neighbor in ipairs(subnode.neighbors) do
                            local neighborPos = Vector3(neighbor.point.x, neighbor.point.y, neighbor.point.z)
                            local neighborScreenPos = client.WorldToScreen(neighborPos)
                            if neighborScreenPos then
                                draw.Line(subScreenPos[1], subScreenPos[2], neighborScreenPos[1], neighborScreenPos[2])  -- Draw line for connection
                            end
                        end
                    end

                    ::continue_sub_node::
                end
                draw.Color(0, 255, 0, 255)  -- Reset color to main nodes color
            end

            -- Node IDs for main nodes
            draw.Text(screenPos[1], screenPos[2] + 10, tostring(id))

            ::continue_main_node::
        end
    end


    -- Draw current path
    if options.drawPath and currentPath then
        draw.Color(255, 255, 255, 255)

        -- Iterate over all nodes in the path, excluding the last two nodes
        for i = 1, #currentPath - 2 do
            local node1 = currentPath[i]
            local node2 = currentPath[i + 1]

            local node1Pos = Vector3(node1.x, node1.y, node1.z)
            local node2Pos = Vector3(node2.x, node2.y, node2.z)

            local screenPos1 = client.WorldToScreen(node1Pos)
            local screenPos2 = client.WorldToScreen(node2Pos)
            if not screenPos1 or not screenPos2 then goto continue end

            if node1Pos and node2Pos then
                L_line(node1Pos, node2Pos, 22)  -- Adjust the size for the perpendicular segment as needed
            end
            ::continue::
        end

        -- Draw a line from the player to the second node from the end
        local secondLastNode = currentPath[#currentPath - 1]
        local secondLastNodePos = Vector3(secondLastNode.x, secondLastNode.y, secondLastNode.z)
        L_line(myPos, secondLastNodePos, 22)
    end

    -- Draw current node
    if options.drawCurrentNode and currentPath then
        draw.Color(255, 0, 0, 255)

        local currentNode = currentPath[currentNodeIndex]
        local currentNodePos = Vector3(currentNode.x, currentNode.y, currentNode.z)

        local screenPos = client.WorldToScreen(currentNodePos)
        if screenPos then
            Draw3DBox(22, currentNodePos)
            draw.Text(screenPos[1], screenPos[2], tostring(currentNodeIndex))
        end
    end
end

local function isVisible(fromPos, toPos)
    local trace = engine.TraceLine(fromPos, toPos, MASK_SHOT_HULL)
    return trace.fraction == 1.0  -- True if the line trace did not hit any obstacles
end

local movementChangeTimer = 66
local previousTask = nil

---@param userCmd UserCmd
local function OnCreateMove(userCmd)
    if not options.autoPath then return end

    local me = entities.GetLocalPlayer()
    if not me or not me:IsAlive() then
        movementChangeTimer = movementChangeTimer - 1
        if movementChangeTimer < 1 then
            Navigation.ClearPath()
            movementChangeTimer = 66
        end
        return
    end

    --if not gamerules.IsMatchTypeCasual() then return end -- return if not in casual.

    -- emergency healthpack task
    if taskTimer:Run(0.7) then
        -- make sure we're not being healed by a medic before running health logic
        if (me:GetHealth() / me:GetMaxHealth()) * 100 < options.SelfHealTreshold and not me:InCond(TFCond_Healing) then
            if currentTask ~= Tasks.Health and options.shouldfindhealth then
                Log:Info("Switching to health task")
                Navigation.ClearPath()
                previousTask = currentTask
            end

            currentTask = Tasks.Health
        else
            if previousTask and currentTask ~= previousTask then
                Log:Info("Switching back to previous task")
                Navigation.ClearPath()
                currentTask = previousTask
                previousTask = nil
            end
        end
    end

    local myPos = me:GetAbsOrigin()
    local currentPath = Navigation.GetCurrentPath()

    if currentTask == Tasks.None then return end

    if currentPath then
        -- Move along path
        if userCmd:GetForwardMove() ~= 0 or userCmd:GetSideMove() ~= 0 then
            Navigation.ClearPath()
            currentNodeTicks = 0
            return
        end

        local currentNode = currentPath[currentNodeIndex]
        local currentNodePos = Vector3(currentNode.x, currentNode.y, currentNode.z)

        if options.lookatpath then
            if currentNodePos == nil then
                return
            else
                local melnx = WPlayer.GetLocal()
                local angles = Lib.Utils.Math.PositionAngles(melnx:GetEyePos(), currentNodePos)
                angles.x = 0
    
                if options.smoothLookAtPath then
                    local currentAngles = userCmd.viewangles
                    local deltaAngles = {x = angles.x - currentAngles.x, y = angles.y - currentAngles.y}

                    deltaAngles.y = math.fmod(deltaAngles.y + 180, 360) - 180

                    angles = EulerAngles(currentAngles.x + deltaAngles.x * 0.5, currentAngles.y + deltaAngles.y * smoothFactor, 0)
                end
    
                engine.SetViewAngles(angles)
            end
        end

        local dist = (myPos - currentNodePos):Length()
        if dist < 22 then
            currentNodeTicks = 0
            for i = #currentPath, currentNodeIndex + 1, -1 do
                table.remove(currentPath, i)
            end
            currentNodeIndex = currentNodeIndex - 1
            if currentNodeIndex < 1 then
                Navigation.ClearPath()
                Log:Info("Reached end of path")
                currentTask = Tasks.None
            end
        else
            currentNodeTicks = currentNodeTicks + 1

            -- Initialize closest node variables
            local closestNodeIndex = currentNodeIndex
            local closestNode = currentNode
            local closestNodePos = currentNodePos
            local closestDist = dist

            -- Iterate over all nodes in the path, excluding the last node
            for i = currentNodeIndex + 1, #currentPath do  -- Start from the next node
                local node = currentPath[i]
                local nodePos = Vector3(node.x, node.y, node.z)
                local nodeDist = (myPos - nodePos):Length()

                local viewPos = me:GetAbsOrigin() + Vector3(0, 0, 72)  -- Eye position

                -- If the node is visible and closer, update closest node variables
                if isVisible(viewPos, nodePos) and nodeDist < closestDist then
                    closestNodeIndex = i
                    closestNode = node
                    closestNodePos = nodePos
                    closestDist = nodeDist
                    break  -- Break the loop as we prefer the closest visible node
                end
            end

            if closestNodeIndex ~= currentNodeIndex then
                Log:Info("Skipping to closer node %d", closestNodeIndex)
                currentNodeIndex = closestNodeIndex
                currentNode = closestNode
                currentNodePos = closestNodePos
                dist = closestDist
            else
                -- No closer visible node found, continue towards the current node
                Lib.TF2.Helpers.WalkTo(userCmd, me, currentNodePos)
            end
        end

        -- Jump if stuck
        if currentNodeTicks > 17 and not me:InCond(TFCond_Zoomed) and me:EstimateAbsVelocity():Length() < 50 then
            --hold down jump for half a second or something i dont know how long it is
            jumptimer = jumptimer + 1;
            userCmd.buttons = userCmd.buttons | IN_JUMP
        end

        -- Repath if stuck
        if currentNodeTicks > 200 then
            local viewPos = me:GetAbsOrigin() + Vector3(0, 0, 72)
            local trace = engine.TraceLine(viewPos, currentNodePos, MASK_SHOT_HULL)
            if trace.fraction < 0.8 then
                Log:Warn("Path to node %d is still blocked after repathing, removing connection and repathing...", currentNodeIndex)
                Navigation.RemoveConnection(currentNode, currentPath[currentNodeIndex - 1])
                Navigation.ClearPath()
                currentNodeTicks = 0
            else
                Log:Warn("Path to node %d is blocked, repathing...", currentNodeIndex)
                Navigation.ClearPath()
                currentNodeTicks = 0
            end
        end
    else
        -- Generate new path
        local startNode = Navigation.GetClosestNode(myPos)
        local goalNode = nil
        local entity = nil

        if not startNode then
            Log:Warn("Could not find a start node near the player's position.")
            return
        end

        if currentTask == Tasks.Objective then
            local objectives = nil

            -- map check
            if engine.GetMapName():lower():find("cp_") then
                -- cp
                objectives = entities.FindByClass("CTFObjectiveResource")
            elseif engine.GetMapName():lower():find("pl_") then
                -- pl
                objectives = entities.FindByClass("CObjectCartDispenser")
            elseif engine.GetMapName():lower():find("ctf_") then
                -- ctf
                local myItem = me:GetPropInt("m_hItem")
                local flags = entities.FindByClass("CCaptureFlag")
                for idx, entity in pairs(flags) do
                    local myTeam = entity:GetTeamNumber() == me:GetTeamNumber()
                    if (myItem > 0 and myTeam) or (myItem < 0 and not myTeam) then
                        goalNode = Navigation.GetClosestNode(entity:GetAbsOrigin())
                        Log:Info("Found flag at node %d", goalNode.id)
                        break
                    end
                end
            else
                Log:Warn("Unsupported Gamemode, try CTF or PL")
                return
            end

            -- Ensure objectives is a table before iterating
            if objectives and type(objectives) == "table" and #objectives > 0 then
                local closestDist = math.huge
                for idx, ent in pairs(objectives) do
                    local objectiveNode = Navigation.GetClosestNode(ent:GetAbsOrigin())
                    if objectiveNode then
                        local dist = (myPos - ent:GetAbsOrigin()):Length()
                        if dist < closestDist then
                            closestDist = dist
                            goalNode = objectiveNode
                            entity = ent
                            Log:Info("Found objective at node %d", goalNode.id)
                        end
                    end
                end
            else
                --Log:Warn("No objectives found; iterate failure.")
            end

            -- Specific checks for PL gamemode
            if engine.GetMapName():lower():find("pl_") and entity and goalNode then
                local distanceToPayload = (myPos - entity:GetAbsOrigin()):Length()
                local thresholdDistance = 80

                if distanceToPayload > thresholdDistance then
                    Log:Info("Payload too far from player, pathing closer.")
                    -- If too far, update the path to get closer
                    Navigation.FindPath(startNode, goalNode)
                    currentNodeIndex = #Navigation.GetCurrentPath()
                end
            end

            if not goalNode then
                Log:Warn("No objectives found. Continuing with default objective task.")
                currentTask = Tasks.Objective
                Navigation.ClearPath()
            end
        elseif currentTask == Tasks.Health then
            local closestDist = math.huge
            for idx, pos in pairs(healthPacks) do
                local healthNode = Navigation.GetClosestNode(pos)
                if healthNode then
                    local dist = (myPos - pos):Length()
                    if dist < closestDist then
                        closestDist = dist
                        goalNode = healthNode
                        Log:Info("Found health pack at node %d", goalNode.id)
                    end
                end
            end
        elseif currentTask == Tasks.Follow then


        elseif currentTask == Tasks.Medic then

        else
            Log:Debug("Unknown task: %d", currentTask)
            return
        end

        -- Check if we found a start and goal node
        if not goalNode then
            Log:Warn("Could not find new goal node")
            return
        end

        -- Update the pathfinder
        Log:Info("Generating new path from node %d to node %d", startNode.id, goalNode.id)
        Navigation.FindPath(startNode, goalNode)

        currentPath = Navigation.GetCurrentPath()
        if currentPath and #currentPath > 0 then
            currentNodeIndex = #currentPath
        else
            Log:Warn("Failed to find a path from node %d to node %d", startNode.id, goalNode.id)
        end
    end
end

---@param ctx DrawModelContext
local function OnDrawModel(ctx)
    -- TODO: This find a better way to do this
    if ctx:GetModelName():find("medkit") then
        local entity = ctx:GetEntity()
        healthPacks[entity:GetIndex()] = entity:GetAbsOrigin()
    end
end

---@param event GameEvent
local function OnGameEvent(event)
    local eventName = event:GetName()

    -- Reload nav file on new map
    if eventName == "game_newmap" then
        Log:Info("New map detected, reloading nav file...")

        healthPacks = {}
        LoadNavFile()
    end
end

callbacks.Unregister("Draw", "LNX.Lmaobot.Draw")
callbacks.Unregister("CreateMove", "LNX.Lmaobot.CreateMove")
callbacks.Unregister("DrawModel", "LNX.Lmaobot.DrawModel")
callbacks.Unregister("FireGameEvent", "LNX.Lmaobot.FireGameEvent")

callbacks.Register("Draw", "LNX.Lmaobot.Draw", OnDraw)
callbacks.Register("CreateMove", "LNX.Lmaobot.CreateMove", OnCreateMove)
callbacks.Register("DrawModel", "LNX.Lmaobot.DrawModel", OnDrawModel)
callbacks.Register("FireGameEvent", "LNX.Lmaobot.FireGameEvent", OnGameEvent)

--[[ Commands ]]

-- Reloads the nav file
Commands.Register("pf_reload", function()
    LoadNavFile()
end)

-- credits: snipergaming888 (Sydney)

local switch = 0;
local switchmax = 1;


local function newmap_eventNav(event)
    if event:GetName() == "game_newmap" then
        LoadNavFile()
    end
end

local function Restart(event)
    if event:GetName() == "teamplay_round_start" then
        switch = switch + 1;
        LoadNavFile()
            if switch == switchmax then 
                switch = 0;
            end    
    end
end  

callbacks.Register("FireGameEvent", "newm_event", newmap_eventNav)
callbacks.Register("FireGameEvent", "teamplay_restart_round", Restart)

-- Calculates the path from start to goal
Commands.Register("pf", function(args)
    if args:size() ~= 2 then
        print("Usage: pf <Start> <Goal>")
        return
    end

    local start = tonumber(args:popFront())
    local goal = tonumber(args:popFront())

    if not start or not goal then
        print("Start/Goal must be numbers!")
        return
    end

    local startNode = Navigation.GetNodeByID(start)
    local goalNode = Navigation.GetNodeByID(goal)

    if not startNode or not goalNode then
        print("Start/Goal node not found!")
        return
    end

    Navigation.FindPath(startNode, goalNode)
end)

Commands.Register("pf_auto", function (args)
    options.autoPath = not options.autoPath
    print("Auto path: " .. tostring(options.autoPath))
end)

Notify.Alert("Lmaobot loaded!")
LoadNavFile()