---@class QUEUE
local Queue = {}
---@type { t_start: number, t_func: fun(time:number?), t_end: number }[]
Queue.timed_queue = {}
---@type { c_start: number, c_check: fun(time:number?), c_func: fun(time:number?) }[]
Queue.callback_queue = {}
---@type ModReference
Queue.Mod = RegisterMod("Queue", 1)

---Add an item to the queue
---@param time number The time to call the function (in frames)
---@param duration number How many frames to call the function
---@param func fun(time:number?) The function to call
function Queue:AddItem(time, duration, func)
    -- The minimum duration is 1 frame
    duration = duration - 1
    -- The current frame count
    local currentFrame = Isaac.GetFrameCount()
    -- The time the event should start
    local startTime = currentFrame + time
    -- The time the event should end
    local endTime = currentFrame + time + duration

    -- Insert the event into the queue
    table.insert(Queue.timed_queue, { t_start = startTime, t_func = func, t_end = endTime })
end

---Add an item to the queue
---@param time number The time to call the function (in frames)
---@param check fun(time:number?):boolean The function to check if the callback should be run
---@param func fun(time:number?) The function to call
function Queue:AddCallback(time, check, func)
    -- Insert the event into the queue
    table.insert(Queue.callback_queue, { c_start = Isaac.GetFrameCount() + time, c_check = check, c_func = func, type = "callback" })
end

---Updating the queue, run every update frame
function Queue:OnUpdate()
    -- Get the current frame count
    local frameCount = Isaac.GetFrameCount()
    -- Loop through all items in the timed queue
    for i, q in pairs(Queue.timed_queue) do
        -- Check if the queue item exists
        if q ~= nil then
            -- Check if it is time for the queue item to start
            if frameCount >= q.t_start then
                -- Run the queue item's function, with how much time has passed as input
                q.t_func(frameCount - q.t_start)
                -- Check if it is time for the queue item to end
                if frameCount >= q.t_end then
                    -- Delete the item from the queue
                    Queue.timed_queue[i] = nil
                end
            end
        end
    end

    -- Loop through all items in the callback queue
    for i, q in pairs(Queue.callback_queue) do
        -- Check if the queue item exists
        -- AND that it is time to start the check
        -- AND that the check succeeds
        if q ~= nil and frameCount >= q.c_start and q.c_check(frameCount - q.c_start) then
            -- Call the callback
            q.c_func(frameCount - q.c_start)
            -- Delete the item from the queue
            Queue.callback_queue[i] = nil
        end
    end
end

Queue.Mod:AddCallback(ModCallbacks.MC_POST_UPDATE, Queue.OnUpdate)

return Queue