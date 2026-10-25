-- SimpleShop主文件

SimpleShop = {};
-- mod保存数据数组，存储每个玩家如金钱等数据
SimpleShop.modData = {};
-- 玩家UI界面对象数组
SimpleShop.upgradeScreen = {};
-- 玩家商品定价窗口对象数组
SimpleShop.adminScreen = {};
-- 配置内容数组
SimpleShop.settings = {};
-- 玩家临时金钱数组
SimpleShop.playerMoneyTemp = {};
-- 玩家临时死亡次数数组
SimpleShop.playerDeathCountTemp = {};
-- 玩家击杀僵尸数数组
SimpleShop.zombieKills = {};

-- **************************************************************************************
-- 初始化玩家金钱
-- **************************************************************************************
SimpleShop.InitPlayer = function()
	local player = getPlayer();
	local playerIndex = SimpleShop.getCurrentPlayerIndexNum();
	SimpleShop.modData[playerIndex] = player:getModData();

	-- 如果临时玩家金钱和临时玩家死亡次数不为空，说明是死亡后的重新初始化，要将二者数据保存下来
	if SimpleShop.playerMoneyTemp[playerIndex] ~= nil and SimpleShop.playerDeathCountTemp[playerIndex] ~= nil then
		SimpleShop.modData[playerIndex].playerMoney = SimpleShop.playerMoneyTemp[playerIndex];
		SimpleShop.modData[playerIndex].playerDeathCount = SimpleShop.playerDeathCountTemp[playerIndex];
	end

	-- 从modData中读取玩家金钱和玩家死亡次数
	SimpleShop.playerMoneyTemp[playerIndex] = SimpleShop.modData[playerIndex].playerMoney;
	SimpleShop.playerDeathCountTemp[playerIndex] = SimpleShop.modData[playerIndex].playerDeathCount;

	if SimpleShop.playerDeathCountTemp[playerIndex] ~= nil and SimpleShop.playerDeathCountTemp[playerIndex] > 0 then
		-- 当前玩家死亡次数大于0则表示本次初始化是因为玩家死亡才进行的初始化，那么继承死亡前的金币数
		SimpleShop.modData[playerIndex].playerMoney = SimpleShop.playerMoneyTemp[playerIndex];
	else
		-- 刚创建角色的首次初始化
		SimpleShop.modData[playerIndex].playerMoney = SimpleShop.modData[playerIndex].playerMoney or SimpleShop.settings["BASIC"]["initialMoney"];
	end

	-- 从modData中读取玩家僵尸击杀数
	SimpleShop.zombieKills[playerIndex] = player:getZombieKills();
end

-- **************************************************************************************
-- 显示商店UI
-- **************************************************************************************
local function showUpgradeScreen(playerNum)
	if not SimpleShop.upgradeScreen[playerNum] then
		local screenWidth = getPlayerScreenWidth(playerNum);
		local screenHeight = getPlayerScreenHeight(playerNum);
		local windowWidth = 620;
		local windowHeight = 545;
		-- 计算中心位置
		local x = (screenWidth - windowWidth) / 2;
		local y = (screenHeight - windowHeight) / 2;
		-- 初始化UI界面对象
		SimpleShop.upgradeScreen[playerNum] = ISSimpleShop:new(x,y,windowWidth,windowHeight,playerNum, SimpleShop.settings);
		SimpleShop.upgradeScreen[playerNum]:initialise();
		SimpleShop.upgradeScreen[playerNum]:addToUIManager();
		-- 初始化为false，只有为false下面的判断才会setVisible为true
		SimpleShop.upgradeScreen[playerNum]:setVisible(false);
	end
	-- 开关UI界面
	if SimpleShop.upgradeScreen[playerNum]:getIsVisible() then
		SimpleShop.upgradeScreen[playerNum]:setVisible(false);
	else
		SimpleShop.upgradeScreen[playerNum]:setVisible(true);
	end
end



-- **************************************************************************************
-- 是否有权限编辑商品与价格（单人/主机默认允许，联机需要管理员或协管）
-- **************************************************************************************
SimpleShop.CanManageItems = function(playerNum)
	if not isClient() then
		return true;
	end
	if isAdmin and isAdmin() then
		return true;
	end
	local level = getAccessLevel and getAccessLevel() or nil;
	return level == "admin" or level == "moderator" or level == "overseer";
end

-- **************************************************************************************
-- 显示商品定价窗口
-- **************************************************************************************
SimpleShop.showAdminScreen = function(playerNum)
	if not SimpleShop.CanManageItems(playerNum) then
		return;
	end

	require "ISUI/ISSimpleShopAdmin";

	if not SimpleShop.adminScreen[playerNum] then
		local screenWidth = getPlayerScreenWidth(playerNum);
		local screenHeight = getPlayerScreenHeight(playerNum);
		-- 定价窗口内容较多（工具栏 + 列表 + 分页 + 操作栏），给足宽度避免挤压
		local windowWidth = math.min(920, screenWidth - 40);
		local windowHeight = math.min(700, screenHeight - 40);
		local x = (screenWidth - windowWidth) / 2;
		local y = (screenHeight - windowHeight) / 2;
		SimpleShop.adminScreen[playerNum] = ISSimpleShopAdmin:new(x, y, windowWidth, windowHeight, playerNum, SimpleShop.settings);
		SimpleShop.adminScreen[playerNum]:initialise();
		SimpleShop.adminScreen[playerNum]:addToUIManager();
		SimpleShop.adminScreen[playerNum]:setVisible(false);
	end

	SimpleShop.adminScreen[playerNum].needRefresh = true;
	SimpleShop.adminScreen[playerNum]:setVisible(true);
end

-- **************************************************************************************
-- 价格变化后刷新所有已打开的商店窗口
-- **************************************************************************************
SimpleShop.refreshAllShops = function()
	for _, screen in pairs(SimpleShop.upgradeScreen) do
		if screen and screen.refreshDataManager then
			screen:refreshDataManager();
		end
	end
end

-- **************************************************************************************
-- 填充世界对象上下文菜单
-- **************************************************************************************
SimpleShop.doWorldContextMenu = function(playerNum, context, worldobjects)
	local player = getSpecificPlayer(playerNum)
	-- 检查玩家是否存活
	if player:isAlive() then
		-- 添加商店选项到上下文菜单，使用国际化文本
		local option = context:addOption(getText("UI_SimpleShop_OpenShop"), nil, function()
			showUpgradeScreen(playerNum);
		end);
		-- 为选项添加图标
		local iconTexture = getTexture("media/ui/menu_icon.png")
		if iconTexture and option then
			option.iconTexture = iconTexture
			option.icon = nil
		end
		-- 管理员：商品定价入口
		if SimpleShop.CanManageItems(playerNum) then
			local adminOption = context:addOption(getText("UI_SimpleShop_Manage"), nil, function()
				SimpleShop.showAdminScreen(playerNum);
			end);
			if iconTexture and adminOption then
				adminOption.iconTexture = iconTexture
				adminOption.icon = nil
			end
		end
	end
end

-- **************************************************************************************
-- 填充库存对象上下文菜单
-- **************************************************************************************
SimpleShop.doInventoryContextMenu = function(playerNum, context, items)
	local player = getSpecificPlayer(playerNum)
	-- 检查玩家是否存活
	if player:isAlive() then
		-- 添加商店选项到上下文菜单，使用国际化文本
		local option = context:addOption(getText("UI_SimpleShop_OpenShop"), nil, function()
			showUpgradeScreen(playerNum);
		end);
		-- 为选项添加图标
		local iconTexture = getTexture("media/ui/menu_icon.png")
		if iconTexture and option then
			option.iconTexture = iconTexture
			option.icon = nil
		end
		-- 管理员：商品定价入口
		if SimpleShop.CanManageItems(playerNum) then
			local adminOption = context:addOption(getText("UI_SimpleShop_Manage"), nil, function()
				SimpleShop.showAdminScreen(playerNum);
			end);
			if iconTexture and adminOption then
				adminOption.iconTexture = iconTexture
				adminOption.icon = nil
			end
		end
	end
end

-- **************************************************************************************
-- 当玩家攻击结束时触发，判断玩家是否有击杀僵尸，有就加钱
-- **************************************************************************************
SimpleShop.onPlayerAttackFinished = function(player,handWeapon)
	-- 联机模式下，击杀奖励由服务端处理
	if isClient() then
		-- 联机模式：服务端会处理击杀奖励和金钱增加
		return
	end
	
	-- 单人模式或主机模式：本地处理
	local playerIndex = SimpleShop.getCurrentPlayerIndexNum();
	local playerNewKills = player:getZombieKills();
	local newCount = playerNewKills - SimpleShop.zombieKills[playerIndex];
	if playerNewKills > SimpleShop.zombieKills[playerIndex] then
		-- 说明该玩家有新的僵尸击杀，所以要给他加钱，使用新的API函数
		local rewardAmount = math.floor(SimpleShop.settings["BASIC"]["zombieKillAmount"] * newCount);
		SimpleShop.AddPlayerMoney(rewardAmount, playerIndex);
		-- 更新击杀数
		SimpleShop.zombieKills[playerIndex] = playerNewKills;
	end
end

-- **************************************************************************************
-- 加载本地配置
-- **************************************************************************************
SimpleShop.LoadSettings = function()
	-- 将基础设置和商品清单合并为一个设置对象
	SimpleShop.settings = {
		["BASIC"] = SimpleShopBasic,
		["ITEMS"] = SimpleShopItems
	};
end

-- **************************************************************************************
-- 初始化，注册事件
-- **************************************************************************************
SimpleShop.init = function()
	-- 读取本地配置文件
	SimpleShop.LoadSettings(); 
	SimpleShop.InitPlayer();
	-- 确保商品价格表已加载（OnInitGlobalModData 未触发时兜底）
	if SimpleShopItemStore and not SimpleShopItemStore.isLoaded then
		SimpleShopItemStore.initialize(false);
	end
	-- 价格变化后刷新已打开的商店窗口
	if SimpleShopItemStore then
		SimpleShopItemStore.addListener(SimpleShop.refreshAllShops);
	end
	-- 注册上下文菜单事件
	Events.OnFillInventoryObjectContextMenu.Add(SimpleShop.doInventoryContextMenu);
	Events.OnFillWorldObjectContextMenu.Add(SimpleShop.doWorldContextMenu);
	-- 注册僵尸击杀事件
	Events.OnPlayerAttackFinished.Add(SimpleShop.onPlayerAttackFinished);

	-- 加载客户端网络命令模块（联机支持）
	require "SimpleShopClientCommands"
	-- 联机时主动拉取服务端的商品价格表
	if isClient() then
		SimpleShopClientCommands.SendPricesRequest();
	end
end

-- **************************************************************************************
-- 玩家死亡时触发
-- **************************************************************************************
SimpleShop.prepareReInit = function()
	local playerIndex = SimpleShop.getCurrentPlayerIndexNum();
	-- 记录临时玩家金钱
	SimpleShop.playerMoneyTemp[playerIndex] = SimpleShop.modData[playerIndex].playerMoney;
	-- 临时玩家死亡次数加1
	if SimpleShop.playerDeathCountTemp[playerIndex] ~= nil then
		SimpleShop.playerDeathCountTemp[playerIndex] = SimpleShop.playerDeathCountTemp[playerIndex] + 1;
	else
		SimpleShop.playerDeathCountTemp[playerIndex] = 1;
	end
	-- 商店面板要初始化，所以将面板对象置空
	SimpleShop.upgradeScreen[playerIndex] = nil;
	SimpleShop.adminScreen[playerIndex] = nil;
	-- 再次初始化玩家金钱
	Events.OnCreatePlayer.Add(SimpleShop.InitPlayer);
end

-- **************************************************************************************
-- 获取当前玩家索引号
-- return 当前玩家索引号
-- **************************************************************************************
SimpleShop.getCurrentPlayerIndexNum = function()
	local player = getPlayer();
	for i = 0,getNumActivePlayers() - 1 do
		local targetPlayer = getSpecificPlayer(i);
		if (player:getUsername() == targetPlayer:getUsername()) then
			return i;
		end
	end
end

-- **************************************************************************************
-- 货币系统API - 供其他mod调用
-- **************************************************************************************

-- **************************************************************************************
-- 获取玩家当前金额
-- @param playerIndex 玩家索引号，可选参数，默认为当前玩家
-- @return 玩家当前金额，如果玩家不存在返回nil
-- **************************************************************************************
SimpleShop.GetPlayerMoney = function(playerIndex)
    local playerIdx = playerIndex or SimpleShop.getCurrentPlayerIndexNum();
    if not SimpleShop.modData[playerIdx] then return nil; end
    return SimpleShop.modData[playerIdx].playerMoney or 0;
end

-- **************************************************************************************
-- 增加玩家金额
-- @param amount 增加的金额（必须为正数）
-- @param playerIndex 玩家索引号，可选参数，默认为当前玩家
-- @return 是否成功增加金额，如果玩家不存在或金额无效返回false，否则返回true
-- **************************************************************************************
SimpleShop.AddPlayerMoney = function(amount, playerIndex)
    if not amount or amount <= 0 then return false; end
    
    local playerIdx = playerIndex or SimpleShop.getCurrentPlayerIndexNum();
    if not SimpleShop.modData[playerIdx] then return false; end
    
    local currentMoney = SimpleShop.modData[playerIdx].playerMoney or 0;
    SimpleShop.modData[playerIdx].playerMoney = currentMoney + amount;
    return true;
end

-- **************************************************************************************
-- 减少玩家金额
-- @param amount 减少的金额（必须为正数）
-- @param playerIndex 玩家索引号，可选参数，默认为当前玩家
-- @return 是否成功减少金额，如果玩家不存在、金额无效或余额不足返回false，否则返回true
-- **************************************************************************************
SimpleShop.RemovePlayerMoney = function(amount, playerIndex)
    if not amount or amount <= 0 then return false; end
    
    local playerIdx = playerIndex or SimpleShop.getCurrentPlayerIndexNum();
    if not SimpleShop.modData[playerIdx] then return false; end
    
    local currentMoney = SimpleShop.modData[playerIdx].playerMoney or 0;
    if currentMoney < amount then return false; end -- 余额不足
    
    SimpleShop.modData[playerIdx].playerMoney = currentMoney - amount;
    return true;
end

-- **************************************************************************************
-- 检查玩家是否有足够金额
-- @param amount 需要的金额（必须为正数）
-- @param playerIndex 玩家索引号，可选参数，默认为当前玩家
-- @return 玩家是否有足够金额，如果玩家不存在或金额无效返回false
-- **************************************************************************************
SimpleShop.HasEnoughMoney = function(amount, playerIndex)
    if not amount or amount <= 0 then return false; end
    
    local playerIdx = playerIndex or SimpleShop.getCurrentPlayerIndexNum();
    if not SimpleShop.modData[playerIdx] then return false; end
    
    local currentMoney = SimpleShop.modData[playerIdx].playerMoney or 0;
    return currentMoney >= amount;
end

-- **************************************************************************************
-- 注册事件
-- **************************************************************************************
Events.OnGameStart.Add(SimpleShop.init)
Events.OnPlayerDeath.Add(SimpleShop.prepareReInit)