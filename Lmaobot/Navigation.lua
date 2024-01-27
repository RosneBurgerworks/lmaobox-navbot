---@alias Connection { count: integer, connections: integer[] }
---@alias Node { x: number, y: number, z: number, id: integer, c: { [1]: Connection, [2]: Connection, [3]: Connection, [4]: Connection } }

local Common = require("Lmaobot.Common")
local SourceNav = require("Lmaobot.SourceNav")
local AStar = require("Lmaobot.A-Star")
local Lib, Log = Common.Lib, Common.Log

local FS = Lib.Utils.FileSystem

local function DistTo(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

---@class Pathfinding
local Navigation = {}

---@type Node[]
local Nodes = {}

---@type Node[]|nil
local CurrentPath = nil

---@param nodes Node[]
function Navigation.SetNodes(nodes)
    Nodes = nodes
end

---@return Node[]
function Navigation.GetNodes()
    return Nodes
end

---@return Node[]|nil
---@return Node[]|nil
function Navigation.GetCurrentPath()
    return CurrentPath
end

function Navigation.ClearPath()
    CurrentPath = nil
end

---@param id integer
---@return Node
function Navigation.GetNodeByID(id)
    return Nodes[id]
end

-- Removes the connection between two nodes (if it exists)
function Navigation.RemoveConnection(nodeA, nodeB)
    for dir = 1, 4 do
		local conDir = nodeA.c[dir]
        for i, con in pairs(conDir.connections) do
            if con == nodeB.id then
                print("Removing connection between " .. nodeA.id .. " and " .. nodeB.id)
                table.remove(conDir.connections, i)
                conDir.count = conDir.count - 1
                break
            end
        end
	end
end

---@param navFile string
function Navigation.LoadFile(navFile)
    -- Internal function to attempt to read and parse the nav file
    local function tryLoadNavFile(navFilePath)
        local file = io.open(navFilePath, "rb")
        if not file then
            return nil, "File not found"
        end

        local content = file:read("*a")
        file:close()

        local navData = SourceNav.parse(content)
        if not navData or #navData.areas == 0 then
            return nil, "Failed to parse nav file or no areas found."
        end

        return navData
    end

    -- Construct the full path to the nav file
    local fullPath = "tf/" .. navFile
    local navData, error = tryLoadNavFile(fullPath)

    -- Attempt to generate the nav file if it's not found
    if not navData and error == "File not found" then
        -- Remove convar protections and generate the nav file
        client.RemoveConVarProtection("sv_cheats")
        client.RemoveConVarProtection("nav_generate")
        client.SetConVar("sv_cheats", "1")
        client.Command("nav_generate", true)
        Log:Info("Generating nav file. Please wait...")

        -- Wait a moment to allow nav file generation
        local navGenerationDelay = 5  -- in seconds
        local startTime = os.time()
        repeat
            if os.time() - startTime > navGenerationDelay then
                break
            end
        until false

        -- Retry loading the nav file
        navData, error = tryLoadNavFile(fullPath)
        if not navData then
            Log:Error("Failed to load or parse generated nav file: " .. error)
            return
        end
    elseif not navData then
        Log:Error(error)
        return
    end

    -- Process the nav data
    Log:Info("Parsed %d areas from nav file.", #navData.areas)
    local navNodes = {}
    for _, area in ipairs(navData.areas) do
        local cX = (area.north_west.x + area.south_east.x) / 2
        local cY = (area.north_west.y + area.south_east.y) / 2
        local cZ = (area.north_west.z + area.south_east.z) / 2
        navNodes[area.id] = { x = cX, y = cY, z = cZ, id = area.id, c = area.connections }
    end
    navNodes[0] = { x = 0, y = 0, z = 0, id = 0, c = {} }
    Navigation.SetNodes(navNodes)
end


---@param pos Vector3|{ x:number, y:number, z:number }
---@return Node
function Navigation.GetClosestNode(pos)
    local closestNode = nil
    local closestDist = math.huge

    for _, node in pairs(Nodes) do
        local dist = DistTo(node, pos)
        if dist < closestDist then
            closestNode = node
            closestDist = dist
        end
    end

    return closestNode
end

-- Returns all adjacent nodes of the given node
---@param node Node
---@param nodes Node[]
local function GetAdjacentNodes(node, nodes)
	local adjacentNodes = {}

	for dir = 1, 4 do
		local conDir = node.c[dir]
        for _, con in pairs(conDir.connections) do
            local conNode = nodes[con]
            if conNode and node.z + 70 > conNode.z then
                table.insert(adjacentNodes, conNode)
            end
        end
	end

	return adjacentNodes
end

---@param startNode Node
---@param goalNode Node
function Navigation.FindPath(startNode, goalNode)
    if not startNode then
        Log:Warn("Invalid start node %d!", startNode.id)
        return
    end

    if not goalNode then
        Log:Warn("Invalid goal node %d!", goalNode.id)
        return
    end

    CurrentPath = AStar.Path(startNode, goalNode, Nodes, GetAdjacentNodes)
    if not CurrentPath then
        Log:Error("Failed to find path from %d to %d!", startNode.id, goalNode.id)
    end
end

return Navigation
