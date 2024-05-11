local SACRILEGE = RegisterMod("Binding of Isaac-SACRILEGE Soundtrack", 1)
local SAVE = include("save_manager")
SAVE.Init(SACRILEGE)

local MUSIC = MusicManager()
local SFX = SFXManager()
---@type QUEUE
local QUEUE = include("sys_queue")

--#region Local data

---@class music_data
---@field id Music The music to play

---@type table<music_data>
local MUSIC_INFO = {
    megaSatan = {
        id = Isaac.GetMusicIdByName("Mega Satan Fight"),
    },
    ambushAlt = {
        id = Isaac.GetMusicIdByName("Challenge Room (fight) (Alt)"),
    },
}

---@class sfx_data
---@field delay number The amount of frames before the sound effect should trigger
---@field id SoundEffect The sound effect to play
---@field original SoundEffect The original sound effect that should be stopped from playing
---@field length number The length, in update frames, of the clip before the music should fade back in

---@type table<sfx_data>
local SFX_INFO = {
    devilRoomEnter = {
        delay = 0,
        id = Isaac.GetSoundIdByName("sacrilege_devilenter"),
        length = 3 * 60,
    },
    angelRoomAppear = {
        delay = 0,
        id = Isaac.GetSoundIdByName("sacrilege_angelappear"),
        original = SoundEffect.SOUND_CHOIR_UNLOCK,
    },
    challengeRoomEnter = {
        delay = 0,
        id = Isaac.GetSoundIdByName("sacrilege_challengeenter"),
        length = 5 * 60,
    },
    minibossRoomEnter = {
        delay = 0,
        id = Isaac.GetSoundIdByName("sacrilege_minibossenter"),
        length = 1.75 * 60,
    },
    devilItemTake = {
        delay = 0,
        id = Isaac.GetSoundIdByName("sacrilege_devilitemtake"),
        original = SoundEffect.SOUND_DEVILROOM_DEAL,
    },
    supersecretRoomAppear = {
        delay = 0,
        id = Isaac.GetSoundIdByName("sacrilege_supersecretappear"),
        length = 2.75 * 60,
    },
    ultrasecretRoomAppear = {
        delay = 0,
        id = Isaac.GetSoundIdByName("sacrilege_ultrasecretappear"),
        length = 2.75 * 60,
    },
}

---@enum DoorFlag
local DoorFlag = {
    Open = 101,
    Closed = 888,
}

---@enum RunType
local RunType = {
    OnRender = 1,
    OnNewRoom = 2,
}

---@class DoorCallback
---@field type RoomType
---@field callback fun()
---@field flag string
---@field trigger fun(self:DoorCallback, room:Room, door:GridEntityDoor, prev:DoorFlag, curr:DoorFlag):boolean
---@field runType RunType

---@type DoorCallback[]
local DoorCallbacks = {}
--#endregion

--#region Local functions

---Check if any player has the collectible
---@param id CollectibleType The collectible to look for
---@return boolean hasID Whether any player has the collectible
local function AnyPlayerHas(id)
    -- All relevant players in the room
    local playerList = Isaac.FindByType(EntityType.ENTITY_PLAYER, 0)
    -- Loop through all players
    for _, ent in pairs(playerList) do
        -- The current player
        local player = ent:ToPlayer()
        -- Check if the player has the collectible
        if player and player:HasCollectible(id) then
            return true
        end
    end
    -- No player has the collectible
    return false
end

---Play a sound effect
---@param info sfx_data The sound effect to play
local function PlaySFX(info)
    -- Stop the original SFX from playing, if there is one
    if info.original ~= nil then
        SFX:Stop(info.original)
    end
    -- Add the sound effect to a queue
    QUEUE:AddItem(info.delay, 0, function ()
        SFX:Play(info.id, 1)
    end, QUEUE.UpdateType.Render)
end

---Callback when an SFX ends
---@param info sfx_data The sound effect to wait for
---@param callback fun() The callback
local function WaitForSFXToEnd(info, callback)
    -- Add an item to the queue that waits for the sound to stop
    QUEUE:AddCallback(info.delay + 1, function (t)
        -- Whether the sound is playing or the length has finished
        return not SFX:IsPlaying(info.id) or (info.length and t > info.length)
    end, function ()
        callback()
    end, QUEUE.UpdateType.Render)
end

---Play a sound effect and pausr the music while it is playing
---@param info sfx_data The sound effect to play
---@param volUnmuteSpeed number How fast to fade back into the normal music
local function PlaySFXAlert(info, volUnmuteSpeed)
    -- Mute the music
    QUEUE:AddItem(0, 0, function ()
        MUSIC:VolumeSlide(0, 1)
        MUSIC:Disable()
    end, 2)
    -- Play the sound effect
    PlaySFX(info)
    -- Wait for the sound effect to finish, then play the music again
    WaitForSFXToEnd(info, function ()
        MUSIC:Enable()
        MUSIC:VolumeSlide(1, volUnmuteSpeed)
        QUEUE:AddItem(1 / volUnmuteSpeed, 0, function () MUSIC:UpdateVolume() end, 1)
    end)
end

---Play a sound effect when entering a room type for the first time on a floor, should be run every update frame
---@param type RoomType The type of room the sound should be played for
---@param func fun() The callback to be executed
local function CallbackWhenEnteringRoom(type, func)
    -- The current room
    local room = Game():GetLevel():GetCurrentRoom()
    -- Check if the current room is being visited for the first time and that the room is the right type
    if room:IsFirstVisit() and room:GetType() == type then
        -- Execute the callback
        func()
    end
end

---Play a sound effect when entering a room type that is uncleared on a floor, should be run every update frame
---@param type RoomType The type of room the sound should be played for
---@param func fun() The callback to be executed
local function CallbackWhenEnteringUnclearedRoom(type, func)
    -- The current room
    local room = Game():GetLevel():GetCurrentRoom()
    -- Check if the current room is being visited for the first time and that the room is the right type
    if not room:IsClear() and room:GetFrameCount() == 0 and room:GetType() == type then
        -- Execute the callback
        func()
    end
end

---Play a sound effect when a room of a specific type appears for the first time on the floor, should be run every update frame
---@param runType RunType The type of room the sound should be played for
local function CallbackWhenRoomAppears(runType)
    -- Initialize the door checking function
    local applicable = function (self, room, door, prev, curr) return door:IsRoomType(self.type) and prev == DoorFlag.Closed and curr == DoorFlag.Open end
    -- The current room
    local room = Game():GetLevel():GetCurrentRoom()
    -- The save for the current room
    local save = SAVE.GetRoomSave()
    if save then
        -- Loop through all door slots
        for i = 0, DoorSlot.NUM_DOOR_SLOTS do
            -- The door in the current slot
            local door = room:GetDoor(i)
            -- Loop through all callbacks
            for _, data in pairs(DoorCallbacks) do
                -- Check if the run type for the callback is the same
                if runType == data.runType then
                    -- Initialize the state of the doors in the room
                    save[data.flag] = save[data.flag] or {}
                    -- Initalize the state of this door
                    save[data.flag][i .. ""] = save[data.flag][i .. ""] or DoorFlag.Open
                    -- The previous state of the door
                    local previousState = save[data.flag][i .. ""]
                    -- The current state of the door
                    save[data.flag][i .. ""] = (door and door:IsOpen()) and DoorFlag.Open or DoorFlag.Closed
                    -- Initialize the trigger function
                    local check = data.trigger or applicable
                    -- Check if the door passes a trigger function
                    if door and check(data, room, door, previousState, save[data.flag][i .. ""]) then
                        -- Execute the callback
                        data.callback()
                    end
                end
            end
        end
    end
end

--#endregion

--#region Music

if REPENTOGON then
    ---Handles playing a special track for MegaSatan
    ---@param musicID Music The ID of the song being played
    ---@param volume number The volume of the song
    ---@return { musicID:Music, volume:number } | nil
    function SACRILEGE:MegaSatanMusic(musicID, volume)
        -- Check if the music to play is the Satan boss fight music, and if MegaSatan has spawned
        if musicID == Music.MUSIC_SATAN_BOSS and Isaac.CountEntities(nil, EntityType.ENTITY_MEGA_SATAN) > 0 then
            -- Return the new music
            return { MUSIC_INFO.megaSatan.id, volume }
        end
    end

    SACRILEGE:AddCallback(ModCallbacks.MC_PRE_MUSIC_PLAY, SACRILEGE.MegaSatanMusic)

    ---Handles playing a special track for Challenge Rooms
    ---@param musicID Music The ID of the song being played
    ---@param volume number The volume of the song
    ---@return { musicID:Music, volume:number } | nil
    function SACRILEGE:AmbushAltMusic(musicID, volume)
        -- Check if the music to play is the Satan boss fight music, and if MegaSatan has spawned
        if musicID == Music.MUSIC_CHALLENGE_FIGHT then
            -- The stage seed for random effects by stage
            local seed = Game():GetSeeds():GetStageSeed(Game():GetLevel():GetStage())
            -- The RNG object
            local rng = RNG()
            -- Set the seed for the RNG object
            rng:SetSeed(seed, 0)
            -- Check if the RNG check is passed
            if rng:RandomFloat() > 0.5 then
                -- Return the new music
                return { MUSIC_INFO.ambushAlt.id, volume }
            end
        end
    end

    SACRILEGE:AddCallback(ModCallbacks.MC_PRE_MUSIC_PLAY, SACRILEGE.AmbushAltMusic)
else
    print("[SACRILEGE] This mod works better with REPENTOGON! Please install it from the Steam Workshop or GitHub.")

    ---Handles playing a special track for MegaSatan
    function SACRILEGE:MegaSatanMusic()
        -- Check if the currently playing music is the satan boss music
        if MUSIC:GetCurrentMusicID() ~= Music.MUSIC_SATAN_BOSS then return end
        -- Play the MegaSatan boss music
        MUSIC:Play(MUSIC_INFO.megaSatan.id, 0.1)
        -- Update the volume of the music
        MUSIC:UpdateVolume()
    end

    SACRILEGE:AddCallback(ModCallbacks.MC_NPC_UPDATE, SACRILEGE.MegaSatanMusic, EntityType.ENTITY_MEGA_SATAN)

    ---Handles playing a special track for Challenge Rooms
    function SACRILEGE:AmbushAltMusic()
        -- The current room
        local room = Game():GetLevel():GetCurrentRoom()
        -- Check if the current room is a challenge room
        if room:GetType() == RoomType.ROOM_CHALLENGE then
            -- The stage seed for random effects by stage
            local seed = Game():GetSeeds():GetStageSeed(Game():GetLevel():GetStage())
            -- The RNG object
            local rng = RNG()
            -- Set the seed for the RNG object
            rng:SetSeed(seed, 0)
            -- Check if the RNG check is passed
            if rng:RandomFloat() > 0 then
                -- The floor's save data
                local save = SAVE.GetFloorSave()
                if save then
                    -- If the ambush was active in the last frame
                    local previousActive = save.ambushActive or false
                    -- If the ambush is active in the current frame
                    save.ambushActive = room:IsAmbushActive()
                    -- If the ambush was activated this frame
                    if not previousActive and save.ambushActive then
                        -- Play the alt ambush track
                        MUSIC:Play(MUSIC_INFO.ambushAlt.id, 0.1)
                        -- Update the volume of the music
                        MUSIC:UpdateVolume()
                    end
                end
            end
        end
    end

    SACRILEGE:AddCallback(ModCallbacks.MC_POST_UPDATE, SACRILEGE.AmbushAltMusic)
end

--#endregion

--#region Entering Rooms SFX

function SACRILEGE:SFXWhenEnteringRooms()
    ---Play a sound when entering a devil room for the first time
    CallbackWhenEnteringRoom(RoomType.ROOM_DEVIL, function() PlaySFXAlert(SFX_INFO.devilRoomEnter, 0.05) end)
    ---Play a sound when entering a challenge room for the first time
    CallbackWhenEnteringRoom(RoomType.ROOM_CHALLENGE, function() PlaySFXAlert(SFX_INFO.challengeRoomEnter, 0.05) end)
    ---Play a sound when entering a miniboss room when uncleared
    CallbackWhenEnteringUnclearedRoom(RoomType.ROOM_MINIBOSS, function() PlaySFXAlert(SFX_INFO.minibossRoomEnter, 0.05) end)

    CallbackWhenRoomAppears(RunType.OnNewRoom)
end

SACRILEGE:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, SACRILEGE.SFXWhenEnteringRooms)

--#endregion

--#region Rooms Appearing SFX

-- Angel Room Appearing
table.insert(DoorCallbacks, {
    type = RoomType.ROOM_ANGEL,
    callback = function() PlaySFX(SFX_INFO.angelRoomAppear) end,
    flag = "angelHasAppeared",
    runType = RunType.OnRender
})

-- Super secret Room Appearing
table.insert(DoorCallbacks, {
    type = RoomType.ROOM_SUPERSECRET,
    callback = function() PlaySFXAlert(SFX_INFO.supersecretRoomAppear, 0.05) end,
    flag = "supersecretHasAppeared",
    trigger = function (self, room, door, prev, curr)
        -- If the door is newly opened and the correct type of door
        local normalApp = door:IsRoomType(self.type) and prev == DoorFlag.Closed and curr == DoorFlag.Open
        -- If the door had to be bombed into/found
        local addApp = not Game():GetLevel():GetCanSeeEverything() and not AnyPlayerHas(CollectibleType.COLLECTIBLE_XRAY_VISION)
        -- If the sound should play
        return normalApp and addApp
    end,
    runType = RunType.OnRender
})

-- Ultra secret Room Appearing
table.insert(DoorCallbacks, {
    type = RoomType.ROOM_ULTRASECRET,
    callback = function() PlaySFXAlert(SFX_INFO.ultrasecretRoomAppear, 0.05) end,
    flag = "ultrasecretDoor",
    ---@type fun(self:DoorCallback, room:Room, door:GridEntityDoor, prev:DoorFlag, curr:DoorFlag):boolean
    trigger = function (self, room, door, _, _)
        return door:IsRoomType(self.type) and room:IsFirstVisit() and Game():GetLevel():GetRoomByIdx(door.TargetRoomIndex).VisitedCount == 0
    end,
    runType = RunType.OnNewRoom
})

---Play a sound when a room appears
function SACRILEGE:SFXRoomAppearing()
    CallbackWhenRoomAppears(RunType.OnRender)
end

SACRILEGE:AddCallback(ModCallbacks.MC_POST_RENDER, SACRILEGE.SFXRoomAppearing)

--#endregion

--#region Misc SFX

local itemTouched = {}

---Check if the player has collided with an item that has a price
---@param pickup EntityPickup
---@param player Entity
function SACRILEGE:PickupCollision(pickup, player)
    -- Check if the entity collided with is the player
    -- AND the pickup is a collectible
    -- AND the pickup has a price
    if player.Type == EntityType.ENTITY_PLAYER and pickup.Variant == PickupVariant.PICKUP_COLLECTIBLE and pickup.Price < 0 then
        -- Set that the player touched an item
        itemTouched[player.Index] = pickup.SubType
    end
end

SACRILEGE:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, SACRILEGE.PickupCollision)

---Play a sound effect when taking a deal in a devil room, run for each player every update frame
---@param player EntityPlayer
function SACRILEGE:SFXWhenTakingDeal(player)
    -- The current room
    local room = Game():GetLevel():GetCurrentRoom()
    -- Check if the current room is a devil room and the player has touched an item
    if room:GetType() == RoomType.ROOM_DEVIL and itemTouched[player.Index] and player.QueuedItem.Item and player.QueuedItem.Item.ID == itemTouched[player.Index] then
        -- Stop the normal SFX
        SFX:Stop(SoundEffect.SOUND_DEVILROOM_DEAL)
        -- Play the SFX
        QUEUE:AddItem(SFX_INFO.devilItemTake.delay, 0, function ()
            SFX:Play(SFX_INFO.devilItemTake.id)
        end, QUEUE.UpdateType.Render)
    end

    itemTouched[player.Index] = false
end

SACRILEGE:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, SACRILEGE.SFXWhenTakingDeal)


--#endregion