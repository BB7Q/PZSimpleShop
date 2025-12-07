-- SimpleShop主文件

SimpleShop = {};
-- mod保存数据数组，存储每个玩家如金钱等数据
SimpleShop.modData = {};
-- 玩家UI界面对象数组
SimpleShop.upgradeScreen = {};
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
	end
end

-- **************************************************************************************
-- 当玩家攻击结束时触发，判断玩家是否有击杀僵尸，有就加钱
-- **************************************************************************************
SimpleShop.onPlayerAttackFinished = function(player,handWeapon)
	local playerIndex = SimpleShop.getCurrentPlayerIndexNum();
	local playerNewKills = player:getZombieKills();
	local newCount = playerNewKills - SimpleShop.zombieKills[playerIndex];
	if playerNewKills > SimpleShop.zombieKills[playerIndex] then
		-- 说明该玩家有新的僵尸击杀，所以要给他加钱
		SimpleShop.modData[playerIndex].playerMoney = math.floor(SimpleShop.modData[playerIndex].playerMoney + SimpleShop.settings["BASIC"]["zombieKillAmount"] * newCount);
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
	-- 注册上下文菜单事件
	Events.OnFillInventoryObjectContextMenu.Add(SimpleShop.doInventoryContextMenu);
	Events.OnFillWorldObjectContextMenu.Add(SimpleShop.doWorldContextMenu);
	-- 注册僵尸击杀事件
	Events.OnPlayerAttackFinished.Add(SimpleShop.onPlayerAttackFinished);
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
-- 注册事件
-- **************************************************************************************
Events.OnGameStart.Add(SimpleShop.init)
Events.OnPlayerDeath.Add(SimpleShop.prepareReInit)