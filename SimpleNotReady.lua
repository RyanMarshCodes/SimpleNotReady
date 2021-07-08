local optionsMenu = nil
local prevpos = false

local char_to_hex = function(c)
    return string.format("%%%02X", string.byte(c))
end

local function urlencode(url)
    if url == nil then
        return
    end
    url = url:gsub("\n", "\r\n")
    url = url:gsub("([^%w ])", char_to_hex)
    url = url:gsub(" ", "+")
    return url
end

local hex_to_char = function(x)
    return string.char(tonumber(x, 16))
end

local urldecode = function(url)
    if url == nil then
        return
    end
    url = url:gsub("+", " ")
    url = url:gsub("%%(%x%x)", hex_to_char)
    return url
end

local function getSpells()
    local tblSpells = {}
    for i = 2, GetNumSpellTabs() do
        local name, texture, offset, numSpells = GetSpellTabInfo(i)
        if not name then
            break
        end

        local newGroup = {}
        newGroup.type = "group"
        newGroup.name = name
        newGroup.args = {}

        for s = offset + 1, offset + numSpells do
            local spell, _ = GetSpellBookItemName(s, BOOKTYPE_SPELL)
            if (spell ~= nil) then
                local spellName, _, _, _, _, _, spellId = GetSpellInfo(spell)

                if (spellName ~= nil and spellId ~= nil) then
                    local newSpellObj = {}
                    newSpellObj.name = spellName
                    newSpellObj.type = "toggle"
                    newSpellObj.set = function(_, val)
                        IgnoredSpellsList[tostring(spellId)] = val
                    end
                    newSpellObj.get = function(_)
                        return IgnoredSpellsList[tostring(spellId)]
                    end

                    newGroup.args[tostring(spellId)] = newSpellObj
                end
            end
        end

        tblSpells[newGroup.name] = newGroup
    end

    return tblSpells
end

local function getConfig(info)
    -- options frame
    local snrOptionsTable = {
        type = "group",
        args = {
            includeEquippedItems = {
                name = "Include Equipped Items",
                type = "toggle",
                desc = "Useful for trinket cooldowns/on-use items",
                set = function(info, val)
                    IncludeEquippedItems = val
                end,
                get = function(info)
                    return IncludeEquippedItems
                end
            },
            declineReadyCheck = {
                name = "Auto-decline Ready Check",
                type = "toggle",
                desc = "Automatically decline ready check if spell is on cooldown",
                set = function(info, val)
                    AutoDeclineReadyCheck = val
                end,
                get = function(info)
                    return AutoDeclineReadyCheck
                end
            },
            chatChannel = {
                name = "Chat Channel to Announce To",
                desc = "GROUP will output to raid if you're in a raid group\r\nPARTY will only output to party",
                type = "select",
                width = "double",
                order = 1,
                values = {
                    ["SAY"] = "SAY",
                    ["YELL"] = "YELL",
                    ["GROUP"] = "GROUP",
                    ["PARTY"] = "PARTY"
                },
                set = function(_, val)
                    NotReadyChatChannel = val
                end,
                get = function(_)
                    return NotReadyChatChannel
                end
            },
            chatMessage = {
                name = "Chat Message",
                type = "input",
                desc = "Usable variables: [[Remaining]], [[SpellLink]]\r\n\r\nNote: Automated messages to SAY or YELL are disabled outside of instances",
                width = "double",
                order = 2,
                set = function(_, val)
                    NotReadyText = urlencode(val)
                end,
                get = function(_)
                    return urldecode(NotReadyText)
                end
            },
            ignoredSpells = {
                name = "Ignore Spells",
                type = "group",
                args = getSpells()
            }
        }
    }

    return snrOptionsTable
end

SLASH_SNR1, SLASH_SNR2 = "/snr", "/simplenotready"
local function handler(msg, editBox)
    if (InterfaceOptionsFrame:IsShown()) then
        InterfaceOptionsFrame_Show()
    else
        InterfaceOptionsFrame_OpenToCategory(optionsMenu)
    end
end
SlashCmdList["SNR"] = handler

local frMain = CreateFrame("ScrollFrame", "SimpleNotReadyFrame", UIParent)
frMain:RegisterEvent("ADDON_LOADED")
frMain:RegisterEvent("READY_CHECK")
frMain:RegisterEvent("PLAYER_LOGOUT")

frMain:SetScript(
    "OnEvent",
    function(self, event, ...)
        if (event == "ADDON_LOADED") and select(1, ...) == "SimpleNotReady" then
            -- do stuff on init?
            if IgnoredSpellsList == nil then
                IgnoredSpellsList = {}
            end

            if NotReadyText == nil then
                NotReadyText = "Need [[Remaining]] seconds for [[SpellLink]]"
            end

            if NotReadyChatChannel == nil then
                NotReadyChatChannel = "SAY"
            end

            if AutoDeclineReadyCheck == nil then
                AutoDeclineReadyCheck = false
            end

            if IncludeEquippedItems == nil then
                IncludeEquippedItems = false
            end

            -- add to WoW Interface Options
            LibStub("AceConfigRegistry-3.0"):RegisterOptionsTable("SimpleNotReady", getConfig)
            optionsMenu = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("SimpleNotReady", "SimpleNotReady")
        elseif (event == "PLAYER_ENTERING_WORLD") or (event == "PLAYER_TALENT_UPDATE") then
            -- update spells in ignore list...
        elseif (event == "READY_CHECK") then
            local longestCDLink = nil
            local longestCDDuration = 0

            -- Check spells
            for i = 2, MAX_SKILLLINE_TABS do
                local name, texture, offset, numSpells = GetSpellTabInfo(i)

                if not name then
                    break
                end

                for s = offset + 1, offset + numSpells do
                    local spell, rank = GetSpellBookItemName(s, BOOKTYPE_SPELL)

                    local spellName, _, _, _, _, _, spellId = GetSpellInfo(spell)

                    if
                        spell ~= nil and
                            (IgnoredSpellsList[tostring(spellId)] == nil or not IgnoredSpellsList[tostring(spellId)])
                     then
                        local cdStart, cdDuration, cdEnabled = GetSpellCooldown(spell)

                        if (cdStart ~= nil and cdStart > 0) and (cdDuration ~= nil and cdDuration > 0) then
                            local remainingTime = cdStart + cdDuration - GetTime()

                            if (remainingTime > longestCDDuration) then
                                longestCDLink = select(1, GetSpellLink(spellId))
                                longestCDDuration = math.ceil(remainingTime)
                            end
                        end
                    end
                end
            end

            -- Check items
            if (IncludeEquippedItems) then
                for i = 1, 15 do
                    local itemId = GetInventoryItemLink("player", i)
                    if itemId then
                        local name, _, quality, ilvl = GetItemInfo(itemId)
                        local itemLink = GetInventoryItemLink("player", i)
                        local start, duration, enable = GetInventoryItemCooldown("player", i)

                        if (start ~= nil and start > 0) and (duration ~= nil and duration > 0) then
                            local remainingTime = start + duration - GetTime()

                            if (remainingTime > longestCDDuration) then
                                longestCDLink = itemLink
                                longestCDDuration = math.ceil(remainingTime)
                            end
                        end
                    end
                end
            end

            if (longestCDLink) then
                local msgType = NotReadyChatChannel

                if (msgType == "SAY" or msgType == "YELL") and not IsInInstance() then
                    print("Unable to send message to Say/Yell outside of instances")
                    return
                end

                -- This is kinda wonky
                if (msgType == "GROUP") and (IsInRaid()) then
                    msgType = "RAID"
                end
                
                if (msgType == "GROUP") and ((not IsInRaid()) and IsInGroup()) then
                    msgType = "PARTY"
                end

                -- One last check
                if (msgType == "GROUP" or msgType == "PARTY") and not IsInGroup() then
                    print("Unable to send message to group: You are not currently in a group")
                    return
                end

                local chatMessage = urldecode(NotReadyText)
                chatMessage, _ = chatMessage:gsub("%[%[Remaining%]%]", tostring(longestCDDuration))
                chatMessage, _ = chatMessage:gsub("%[%[SpellLink%]%]", longestCDLink)

                SendChatMessage(chatMessage, msgType)

                if AutoDeclineReadyCheck then
                    ConfirmReadyCheck(nil)
                end
            end
        end
    end
)
