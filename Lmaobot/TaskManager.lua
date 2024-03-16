local TaskManager = {}
TaskManager.tasks = {}
TaskManager.sortedIdentifiers = {}

--- Adds a task to the TaskManager
--- @param func function The function to be executed
--- @param args table The arguments to pass to the function
--- @param delay number The delay (in ticks) before the function should be executed
--- @param identifier string A unique identifier for the task
function TaskManager.addTask(func, args, delay, identifier)
    local currentTime = globals.TickCount()
    args = args or {}

    if TaskManager.tasks[identifier] then
        -- Update existing task details (function, delay, args) but not lastExecuted
        TaskManager.tasks[identifier].func = func
        TaskManager.tasks[identifier].delay = delay or 1
        TaskManager.tasks[identifier].args = args or {}
        TaskManager.tasks[identifier].wasExecuted = false
        -- No need to re-insert into sortedIdentifiers or re-sort, as delay order hasn't changed
    else
        -- Add new task
        TaskManager.tasks[identifier] = {
            func = func,
            delay = delay,
            args = args,
            lastExecuted = currentTime,
            wasExecuted = false,
        }
        -- Insert identifier and sort tasks based on their delay, in descending order
        table.insert(TaskManager.sortedIdentifiers, identifier)
        table.sort(TaskManager.sortedIdentifiers, function(a, b)
            return TaskManager.tasks[a].delay > TaskManager.tasks[b].delay
        end)
    end
end

function TaskManager.TickUpdate()
    local currentTime = globals.TickCount()
    for _, identifier in ipairs(TaskManager.sortedIdentifiers) do
        local task = TaskManager.tasks[identifier]
        if not task.wasExecuted and currentTime - task.lastExecuted >= task.delay then
            -- Execute the task
            task.func(table.unpack(task.args))
            task.wasExecuted = true
            -- Reset task data except for lastExecuted
            task.func = nil
            task.args = nil
            task.delay = nil
            -- Execute only the first eligible task per tick
            return
        end
    end
end

return TaskManager
