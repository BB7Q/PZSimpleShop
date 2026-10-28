-- SimpleShop 服务器端主文件
-- 防止在客户端加载此文件
if isClient() then return end

require "SimpleShopBasic"
require "SimpleShopItemStore"

SimpleShopServer = {}
SimpleShopServer.Commands = {}

-- **************************************************************************************
-- 解析当前生效的金额设置：沙箱选项 > SimpleShopBasic 旧字段 > 内置默认
--   沙箱选项定义见 common/media/sandbox-options.txt（世界级，联机时服务端权威）
--   旧配置模组可能整体覆盖 SimpleShopBasic（连辅助函数一起丢掉），这里直接读沙箱 + 兜底
-- **************************************************************************************
local function getSandboxNumber(name)
    if type(SandboxVars) ~= "table" then return nil end
    local page = SandboxVars["SimpleShop"]
    if type(page) ~= "table" then return nil end
    return tonumber(page[name])
end

local function resolveSetting(sandboxName, getterName, fieldName, defaultValue)
    local value = getSandboxNumber(sandboxName)
    if value == nil and type(SimpleShopBasic) == "table" and type(SimpleShopBasic[getterName]) == "function" then
        return SimpleShopBasic[getterName]()
    end
    if value == nil and type(SimpleShopBasic) == "table" then
        value = tonumber(SimpleShopBasic[fieldName])
    end
    if value == nil then return defaultValue end
    return math.max(0, math.floor(value))
end

-- 新角色初始金钱（沙箱 SimpleShop.InitialMoney，默认 0）
SimpleShopServer.GetInitialMoney = function()
    return resolveSetting("InitialMoney", "getInitialMoney", "initialMoney", 0)
end

-- 每击杀一只僵尸的奖励（沙箱 SimpleShop.KillReward，默认 10）
SimpleShopServer.GetKillReward = function()
    return resolveSetting("KillReward", "getKillReward", "zombieKillAmount", 10)
end

-- 调试：检查生效设置
print("[SimpleShop] Server module loading...")
print("[SimpleShop] Initial money for new characters = " .. tostring(SimpleShopServer.GetInitialMoney()))
print("[SimpleShop] Kill reward per zombie = " .. tostring(SimpleShopServer.GetKillReward()))

-- **************************************************************************************
-- 初始化玩家金钱数据（服务端）
-- @param playerObj 玩家对象
-- **************************************************************************************
SimpleShopServer.InitPlayerMoney = function(playerObj)
    if not playerObj then return end
    
    local modData = playerObj:getModData()
    
    -- 如果玩家还没有金钱数据，按沙箱选项初始化
    if not modData.playerMoney then
        local initialMoney = SimpleShopServer.GetInitialMoney()
        modData.playerMoney = initialMoney
        print("[SimpleShop] Initialized player money for " .. tostring(playerObj:getUsername()) .. ": " .. modData.playerMoney)
    else
        print("[SimpleShop] Player " .. tostring(playerObj:getUsername()) .. " already has money: " .. modData.playerMoney)
    end
end

-- **************************************************************************************
-- 僵尸击杀奖励（服务端结算）
--   口径：直接看玩家自己的击杀计数 getZombieKills() 的增量，游戏统计到的每一次击杀都算。
--   早期实现挂在武器事件上，只能覆盖近战，远距离击杀不加钱：
--     · OnWeaponHitXp           只在近战碰撞（CombatManager.attackCollisionCheck）与网络 WeaponHit 里触发
--     · OnPlayerAttackFinished  只在近战挥击状态结束时（SwipeStatePlayer.exit）触发
--   枪械、投掷等远程击杀不经过这两个事件，因此拿不到奖励；击杀计数是引擎维护的，
--   枪械/近战/车辆等所有来源都会累加，按增量发钱即可覆盖全部击杀方式。
-- **************************************************************************************
SimpleShopServer.KILL_CHECK_TICKS = 15;   -- 每 15 tick 检查一次（约 0.5 秒），避免每帧扫玩家
SimpleShopServer.killCheckTicks = 0;

-- **************************************************************************************
-- 读取玩家累计击杀数（异常/取不到值时返回 0，不影响其它逻辑）
-- **************************************************************************************
SimpleShopServer.GetZombieKills = function(playerObj)
    if not playerObj then return 0 end
    local ok, kills = pcall(function() return playerObj:getZombieKills() end)
    if not ok or not kills then return 0 end
    return math.floor(kills)
end

-- **************************************************************************************
-- 是否为旧版客户端脚本（旧版客户端自己在 OnPlayerAttackFinished 里发钱）
--   客户端脚本只在游戏启动时加载，服务端脚本在进入世界时加载：
--   改了脚本但只重开存档、没完整重启游戏时，就会出现"新服务端 + 旧客户端"混跑，
--   一次击杀被服务端和客户端各发一次，表现为双倍钱。
--   单人/主机模式下客户端与服务端共用一份 Lua 状态，可以在这里直接看到客户端全局；
--   联机专用服务器上没有客户端模块（SimpleShop 为 nil），不受影响。
-- **************************************************************************************
SimpleShopServer.HasLegacyClientReward = function()
    return type(SimpleShop) == "table" and SimpleShop.onPlayerAttackFinished ~= nil
end

-- **************************************************************************************
-- 检查所有在线玩家的击杀增量并结算奖励
--   单人/主机模式由同一份服务端逻辑处理；联机时结算后通过 updateMoney 通知客户端
-- **************************************************************************************
SimpleShopServer.CheckKillRewards = function()
    -- 旧版客户端会自己发钱，服务端让位，避免同一只僵尸发两次奖励
    if SimpleShopServer.HasLegacyClientReward() then
        if not SimpleShopServer.warnedLegacyClient then
            SimpleShopServer.warnedLegacyClient = true
            print("[SimpleShop] WARNING: detected legacy client kill-reward code, server reward skipped to avoid double pay. Please fully restart the game to load the new scripts.")
        end
        return
    end

    local rewardPerKill = SimpleShopServer.GetKillReward()

    -- 单个玩家结算：只处理"比上次结算时多出来的击杀数"，重复调用不会有副作用
    local function checkPlayer(playerObj)
        if not playerObj or not playerObj:isAlive() then return end

        local modData = playerObj:getModData()
        local kills = SimpleShopServer.GetZombieKills(playerObj)

        -- 首次记录该角色时只建立基线：之前（读档/加入服务器前）的击杀不补发
        if modData.playerKillsPaid == nil then
            modData.playerKillsPaid = kills
        end
        if modData.playerMoney == nil then
            SimpleShopServer.InitPlayerMoney(playerObj)
        end

        local paid = modData.playerKillsPaid
        if kills > paid then
            modData.playerKillsPaid = kills
            local newKills = kills - paid
            local reward = newKills * rewardPerKill
            if reward > 0 then
                local oldMoney = modData.playerMoney or 0
                modData.playerMoney = oldMoney + reward

                print("[SimpleShop] Player " .. tostring(playerObj:getUsername()) .. " killed " .. tostring(newKills)
                    .. " zombie(s), rewarded " .. tostring(reward) .. " money. Old: " .. tostring(oldMoney)
                    .. " -> New: " .. tostring(modData.playerMoney))

                -- 通知客户端金钱更新（带击杀提示）
                sendServerCommand(playerObj, "SimpleShop", "updateMoney", {
                    money = modData.playerMoney,
                    killReward = true,
                    amount = reward,
                    kills = newKills
                })
            end
        elseif kills < paid then
            -- 击杀数被重置（读档回退/新角色），重新对齐基线，避免把差值当成一批新击杀
            modData.playerKillsPaid = kills
        end
    end

    -- 联机（含主机模式）：在线玩家列表是权威来源
    local players = getOnlinePlayers and getOnlinePlayers()
    if players then
        for i = 0, players:size() - 1 do
            checkPlayer(players:get(i))
        end
    end

    -- 单人模式/分屏：在线列表可能为空，用本地玩家列表兜底（重复结算同一玩家是无害的）
    local numPlayers = getNumActivePlayers and getNumActivePlayers() or 0
    for i = 0, numPlayers - 1 do
        checkPlayer(getSpecificPlayer(i))
    end
end

-- **************************************************************************************
-- 处理购买请求的服务器命令
-- @param playerObj 玩家对象
-- @param args 参数表 {itemType, quantity, totalCost}
-- **************************************************************************************
SimpleShopServer.Commands.Purchase = function(playerObj, args)
    if not playerObj or not args or not args.itemType then
        print("[SimpleShop] Invalid purchase request from client")
        return
    end

    local quantity = math.floor(tonumber(args.quantity) or 0)
    if quantity <= 0 then
        print("[SimpleShop] Invalid purchase quantity from client")
        return
    end

    -- 价格以服务端价格表为准（忽略客户端传来的金额，防止篡改）
    local unitCost = SimpleShopItemStore.getPrice(args.itemType)
    if unitCost == nil then
        print("[SimpleShop] Item not for sale: " .. tostring(args.itemType))
        sendServerCommand(playerObj, "SimpleShop", "purchaseFailed", {reason = "not_for_sale"})
        return
    end
    local totalCost = unitCost * quantity

    -- 确保玩家金钱已初始化
    SimpleShopServer.InitPlayerMoney(playerObj)

    local modData = playerObj:getModData()

    -- 验证玩家是否有足够金钱
    local currentMoney = modData.playerMoney or 0
    if currentMoney < totalCost then
        print("[SimpleShop] Player " .. tostring(playerObj:getUsername()) .. " has insufficient funds: " .. currentMoney .. " < " .. totalCost)
        sendServerCommand(playerObj, "SimpleShop", "purchaseFailed", {reason = "insufficient_funds"})
        return
    end

    -- 扣除金钱
    modData.playerMoney = currentMoney - totalCost
    
    -- 添加物品到玩家背包
    local inventory = playerObj:getInventory()
    local addedCount = 0
    
    -- 逐个添加物品并同步到客户端
    for i = 1, quantity do
        local item = inventory:AddItem(args.itemType)
        if item then
            -- 同步物品到客户端
            sendAddItemToContainer(inventory, item)
            addedCount = addedCount + 1
        else
            print("[SimpleShop] Failed to add item " .. tostring(i) .. " of " .. tostring(quantity))
        end
    end
    
    -- 标记背包为脏，需要更新
    inventory:setDrawDirty(true)
    
    if addedCount == quantity then
        print("[SimpleShop] Player " .. tostring(playerObj:getUsername()) .. " purchased " .. tostring(quantity) .. "x " .. tostring(args.itemType))
        
        -- 发送成功消息回客户端
        sendServerCommand(playerObj, "SimpleShop", "purchaseSuccess", {
            itemType = args.itemType,
            quantity = quantity,
            totalCost = totalCost,
            unitCost = unitCost,
            newMoney = modData.playerMoney
        })
    else
        print("[SimpleShop] Failed to add items for player " .. tostring(playerObj:getUsername()) .. " (added " .. addedCount .. "/" .. quantity .. ")")
        -- 退款
        modData.playerMoney = currentMoney
        sendServerCommand(playerObj, "SimpleShop", "purchaseFailed", {reason = "item_add_failed"})
    end
end

-- **************************************************************************************
-- 处理查询玩家金钱的请求
-- @param playerObj 玩家对象
-- **************************************************************************************
SimpleShopServer.Commands.RequestMoney = function(playerObj, args)
    if not playerObj then return end
    
    local modData = playerObj:getModData()
    local currentMoney = modData.playerMoney or 0
    
    sendServerCommand(playerObj, "SimpleShop", "updateMoney", {
        money = currentMoney
    })
end

-- **************************************************************************************
-- 是否有权限编辑商品价格
-- 单人/主机（isServer() 为 false）直接放行；专用服务器要求管理员/协管
-- **************************************************************************************
SimpleShopServer.CanManageItems = function(playerObj)
    if not isServer() then return true end
    -- 沙箱选项"允许配置商品"是权威开关：关掉后即使有管理员权限也不接受任何改价请求
    if not SimpleShopItemStore.getSandboxOption("AllowManageItems", false) then return false end
    if not playerObj then return false end
    local level = playerObj:getAccessLevel()
    return level == "admin" or level == "moderator" or level == "overseer" or level == "gm"
end

-- **************************************************************************************
-- 价格表快照（复制一份，避免把内部表直接塞进网络包）
-- **************************************************************************************
local function snapshotPrices()
    local result = {}
    for fullType, cost in pairs(SimpleShopItemStore.getPrices() or {}) do
        result[fullType] = cost
    end
    return result
end

-- **************************************************************************************
-- 陈列顺序快照（同样复制一份，数组元素是字符串）
-- **************************************************************************************
local function snapshotOrder()
    local result = {}
    for index, fullType in ipairs(SimpleShopItemStore.getOrder() or {}) do
        result[index] = fullType
    end
    return result
end

-- **************************************************************************************
-- 下发价格表与陈列顺序：playerObj 为 nil 时广播给所有客户端
-- 这是 Global ModData 同步之外的第二条通道，保证客户端一定能拿到最新状态
-- **************************************************************************************
SimpleShopServer.SendPrices = function(playerObj)
    local args = { prices = snapshotPrices(), order = snapshotOrder() }
    if playerObj then
        sendServerCommand(playerObj, "SimpleShop", "pricesUpdated", args)
    else
        sendServerCommand("SimpleShop", "pricesUpdated", args)
    end
end

-- **************************************************************************************
-- 客户端请求同步商品价格表
-- **************************************************************************************
SimpleShopServer.Commands.RequestPrices = function(playerObj, args)
    if not playerObj then return end
    ModData.transmit(SimpleShopItemStore.KEY)
    SimpleShopServer.SendPrices(playerObj)
end

-- **************************************************************************************
-- 上架/修改商品价格
-- **************************************************************************************
SimpleShopServer.Commands.SetItemPrice = function(playerObj, args)
    if not playerObj or not args or not args.itemType then return end
    if not SimpleShopServer.CanManageItems(playerObj) then
        sendServerCommand(playerObj, "SimpleShop", "priceChangeRejected", {reason = "no_permission"})
        return
    end

    local cost = SimpleShopItemStore.sanitizePrice(args.cost)
    if not cost then
        sendServerCommand(playerObj, "SimpleShop", "priceChangeRejected", {reason = "invalid_price"})
        return
    end

    print("[SimpleShop] " .. tostring(playerObj:getUsername()) .. " set price: " .. tostring(args.itemType) .. " = " .. tostring(cost))
    SimpleShopItemStore.setPrice(args.itemType, cost)
    SimpleShopServer.SendPrices()
end

-- **************************************************************************************
-- 下架商品
-- **************************************************************************************
SimpleShopServer.Commands.RemoveItemPrice = function(playerObj, args)
    if not playerObj or not args or not args.itemType then return end
    if not SimpleShopServer.CanManageItems(playerObj) then
        sendServerCommand(playerObj, "SimpleShop", "priceChangeRejected", {reason = "no_permission"})
        return
    end

    print("[SimpleShop] " .. tostring(playerObj:getUsername()) .. " removed item: " .. tostring(args.itemType))
    SimpleShopItemStore.removePrice(args.itemType)
    SimpleShopServer.SendPrices()
end

-- **************************************************************************************
-- 调整商品陈列顺序（上移/下移）
-- **************************************************************************************
SimpleShopServer.Commands.MoveItemOrder = function(playerObj, args)
    if not playerObj or not args or not args.itemType then return end
    if not SimpleShopServer.CanManageItems(playerObj) then
        sendServerCommand(playerObj, "SimpleShop", "priceChangeRejected", {reason = "no_permission"})
        return
    end

    local delta = math.floor(tonumber(args.delta) or 0)
    if delta == 0 then return end

    if not SimpleShopItemStore.hasPrice(args.itemType) then
        sendServerCommand(playerObj, "SimpleShop", "priceChangeRejected", {reason = "not_listed"})
        return
    end

    print("[SimpleShop] " .. tostring(playerObj:getUsername()) .. " moved item: " .. tostring(args.itemType)
        .. " by " .. tostring(delta))
    SimpleShopItemStore.moveOrder(args.itemType, delta)
    SimpleShopServer.SendPrices()
end

-- **************************************************************************************
-- 恢复默认商品清单
-- **************************************************************************************
SimpleShopServer.Commands.ResetItemPrices = function(playerObj, args)
    if not playerObj then return end
    if not SimpleShopServer.CanManageItems(playerObj) then
        sendServerCommand(playerObj, "SimpleShop", "priceChangeRejected", {reason = "no_permission"})
        return
    end

    print("[SimpleShop] " .. tostring(playerObj:getUsername()) .. " reset item prices to default")
    SimpleShopItemStore.resetToDefault()
    SimpleShopServer.SendPrices()
end

-- **************************************************************************************
-- 当玩家连接到服务器时初始化
-- **************************************************************************************
local function onConnected(playerObj)
    if not playerObj then return end
    SimpleShopServer.InitPlayerMoney(playerObj)
end

-- **************************************************************************************
-- 注册服务器命令处理器
-- **************************************************************************************
local function onClientCommand(module, command, playerObj, args)
    if module == "SimpleShop" and SimpleShopServer.Commands[command] then
        SimpleShopServer.Commands[command](playerObj, args)
    end
end

-- 检查事件是否可用
print("[SimpleShop] Events.OnTick available: " .. tostring(Events.OnTick ~= nil))
print("[SimpleShop] Events.OnClientCommand available: " .. tostring(Events.OnClientCommand ~= nil))
print("[SimpleShop] Events.OnConnected available: " .. tostring(Events.OnConnected ~= nil))
print("[SimpleShop] Events.OnServerStarted available: " .. tostring(Events.OnServerStarted ~= nil))

-- 注册事件
if Events.OnClientCommand then
    Events.OnClientCommand.Add(onClientCommand)
    print("[SimpleShop] Registered OnClientCommand")
end

if Events.OnConnected then
    Events.OnConnected.Add(onConnected)
    print("[SimpleShop] Registered OnConnected")
end

-- 击杀奖励：按击杀计数增量结算（每帧触发，内部按 tick 节流）
if Events.OnTick then
    Events.OnTick.Add(function()
        SimpleShopServer.killCheckTicks = SimpleShopServer.killCheckTicks + 1
        if SimpleShopServer.killCheckTicks < SimpleShopServer.KILL_CHECK_TICKS then return end
        SimpleShopServer.killCheckTicks = 0
        SimpleShopServer.CheckKillRewards()
    end)
    print("[SimpleShop] Registered OnTick (kill reward check)")
else
    print("[SimpleShop] ERROR: OnTick event not available, kill rewards will not work!")
end

-- 初始化已在线的玩家（服务器启动时）
local function onServerStarted()
    print("[SimpleShop] Server started, initializing online players...")
    -- 确保商品价格表已初始化（OnInitGlobalModData 未触发时兜底）
    if SimpleShopItemStore and not SimpleShopItemStore.isLoaded then
        SimpleShopItemStore.initialize(false)
    end
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player then
            SimpleShopServer.InitPlayerMoney(player)
        end
    end
end

if Events.OnServerStarted then
    Events.OnServerStarted.Add(onServerStarted)
    print("[SimpleShop] Registered OnServerStarted")
end

print("[SimpleShop] Server module loaded successfully")
