-- SimpleShop 客户端网络命令处理

SimpleShopClientCommands = {}

-- **************************************************************************************
-- 发送购买请求到服务器
-- @param itemType 物品类型
-- @param quantity 购买数量
-- @param totalCost 总花费
-- **************************************************************************************
SimpleShopClientCommands.SendPurchaseRequest = function(itemType, quantity, totalCost)
    -- 检查是否为联机模式
    if not isClient() then
        -- 单人模式或主机模式，直接调用本地逻辑
        return false
    end
    
    local playerObj = getPlayer()
    if not playerObj then return false end
    
    -- 调试信息：显示客户端当前金钱
    local currentMoney = SimpleShop.GetPlayerMoney()
    print("[SimpleShop] Client sending purchase request: " .. tostring(quantity) .. "x " .. tostring(itemType) .. ", cost: " .. tostring(totalCost) .. ", current money: " .. tostring(currentMoney))
    
    sendClientCommand(playerObj, "SimpleShop", "Purchase", {
        itemType = itemType,
        quantity = quantity,
        totalCost = totalCost
    })
    
    return true
end

-- **************************************************************************************
-- 发送查询金钱请求到服务器
-- **************************************************************************************
SimpleShopClientCommands.SendMoneyRequest = function()
    if not isClient() then
        -- 单人模式
        return false
    end
    
    local playerObj = getPlayer()
    if not playerObj then return false end
    
    sendClientCommand(playerObj, "SimpleShop", "RequestMoney", {})
    return true
end

-- **************************************************************************************
-- 处理服务器响应
-- **************************************************************************************
local function onServerCommand(module, command, args)
    if module ~= "SimpleShop" then return end
    
    if command == "purchaseSuccess" then
        -- 购买成功
        print("[SimpleShop] Purchase successful: " .. tostring(args.quantity) .. "x " .. tostring(args.itemType) .. ", new money: " .. tostring(args.newMoney))

        -- 更新本地金钱数据
        local playerIndex = getPlayer():getPlayerNum()
        if SimpleShop.modData[playerIndex] then
            SimpleShop.modData[playerIndex].playerMoney = args.newMoney
        end
        SimpleShop.playerMoneyTemp[playerIndex] = args.newMoney

        -- 更新UI显示
        if SimpleShop.upgradeScreen[playerIndex] and SimpleShop.upgradeScreen[playerIndex].moneyLabel then
            SimpleShop.upgradeScreen[playerIndex].moneyLabel.name = getText("UI_SimpleShop_Money") .. ": " .. tostring(args.newMoney)
        end
        
    elseif command == "purchaseFailed" then
        -- 购买失败
        print("[SimpleShop] Purchase failed: " .. tostring(args.reason))
        
    elseif command == "updateMoney" then
        -- 更新金钱数据和显示
        local playerIndex = getPlayer():getPlayerNum()

        -- 更新本地存储的金钱数据
        if SimpleShop.modData[playerIndex] then
            SimpleShop.modData[playerIndex].playerMoney = args.money
        end
        SimpleShop.playerMoneyTemp[playerIndex] = args.money

        -- 更新UI显示
        if SimpleShop.upgradeScreen[playerIndex] and SimpleShop.upgradeScreen[playerIndex].moneyLabel then
            SimpleShop.upgradeScreen[playerIndex].moneyLabel.name = getText("UI_SimpleShop_Money") .. ": " .. tostring(args.money)
        end

        -- 记录击杀奖励日志（如果有）
        if args.killReward then
            print("[SimpleShop] Kill reward: +" .. tostring(args.amount or 0) .. " money, total: " .. tostring(args.money))
        end
    end
end

Events.OnServerCommand.Add(onServerCommand)

print("[SimpleShop] Client commands module loaded")
