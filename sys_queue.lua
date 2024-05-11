---@class QUEUE
local Queue = {}

---@enum UpdateType
Queue.UpdateType = {
    Update = 1,
    Render = 2
}

---@type { u_type:UpdateType, t_start: number, t_func: fun(time:number?), t_end: number }[]
Queue.timed_queue = {}
---@type { u_type:UpdateType, c_start: number, c_check: fun(time:number?), c_func: fun(time:number?) }[]
Queue.callback_queue = {}
---@type ModReference
Queue.Mod = RegisterMod("Queue", 1)
---@type number
Queue.UpdateFrameCount = 0
---@type number
Queue.RenderFrameCount = 0

---Add an item to the queue
---@param time number The time to call the function (in frames)
---@param duration number How many frames to call the function
---@param func fun(time:number?) The function to call
---@param type UpdateType How often the function should be updated
function Queue:AddItem(time, duration, func, type)
    -- The minimum duration is 1 frame
    duration = duration - 1
    -- The current frame count
    local currentFrame = type == Queue.UpdateType.Update and Queue.UpdateFrameCount or Queue.RenderFrameCount
    -- The time the event should start
    local startTime = currentFrame + time
    -- The time the event should end
    local endTime = currentFrame + time + duration

    -- Insert the event into the queue
    table.insert(Queue.timed_queue, { u_type = type, t_start = startTime, t_func = func, t_end = endTime })
end

---Add an item to the queue
---@param time number The time to call the function (in frames)
---@param check fun(time:number?):boolean The function to check if the callback should be run
---@param func fun(time:number?) The function to call
---@param type UpdateType How often the function should be updated
function Queue:AddCallback(time, check, func, type)
    -- The current frame count
    local currentFrame = type == Queue.UpdateType.Update and Queue.UpdateFrameCount or Queue.RenderFrameCount
    -- Insert the event into the queue
    table.insert(Queue.callback_queue, { u_type = type, c_start = currentFrame + time, c_check = check, c_func = func })
end

---Update each type of queue
---@param frameCount number The current number of frames
---@param type UpdateType The type of update being run
function Queue:UpdateQueue(frameCount, type)
    -- Loop through all items in the timed queue
    for i, q in pairs(Queue.timed_queue) do
        -- Check if the queue item exists
        if q ~= nil and q.u_type == type then
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
        if q ~= nil and q.u_type == type and frameCount >= q.c_start and q.c_check(frameCount - q.c_start) then
            -- Call the callback
            q.c_func(frameCount - q.c_start)
            -- Delete the item from the queue
            Queue.callback_queue[i] = nil
        end
    end
end

---Updating the queue, run every update frame
function Queue:OnUpdate()
    -- Update items in the queue that run every update frame
    Queue:UpdateQueue(Queue.UpdateFrameCount, Queue.UpdateType.Update)
    Queue.UpdateFrameCount = Queue.UpdateFrameCount + 1
end

Queue.Mod:AddCallback(ModCallbacks.MC_POST_UPDATE, Queue.OnUpdate)

---Updating the queue, run every frame
function Queue:OnRender()
    -- Update items in the queue that run every update frame
    Queue:UpdateQueue(Queue.RenderFrameCount, Queue.UpdateType.Render)
    Queue.RenderFrameCount = Queue.RenderFrameCount + 1
end

Queue.Mod:AddCallback(ModCallbacks.MC_POST_RENDER, Queue.OnRender)

return Queue