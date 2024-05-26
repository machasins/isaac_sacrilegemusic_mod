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
        id = Isaac.GetMusicIdByName("Sacrilege Boss (Mega Satan)"),
    },
    ambushAlt = {
        id = Isaac.GetMusicIdByName("Sacrilege Challenge Room (fight) (Alt)"),
    },
    unicornMusic = {
        id = Isaac.GetMusicIdByName("Sacrilege Unicorn"),
    },
}

---@class sfx_data
---@field delay number The amount of frames before the sound effect should trigger
---@field volume number The volume multiplier for the sfx
---@field id SoundEffect The sound effect to play
---@field original SoundEffect The original sound effect that should be stopped from playing
---@field length number The length, in update frames, of the clip before the music should fade back in

---@type table<sfx_data>
local SFX_INFO = {
    devilRoomEnter = {
        delay = 0,
        volume = 2,
        id = Isaac.GetSoundIdByName("sacrilege_devilenter"),
        length = 3 * 60,
    },
    angelRoomAppear = {
        delay = 0,
        volume = 3,
        id = Isaac.GetSoundIdByName("Sacrilege Holy Room Find (jingle)"),
        original = SoundEffect.SOUND_CHOIR_UNLOCK,
    },
    challengeRoomEnter = {
        delay = 0,
        volume = 2,
        id = Isaac.GetSoundIdByName("sacrilege_challengeenter"),
        length = 5 * 60,
    },
    minibossRoomEnter = {
        delay = 0,
        volume = 2,
        id = Isaac.GetSoundIdByName("sacrilege_minibossenter"),
        length = 1.75 * 60,
    },
    devilItemTake = {
        delay = 0,
        volume = 1,
        id = Isaac.GetSoundIdByName("sacrilege_devilitemtake"),
        original = SoundEffect.SOUND_DEVILROOM_DEAL,
    },
    supersecretRoomAppear = {
        delay = 0,
        volume = 2,
        id = Isaac.GetSoundIdByName("sacrilege_supersecretappear"),
        length = 3 * 60,
    },
    ultrasecretRoomAppear = {
        delay = 0,
        volume = 2,
        id = Isaac.GetSoundIdByName("sacrilege_ultrasecretappear"),
        length = 3 * 60,
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
---@field type RoomType The room type to trigger the callback on
---@field callback fun() The callback when a room is encountered
---@field doorFlag string The save data flag that should be used for the doors
---@field roomFlag string The save data flag that should be used for the room being encountered
---@field setting fun():boolean Whether to run this callback
---@field trigger (fun(self:DoorCallback, room:Room, door:GridEntityDoor, prev:DoorFlag, curr:DoorFlag, seen:boolean):boolean)? Whether the callback should be triggered
---@field runType RunType When this callback should be checked

---@type table<string, DoorCallback>
local DoorCallbacks = {}

---@class UnicornEffect
---@field hasEffect boolean
---@field duration number

---@type table<integer, table<CollectibleType, UnicornEffect>>
local unicornEffects = {}

local dadsKeyUsedThisFrame = false

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
        SFX:Play(info.id, info.volume)
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
    end, callback, QUEUE.UpdateType.Render)
end

---Callback when an SFX ends
---@param info sfx_data The sound effect to wait for
---@param checkFunc fun(integer?):boolean A check function that checks if the sound should be interupted
---@param callback fun() The callback
local function WaitForSFXEvent(info, checkFunc, callback)
    -- Add an item to the queue that waits for the sound to stop
    QUEUE:AddCallback(info.delay + 1, checkFunc, callback, QUEUE.UpdateType.Render)
end

---Play a sound effect and pause the music while it is playing
---@param info sfx_data The sound effect to play
---@param volUnmuteSpeed number How fast to fade back into the normal music
---@param disableMusic boolean? Whether to disable the music entirely during the sfx
local function PlaySFXAlert(info, volUnmuteSpeed, disableMusic)
    -- Mute the music
    QUEUE:AddItem(0, 0, function ()
        MUSIC:VolumeSlide(0, 1)
        if disableMusic then MUSIC:Disable() end
    end, 2)
    -- Play the sound effect
    PlaySFX(info)
    -- Wait for the sound effect to finish, then play the music again
    WaitForSFXToEnd(info, function ()
        if disableMusic then MUSIC:Enable() end
        MUSIC:VolumeSlide(1, volUnmuteSpeed)
        QUEUE:AddItem(1 / volUnmuteSpeed, 0, function () MUSIC:UpdateVolume() end, 1)
    end)
end

---Play a sound effect and pause the music while it is playing, but can be interupted if needed
---@param info sfx_data The sound effect to play
---@param checkFunc fun():boolean A check function that checks if the sound should be interupted
---@param volUnmuteSpeed number How fast to fade back into the normal music
---@param disableMusic boolean? Whether to disable the music entirely during the sfx
local function PlaySFXAlertInterupt(info, checkFunc, volUnmuteSpeed, disableMusic)
    -- Mute the music
    QUEUE:AddItem(0, 0, function ()
        MUSIC:VolumeSlide(0, 1)
        if disableMusic then MUSIC:Disable() end
    end, 2)
    -- Play the sound effect
    PlaySFX(info)
    -- Function to stop the music from playing
    local stopMusic = function ()
        SFX:Stop(info.id)
        if disableMusic then MUSIC:Enable() end
        MUSIC:VolumeSlide(1, volUnmuteSpeed)
        QUEUE:AddItem(1 / volUnmuteSpeed, 0, function () MUSIC:UpdateVolume() end, 1)
    end
    -- Wait for the sound effect to finish, then play the music again
    WaitForSFXToEnd(info, stopMusic)
    WaitForSFXEvent(info, checkFunc, stopMusic)
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
---@param trig (fun(room:Room):boolean)? Whether to trigger the callback
local function CallbackWhenEnteringUnclearedRoom(type, func, trig)
    trig = trig or function (room) return true end
    -- The current room
    local room = Game():GetLevel():GetCurrentRoom()
    -- Check if the current room is being visited for the first time and that the room is the right type
    if not room:IsClear() and room:GetFrameCount() == 0 and room:GetType() == type and trig(room) then
        -- Execute the callback
        func()
    end
end

---Play a sound effect when a room of a specific type appears for the first time on the floor, should be run every update frame
---@param runType RunType The type of room the sound should be played for
local function CallbackWhenRoomAppears(runType)
    -- Initialize the door checking function
    local applicable = function (self, room, door, prev, curr, seen) return not seen and door:IsRoomType(self.type) and prev == DoorFlag.Closed and curr == DoorFlag.Open end
    -- The current room
    local room = Game():GetLevel():GetCurrentRoom()
    -- The save for the current room
    local roomSave = SAVE.GetRoomSave()
    -- The save for the current floor
    local floorSave = SAVE.GetFloorSave()
    if roomSave and floorSave then
        -- Loop through all door slots
        for i = 0, DoorSlot.NUM_DOOR_SLOTS do
            -- The door in the current slot
            local door = room:GetDoor(i)
            local doorRoomIndex = door and Game():GetLevel():GetRoomByIdx(door.TargetRoomIndex).SafeGridIndex or -1
            -- Loop through all callbacks
            for _, data in pairs(DoorCallbacks) do
                -- Initialize the state of rooms on the floor
                floorSave[data.roomFlag] = floorSave[data.roomFlag] or {}
                -- Initialize the state of the doors in the room
                roomSave[data.doorFlag] = roomSave[data.doorFlag] or {}
                -- Check if the run type for the callback is the same
                if runType == data.runType and data.setting() then
                    -- Initalize whether the player used the callback for this door before
                    floorSave[data.roomFlag][doorRoomIndex .. ""] = floorSave[data.roomFlag][doorRoomIndex .. ""] or false
                    -- Initalize the state of this door
                    roomSave[data.doorFlag][i .. ""] = roomSave[data.doorFlag][i .. ""] or DoorFlag.Open
                    -- The previous state of the door
                    local previousState = roomSave[data.doorFlag][i .. ""]
                    -- The current state of the door
                    roomSave[data.doorFlag][i .. ""] = (door and door:IsOpen()) and DoorFlag.Open or DoorFlag.Closed
                    -- Initialize the trigger function
                    local check = data.trigger or applicable
                    -- Whether the door passes a trigger function
                    local checkValue = door and check(data, room, door, previousState, roomSave[data.doorFlag][i .. ""], floorSave[data.roomFlag][doorRoomIndex .. ""])
                    -- Check if the door succeeded
                    if checkValue then
                        -- Execute the callback
                        data.callback()
                        -- Save that the callback was executed for this room
                        floorSave[data.roomFlag][doorRoomIndex .. ""] = true
                    end
                end
            end
        end
    end
end

--#endregion

--#region Music

---Compatibility with the Soundtrack mod
function SACRILEGE:OnGameStart()
	if SoundtrackSongList then
		--add soundtrack to menu
		AddSoundtrackToMenu("Sacrilege")
		--add track list to jukebox
		if nil then
			AddTitlesToJukebox("Sacrilege", "Sacrilege", "Sacrilege", nil)
		end
	end
end
SACRILEGE:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, SACRILEGE.OnGameStart)

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

if StageAPI then
    -- idk the flash unicorn sound mod had this so we keeping it
    StageAPI.StopOverridingMusic(MUSIC_INFO.unicornMusic.id, true, true)
end

---Start playing the unicorn music when the player gets the corresponding effect
---@param player EntityPlayer
function SACRILEGE:UnicornEffectUpdate(player)
    -- The collectibles that can cause the unicorn effect
    local COLLECTIBLE_EFFECTS = {
        CollectibleType.COLLECTIBLE_GAMEKID,
        CollectibleType.COLLECTIBLE_UNICORN_STUMP,
        CollectibleType.COLLECTIBLE_MY_LITTLE_UNICORN,
        CollectibleType.COLLECTIBLE_TAURUS
    }

    -- Initialize variable that store the player's effect status
    unicornEffects[player.Index] = unicornEffects[player.Index] or {}

    -- The effects the player has
    local effects = player:GetEffects()
    -- The status of each effect
    local effectStatus = unicornEffects[player.Index]
    -- The current music being played
    local currentSong = MUSIC:GetCurrentMusicID()

    -- Loop through all collectibles
    for _, v in pairs(COLLECTIBLE_EFFECTS) do
        -- Initialize the effect status if needed
        effectStatus[v] = effectStatus[v] or {}
        -- Whether the effect was active in the last frame
        local previousHad = effectStatus[v].hasEffect
        -- Whether the effect is active this frame
        effectStatus[v].hasEffect = effects:HasCollectibleEffect(v)
        -- Check if the player has the effect
        if effectStatus[v].hasEffect then
            local effect = effects:GetCollectibleEffect(v)
            -- Check if the effect is new on this frame or if the song has ended but the effect is still ongoing
            if effect.Cooldown > 0 and (not previousHad or currentSong ~= MUSIC_INFO.unicornMusic.id) then
                -- Undo the pitch caused by the normal unicorn effect
                MUSIC:PitchSlide(1)
                -- Play the current music
                MUSIC:Play(MUSIC_INFO.unicornMusic.id, 1)
                -- Update the volume of the unicorn music
                MUSIC:UpdateVolume()
                -- Check if the current music being played is not the unicorn music
                if currentSong ~= MUSIC_INFO.unicornMusic.id then
                    -- Queue the previous song to play after the unicorn music
                    MUSIC:Queue(currentSong)
                end
            end
        end
    end
end

SACRILEGE:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, SACRILEGE.UnicornEffectUpdate)

---Keep the 
function SACRILEGE:UnicornPostUpdate()
    if MUSIC:GetCurrentMusicID() == MUSIC_INFO.unicornMusic.id then
        MUSIC:VolumeSlide(1)
        MUSIC:UpdateVolume()
        MUSIC:PitchSlide(1)
    end
end

SACRILEGE:AddCallback(ModCallbacks.MC_POST_UPDATE, SACRILEGE.UnicornPostUpdate)

function SACRILEGE:UnicornNewRoom()
    if MUSIC:GetCurrentMusicID() == MUSIC_INFO.unicornMusic.id then
        MUSIC:Play(MUSIC:GetQueuedMusicID(), 1)
        MUSIC:UpdateVolume()
    end

    unicornEffects = {}
end

SACRILEGE:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, SACRILEGE.UnicornNewRoom)

--#endregion

--#region Entering Rooms SFX

function SACRILEGE:SFXWhenEnteringRooms()
    ---Play a sound when entering a devil room for the first time
    CallbackWhenEnteringRoom(RoomType.ROOM_DEVIL, function() PlaySFXAlert(SFX_INFO.devilRoomEnter, 0.05) end)
    ---Play a sound when entering a challenge room for the first time
    CallbackWhenEnteringRoom(RoomType.ROOM_CHALLENGE, function() PlaySFXAlertInterupt(SFX_INFO.challengeRoomEnter, function ()
        return not SFX:IsPlaying(SFX_INFO.challengeRoomEnter.id) or Game():GetLevel():GetCurrentRoom():IsAmbushActive()
    end, 0.05) end)
    ---Play a sound when entering a miniboss room when uncleared
    CallbackWhenEnteringUnclearedRoom(RoomType.ROOM_MINIBOSS, function() PlaySFXAlert(SFX_INFO.minibossRoomEnter, 0.05) end)
    ---Play a sound when entering a shop with greed
    CallbackWhenEnteringUnclearedRoom(RoomType.ROOM_SHOP, function() PlaySFXAlert(SFX_INFO.minibossRoomEnter, 0.05) end,
        function(room) return Game():GetLevel():GetCurrentRoomDesc().SurpriseMiniboss end)
    ---Play a sound when entering a secret room with greed
    CallbackWhenEnteringUnclearedRoom(RoomType.ROOM_SECRET, function() PlaySFXAlert(SFX_INFO.minibossRoomEnter, 0.05) end,
        function(room) return Game():GetLevel():GetCurrentRoomDesc().SurpriseMiniboss end)

    CallbackWhenRoomAppears(RunType.OnNewRoom)
end

SACRILEGE:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, SACRILEGE.SFXWhenEnteringRooms)

--#endregion

--#region Rooms Appearing SFX

-- Angel Room Appearing
DoorCallbacks.AngelRoom = {
    type = RoomType.ROOM_ANGEL,
    callback = function() PlaySFX(SFX_INFO.angelRoomAppear) end,
    doorFlag = "angelDoor",
    roomFlag = "angelHasAppeared",
    setting = function() return SoundtrackSongList == nil end,
    runType = RunType.OnRender
}

-- Super secret Room Appearing
DoorCallbacks.SupersecretRoom = {
    type = RoomType.ROOM_SUPERSECRET,
    callback = function() PlaySFXAlert(SFX_INFO.supersecretRoomAppear, 0.05, true) end,
    doorFlag = "supersecretDoor",
    roomFlag = "supersecretHasAppeared",
    trigger = function (self, _, door, prev, curr, seen)
        -- If the door is newly opened and the correct type of door
        local normalApp = door:IsRoomType(self.type) and prev == DoorFlag.Closed and curr == DoorFlag.Open
        -- If the door had to be bombed into/found
        local addApp = not Game():GetLevel():GetCanSeeEverything() and not AnyPlayerHas(CollectibleType.COLLECTIBLE_XRAY_VISION) and not dadsKeyUsedThisFrame
        -- Return if the sound should play
        return not seen and normalApp and addApp
    end,
    setting = function() return true end,
    runType = RunType.OnRender
}

-- Ultra secret Room Appearing
DoorCallbacks.UltrasecretRoom = {
    type = RoomType.ROOM_ULTRASECRET,
    callback = function() PlaySFXAlert(SFX_INFO.ultrasecretRoomAppear, 0.05, true) end,
    doorFlag = "ultrasecretDoor",
    roomFlag = "ultrasecretHasAppeared",
    trigger = function (self, room, door, _, _, _)
        return door:IsRoomType(self.type) and room:IsFirstVisit() and Game():GetLevel():GetRoomByIdx(door.TargetRoomIndex).VisitedCount == 0
    end,
    setting = function() return true end,
    runType = RunType.OnNewRoom
}

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

---Function to track when the effect of dads key was triggered
function SACRILEGE:DadsKeyUsage()
    dadsKeyUsedThisFrame = true
    QUEUE:AddItem(1, 0, function() dadsKeyUsedThisFrame = false end, QUEUE.UpdateType.Update)
end

SACRILEGE:AddCallback(ModCallbacks.MC_USE_ITEM, SACRILEGE.DadsKeyUsage, CollectibleType.COLLECTIBLE_DADS_KEY)

--#endregion