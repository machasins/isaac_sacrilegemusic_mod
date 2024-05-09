local SACRILEGE = RegisterMod("Binding of Isaac-SACRILEGE Soundtrack", 1)
local SAVE = include("save_manager")
SAVE.Init(SACRILEGE)

local MUSIC = MusicManager()
local SFX = SFXManager()
---@type QUEUE
local QUEUE = include("sys_queue")

--#region Local data

local OPEN_FLAG = 101
local CLOSED_FLAG = 888

---@class music_data
---@field id Music The music to play

---@type table<music_data>
local MUSIC_INFO = {
    megaSatan = {
        id = Isaac.GetMusicIdByName("Mega Satan Fight"),
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
    },
    angelRoomAppear = {
        delay = 0,
        id = Isaac.GetSoundIdByName("sacrilege_angelappear"),
        original = SoundEffect.SOUND_CHOIR_UNLOCK,
    },
    challengeRoomEnter = {
        delay = 0,
        id = Isaac.GetSoundIdByName("sacrilege_challengeenter"),
    },
    devilItemTake = {
        delay = 0,
        id = Isaac.GetSoundIdByName("sacrilege_devilitemtake"),
        original = SoundEffect.SOUND_DEVILROOM_DEAL,
    },
    supersecretRoomAppear = {
        delay = 0,
        id = Isaac.GetSoundIdByName("sacrilege_supersecretappear"),
        length = 3 * 30,
    },
}

--#endregion

--#region Local functions

---Play a sound effect
---@param info sfx_data
local function PlaySFX(info)
    -- Stop the original SFX from playing, if there is one
    if info.original ~= nil and SFX:IsPlaying(info.original) then
        SFX:Stop(info.original)
    end
    QUEUE:AddItem(info.delay, 0, function ()
        SFX:Play(info.id)
    end)
end

---Callback when an SFX ends
---@param info sfx_data
---@param callback fun()
local function WaitForSFXToEnd(info, callback)
    QUEUE:AddCallback(info.delay + 1, function (t)
        return not SFX:IsPlaying(info.id) or (info.length and t > info.length)
    end, function ()
        callback()
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

---Play a sound effect when a room of a specific type appears for the first time on the floor, should be run every update frame
---@param type RoomType The type of room the sound should be played for
---@param func fun() The callback to execute
---@param flag string Where to save the status of the door
local function CallbackWhenRoomAppears(type, func, flag)
    -- The current room
    local room = Game():GetLevel():GetCurrentRoom()
    -- The save for the current room
    local save = SAVE.GetRoomSave()
    -- Check if the current room has been cleared
    if room:IsClear() and save then
        -- Initialize the state of the doors in the room
        save[flag] = save[flag] or {}
        -- Loop through all door slots
        for i = 0, DoorSlot.NUM_DOOR_SLOTS do
            -- The door in the current slot
            local door = room:GetDoor(i)
            -- Check if the door exists
            if door then
                -- Initalize the state of this door
                save[flag][i .. ""] = save[flag][i .. ""] or OPEN_FLAG
                -- The previous state of the door
                local previousState = save[flag][i .. ""]
                -- The current state of the door
                save[flag][i .. ""] = door:IsOpen() and OPEN_FLAG or CLOSED_FLAG
                -- Check if the door is the correct room type 
                -- AND was not open in the last frame, but is now
                if door:IsRoomType(type) and previousState == CLOSED_FLAG and save[flag][i .. ""] == OPEN_FLAG then
                    -- Execute the callback
                    func()
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
end

--#endregion

--#region Entering Rooms SFX

function SACRILEGE:SFXWhenEnteringRooms()
    ---Play a sound when entering a devil room for the first time
    CallbackWhenEnteringRoom(RoomType.ROOM_DEVIL, function() PlaySFX(SFX_INFO.devilRoomEnter) end)
    ---Play a sound when entering a challenge room for the first time
    CallbackWhenEnteringRoom(RoomType.ROOM_CHALLENGE, function() PlaySFX(SFX_INFO.challengeRoomEnter) end)
end

SACRILEGE:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, SACRILEGE.SFXWhenEnteringRooms)

--#endregion

--#region Rooms Appearing SFX

---Play a sound when an angel room appears
function SACRILEGE:SFXRoomAppearing()
    CallbackWhenRoomAppears(RoomType.ROOM_ANGEL, function() PlaySFX(SFX_INFO.angelRoomAppear) end, "angelHasAppeared")
    CallbackWhenRoomAppears(RoomType.ROOM_SUPERSECRET, function()
        MUSIC:VolumeSlide(0)
        PlaySFX(SFX_INFO.supersecretRoomAppear)
        WaitForSFXToEnd(SFX_INFO.supersecretRoomAppear, function ()
            print('ended')
            MUSIC:VolumeSlide(1)
        end)
    end, "supersecretHasAppeared")
end

SACRILEGE:AddCallback(ModCallbacks.MC_POST_UPDATE, SACRILEGE.SFXRoomAppearing)

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
        itemTouched[player.Index] = true
    end
end

SACRILEGE:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, SACRILEGE.PickupCollision)

---Play a sound effect when taking a deal in a devil room, run for each player every update frame
---@param player EntityPlayer
function SACRILEGE:SFXWhenTakingDeal(player)
    -- The current room
    local room = Game():GetLevel():GetCurrentRoom()
    -- Check if the current room is a devil room and the player has touched an item
    if room:GetType() == RoomType.ROOM_DEVIL and itemTouched[player.Index] and player.QueuedItem.Item then
        -- Stop the normal SFX
        SFX:Stop(SoundEffect.SOUND_DEVILROOM_DEAL)
        -- Play the SFX
        QUEUE:AddItem(SFX_INFO.devilItemTake.delay, 0, function ()
            SFX:Play(SFX_INFO.devilItemTake.id)
        end)
    end

    itemTouched[player.Index] = false
end

SACRILEGE:AddCallback(ModCallbacks.MC_POST_PLAYER_UPDATE, SACRILEGE.SFXWhenTakingDeal)


--#endregion