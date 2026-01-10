-- SimpleShop 服务器端主文件
-- 防止在客户端加载此文件
if isClient() then return end

require "SimpleShopBasic"

SimpleShopServer = {}
SimpleShopServer.Commands = {}

-- 调试：检查配置文件是否加载
print("[SimpleShop] Server module loading...")
print("[SimpleShop] SimpleShopBasic.initialMoney = " .. tostring(SimpleShopBasic.initialMoney))
print("[SimpleShop] SimpleShopBasic.zombieKillAmount = " .. tostring(SimpleShopBasic.zombieKillAmount))

-- **************************************************************************************
-- 初始化玩家金钱数据（服务端）
-- @param playerObj 玩家对象
-- **************************************************************************************
SimpleShopServer.InitPlayerMoney = function(playerObj)
    if not playerObj then return end
    
    local modData = playerObj:getModData()
    
    -- 如果玩家还没有金钱数据，从配置文件初始化
    if not modData.playerMoney then
        local initialMoney = SimpleShopBasic and SimpleShopBasic.initialMoney or 100
        modData.playerMoney = initialMoney
        print("[SimpleShop] Initialized player money for " .. tostring(playerObj:getUsername()) .. ": " .. modData.playerMoney)
    else
        print("[SimpleShop] Player " .. tostring(playerObj:getUsername()) .. " already has money: " .. modData.playerMoney)
    end
end

-- **************************************************************************************
-- 当玩家击中僵尸时触发（只在服务端执行）
-- @param owner 攻击者（玩家）
-- @param weapon 武器
-- @param hitObject 被击中的对象（僵尸）
-- @param damage 伤害
-- @param hitCount 命中次数
-- **************************************************************************************
SimpleShopServer.OnWeaponHitXp = function(owner, weapon, hitObject, damage, hitCount)
    print("[SimpleShop] OnWeaponHitXp triggered - hitObject: " .. tostring(hitObject))

    -- 安全检查 owner
    if not owner then
        print("[SimpleShop] owner is nil")
        return
    end

    -- 安全检查 hitObject
    if not hitObject then
        print("[SimpleShop] hitObject is nil")
        return
    end

    -- 检查是否击中了僵尸
    local isZombie = instanceof(hitObject, "IsoZombie")
    print("[SimpleShop] isZombie: " .. tostring(isZombie))
    if not isZombie then return end

    -- 检查僵尸是否已经死亡
    local isDead
    local success, result = pcall(function() return hitObject:isDead() end)
    if success then
        isDead = result
    else
        print("[SimpleShop] Error calling isDead(): " .. tostring(result))
        return
    end

    print("[SimpleShop] isDead: " .. tostring(isDead))
    if not isDead then return end

    -- 获取击杀者（僵尸的攻击者）
    local killer
    success, result = pcall(function() return hitObject:getAttackedBy() end)
    if success then
        killer = result
    else
        print("[SimpleShop] Error calling getAttackedBy(): " .. tostring(result))
        return
    end

    print("[SimpleShop] getAttackedBy() returned: " .. tostring(killer))

    -- 如果击杀者是 nil，直接使用 owner（因为 OnWeaponHitXp 的 owner 就是攻击者）
    if not killer then
        print("[SimpleShop] killer is nil, using owner as killer")
        killer = owner
    end

    -- 检查击杀者是否是当前玩家
    local isKillerOwner = killer == owner
    print("[SimpleShop] killer == owner: " .. tostring(isKillerOwner))
    if not isKillerOwner then
        print("[SimpleShop] killer is not the same as owner, skipping")
        return
    end

    local playerObj = owner
    print("[SimpleShop] All checks passed, will reward money")

    -- 确保金钱已初始化
    SimpleShopServer.InitPlayerMoney(playerObj)

    -- 计算奖励
    local rewardAmount = SimpleShopBasic.zombieKillAmount or 10

    -- 增加金钱
    local modData = playerObj:getModData()
    local oldMoney = modData.playerMoney or 0
    modData.playerMoney = oldMoney + rewardAmount

    print("[SimpleShop] Player " .. tostring(playerObj:getUsername()) .. " killed a zombie, rewarded " .. rewardAmount .. " money. Old: " .. oldMoney .. " -> New: " .. modData.playerMoney)

    -- 通知客户端金钱更新（带击杀提示）
    sendServerCommand(playerObj, "SimpleShop", "updateMoney", {
        money = modData.playerMoney,
        killReward = true,
        amount = rewardAmount
    })
end

-- **************************************************************************************
-- 处理购买请求的服务器命令
-- @param playerObj 玩家对象
-- @param args 参数表 {itemType, quantity, totalCost}
-- **************************************************************************************
SimpleShopServer.Commands.Purchase = function(playerObj, args)
    if not playerObj or not args or not args.itemType or args.quantity <= 0 or args.totalCost < 0 then
        print("[SimpleShop] Invalid purchase request from client")
        return
    end
    
    -- 确保玩家金钱已初始化
    SimpleShopServer.InitPlayerMoney(playerObj)
    
    local modData = playerObj:getModData()
    
    -- 验证玩家是否有足够金钱
    local currentMoney = modData.playerMoney or 0
    if currentMoney < args.totalCost then
        print("[SimpleShop] Player " .. tostring(playerObj:getUsername()) .. " has insufficient funds: " .. currentMoney .. " < " .. args.totalCost)
        sendServerCommand(playerObj, "SimpleShop", "purchaseFailed", {reason = "insufficient_funds"})
        return
    end
    
    -- 扣除金钱
    modData.playerMoney = currentMoney - args.totalCost
    
    -- 添加物品到玩家背包
    local inventory = playerObj:getInventory()
    local addedCount = 0
    
    -- 逐个添加物品并同步到客户端
    for i = 1, args.quantity do
        local item = inventory:AddItem(args.itemType)
        if item then
            -- 同步物品到客户端
            sendAddItemToContainer(inventory, item)
            addedCount = addedCount + 1
        else
            print("[SimpleShop] Failed to add item " .. tostring(i) .. " of " .. tostring(args.quantity))
        end
    end
    
    -- 标记背包为脏，需要更新
    inventory:setDrawDirty(true)
    
    if addedCount == args.quantity then
        print("[SimpleShop] Player " .. tostring(playerObj:getUsername()) .. " purchased " .. tostring(args.quantity) .. "x " .. tostring(args.itemType))
        
        -- 发送成功消息回客户端
        sendServerCommand(playerObj, "SimpleShop", "purchaseSuccess", {
            itemType = args.itemType,
            quantity = args.quantity,
            totalCost = args.totalCost,
            newMoney = modData.playerMoney
        })
    else
        print("[SimpleShop] Failed to add items for player " .. tostring(playerObj:getUsername()) .. " (added " .. addedCount .. "/" .. args.quantity .. ")")
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
print("[SimpleShop] Events.OnWeaponHitXp available: " .. tostring(Events.OnWeaponHitXp ~= nil))
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

if Events.OnWeaponHitXp then
    Events.OnWeaponHitXp.Add(SimpleShopServer.OnWeaponHitXp)
    print("[SimpleShop] Registered OnWeaponHitXp")
else
    print("[SimpleShop] ERROR: OnWeaponHitXp event not available!")
end

-- 初始化已在线的玩家（服务器启动时）
local function onServerStarted()
    print("[SimpleShop] Server started, initializing online players...")
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
