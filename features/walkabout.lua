local Task = require 'utils.task'
local Game = require 'utils.game'
local Event = require 'utils.event'
local Token = require 'utils.token'
local Command = require 'utils.command'

global.walkabout = {}

local function return_player(index)
    local data = global.walkabout[index]
    if not data then
        log('Warning: return_player received nil data')
        return
    end

    local player = Game.get_player_by_index(index)
    if not player or not player.valid then
        log('Warning: return_player received nil or invalid player')
        return
    end

    local walkabout_character = player.character
    if walkabout_character and walkabout_character.valid then
        walkabout_character.destroy()
    end

    local character = data.character
    if character and character.valid then
        player.character = character
    else
        player.create_character()
        player.teleport(data.position)
    end
    player.force = data.force

    game.print(data.player.name .. ' came back from walkabout.')
    global.walkabout[index] = nil
end

--- Returns a player from walkabout after the timeout.
local redmew_commands_return_player =
    Token.register(
    function(player)
        if not player or not player.valid then
            log('Warning: redmew_commands_return_player received nil or invalid player')
            return
        end

        local index = player.index

        -- If the player is no longer connected, store that fact so we can clean them when/if they rejoin.
        if player.connected then
            return_player(index)
        else
            global.walkabout[index].timer_expired = true
        end
    end
)

--- Sends a player on a walkabout:
-- They are teleported far away, placed on a neutral force, and are given a new character.
-- They are returned after the timeout by redmew_commands_return_player
local function walkabout(args)
    local player_name = args.player
    local duration = tonumber(args.duration)

    if not duration then
        Game.player_print('Duration should be a number, player will be sent on walkabout for the default 60 seconds.')
        duration = 60
    end

    if duration < 15 then
        duration = 15
    end

    local player = game.players[player_name]
    if not player or not player.character or global.walkabout[player.index] then
        Game.player_print(player_name .. ' could not go on a walkabout.')
        return
    end

    local surface = player.surface
    local chunk = surface.get_random_chunk()
    local pos = {x = chunk.x * 32, y = chunk.y * 32}
    local non_colliding_pos = surface.find_non_colliding_position('player', pos, 100, 1)

    local character = player.character
    if character and character.valid then
        character.walking_state = {walking = false}
    end

    if non_colliding_pos then
        game.print(player_name .. ' went on a walkabout, to find himself.')

        -- Information about the player's former state so we can restore them later
        local data = {
            player = player,
            force = player.force,
            position = {x = player.position.x, y = player.position.y},
            character = character
        }

        Task.set_timeout(duration, redmew_commands_return_player, player)
        global.walkabout[player.index] = data

        player.character = nil
        player.create_character()
        player.teleport(non_colliding_pos)
        player.force = 'neutral'
    else
        Game.player_print('Walkabout failed: could not find non-colliding-position')
    end
end

--- Cleans the walkabout status off players who disconnected during walkabout.
-- Restores their original force, character, and position.
local function clean_on_join(event)
    local player = Game.get_player_by_index(event.player_index)
    local index = player.index

    -- If a player joins and they're marked as being on walkabout but their timer has expired, restore them.
    if player and global.walkabout[index] and global.walkabout[index].timer_expired then
        return_player(index)
    end
end

Event.add(defines.events.on_player_joined_game, clean_on_join)
Command.add(
    'walkabout',
    {
        description = 'Send someone on a walk. Duration is in seconds.',
        arguments = {'player', 'duration'},
        default_values = {duration = 60},
        admin_only = true,
        allowed_by_server = true
    },
    walkabout
)
