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
-- 悬浮余额面板对象（客户端 UI，显示当前金钱，点击打开商店）
SimpleShop.hud = nil;

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
local function createUpgradeScreen(playerNum)
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

-- @return 关闭前窗口是否可见
local function destroyUpgradeScreen(playerNum)
	local screen = SimpleShop.upgradeScreen[playerNum];
	if not screen then return false end
	local wasVisible = screen:getIsVisible() and true or false;
	screen:setVisible(false);
	screen:removeFromUIManager();
	SimpleShop.upgradeScreen[playerNum] = nil;
	return wasVisible;
end

local function showUpgradeScreen(playerNum)
	-- 沙箱/模组配置可能在会话中被改掉：缓存窗口的按钮布局对不上就重建，避免显示过期按钮
	local existing = SimpleShop.upgradeScreen[playerNum];
	if existing and existing.manageAllowed ~= SimpleShop.canShowManageButton(playerNum) then
		destroyUpgradeScreen(playerNum);
	end

	if not SimpleShop.upgradeScreen[playerNum] then
		createUpgradeScreen(playerNum);
	end
	-- 开关UI界面
	if SimpleShop.upgradeScreen[playerNum]:getIsVisible() then
		SimpleShop.upgradeScreen[playerNum]:setVisible(false);
	else
		SimpleShop.upgradeScreen[playerNum]:setVisible(true);
	end
end

-- 配置改完后立即重建已打开的商店窗口：按钮显隐不用关掉窗口再开一次
SimpleShop.rebuildUpgradeScreens = function()
	if not getPlayer() then return end
	local reopened = {};
	for playerNum in pairs(SimpleShop.upgradeScreen or {}) do
		if destroyUpgradeScreen(playerNum) then
			reopened[#reopened + 1] = playerNum;
		end
	end
	for _, playerNum in ipairs(reopened) do
		showUpgradeScreen(playerNum);
	end
end

-- **************************************************************************************
-- 悬浮余额面板：常驻显示当前金钱，点击打开/关闭商店，按住可拖拽
--   默认位置在画面右侧中间；拖动后的位置记在玩家 ModData（随存档保存）
-- **************************************************************************************
-- 默认位置与画面右边缘的间距
SimpleShop.HUD_EDGE_MARGIN = 16;

-- 千分位格式化：1234567 -> "1,234,567"（负数也能正确出符号）
SimpleShop.formatMoney = function(value)
	local number = math.floor(tonumber(value) or 0);
	local sign = "";
	local text = tostring(number);
	if string.sub(text, 1, 1) == "-" then
		sign = "-";
		text = string.sub(text, 2);
	end
	local formatted = string.reverse(string.gsub(string.reverse(text), "(%d%d%d)", "%1,"));
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2);
	end
	return sign .. formatted;
end;

-- 打开/关闭商店窗口（悬浮面板点击时调用）
SimpleShop.toggleShopWindow = function(playerNum)
	if playerNum == nil then return end
	local player = getSpecificPlayer(playerNum);
	if not player or not player:isAlive() then return end
	showUpgradeScreen(playerNum);
end;

-- 创建悬浮面板；位置优先取上次拖拽保存的值，没有就贴右侧居中
SimpleShop.createHud = function(playerNum)
	if playerNum == nil then return end
	require "ISUI/ISSimpleShopHud";

	local hud = ISSimpleShopHud:new(playerNum, 0, 0);

	local player = getSpecificPlayer(playerNum);
	local modData = player and player:getModData() or nil;
	local savedX = modData and tonumber(modData.SimpleShopHudX) or nil;
	local savedY = modData and tonumber(modData.SimpleShopHudY) or nil;

	if savedX and savedY then
		hud:setX(math.floor(savedX));
		hud:setY(math.floor(savedY));
	else
		local screenLeft = getPlayerScreenLeft and getPlayerScreenLeft(playerNum) or 0;
		local screenTop = getPlayerScreenTop and getPlayerScreenTop(playerNum) or 0;
		local screenWidth = getPlayerScreenWidth(playerNum) or 0;
		local screenHeight = getPlayerScreenHeight(playerNum) or 0;
		hud:setX(math.floor(screenLeft + screenWidth - hud.width - SimpleShop.HUD_EDGE_MARGIN));
		hud:setY(math.floor(screenTop + (screenHeight - hud.height) / 2));
	end

	hud:initialise();
	-- 旧分辨率下保存的坐标可能已经出屏，统一收回画面内
	hud:clampToScreen();
	hud:addToUIManager();
	SimpleShop.hud = hud;
	return hud;
end;

SimpleShop.destroyHud = function()
	local hud = SimpleShop.hud;
	SimpleShop.hud = nil;
	if not hud then return end
	hud:setVisible(false);
	hud:removeFromUIManager();
end;

-- 首次进入游戏、以及死亡后重新创建角色时调用（重复调用无副作用）
SimpleShop.initHud = function()
	if not getPlayer() then return end
	if not SimpleShop.getShowHudOption() then return end

	local playerNum = SimpleShop.getCurrentPlayerIndexNum();
	if playerNum == nil then return end
	local player = getSpecificPlayer(playerNum);
	if not player or not player:isAlive() then return end

	-- 已经有一块属于当前玩家的面板就不重建
	if SimpleShop.hud and SimpleShop.hud.playerNum == playerNum and SimpleShop.hud:getIsVisible() then
		return;
	end

	SimpleShop.destroyHud();
	SimpleShop.createHud(playerNum);
end;

-- 模组配置"显示悬浮余额面板"：优先取 onChangeApply 传进来的新值（原生回调早于写回）
SimpleShop.showHudOverride = nil;
SimpleShop.getShowHudOption = function()
	if SimpleShop.showHudOverride ~= nil then
		return SimpleShop.showHudOverride == true;
	end
	return SimpleShop.getModOption("ShowHud", true) == true;
end;

-- 配置改完后立即生效：开就建面板，关就销毁
SimpleShop.applyHudVisibility = function()
	if not getPlayer() then return end
	if SimpleShop.getShowHudOption() then
		SimpleShop.initHud();
	else
		SimpleShop.destroyHud();
	end
end;



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
-- 沙箱配置（世界级）：选项 -> 沙箱选项 -> 简易商店
--   AllowManageItems : 是否允许配置商品（定价/陈列顺序，默认关闭）
--   定义见 common/media/sandbox-options.txt，运行时读取 SandboxVars.SimpleShop.<name>
-- **************************************************************************************
SimpleShop.getSandboxOption = function(name, default)
	if SimpleShopItemStore and SimpleShopItemStore.getSandboxOption then
		return SimpleShopItemStore.getSandboxOption(name, default);
	end
	return default;
end

-- **************************************************************************************
-- 模组配置项（选项 -> 模组 -> 简易商店）：客户端设置，改完即生效
--   ShowHud : 是否显示悬浮余额面板（默认显示）
--   ShowContextMenu : 是否显示"打开商店"右键菜单项（默认关闭）
--   ShowManageButton : 是否在商店窗口里显示"管理商品"按钮（默认关闭）
--   OpenSimpleShop / ManageSimpleShop : 快捷键（默认不绑定）
--   注意：管理按钮是否真的出现还要看沙箱选项"允许配置商品"，两者是与关系
-- **************************************************************************************
SimpleShop.modOptionsId = "SimpleShop";

-- 注册模组配置项；重复调用无副作用
SimpleShop.registerModOptions = function()
	if PZAPI == nil or PZAPI.ModOptions == nil then return end
	if SimpleShop.modOptionsRegistered then return end

	local options = PZAPI.ModOptions:getOptions(SimpleShop.modOptionsId);
	if not options then
		options = PZAPI.ModOptions:create(SimpleShop.modOptionsId, "UI_SimpleShop_ModOptions");
		-- 顶部说明：告诉玩家按钮最终受沙箱开关制约，避免开了却在游戏里找不到按钮
		options:addDescription("UI_SimpleShop_OptHint");
	end

	-- 顺序：入口相关（悬浮面板 / 右键菜单）在前，管理按钮与快捷键在后
	local hudOption = options:getOption("ShowHud");
	if not hudOption then
		hudOption = options:addTickBox("ShowHud",
			"UI_SimpleShop_OptShowHud", true, "UI_SimpleShop_OptShowHud_tt");
		function hudOption.onChangeApply(option, value)
			SimpleShop.showHudOverride = value and true or false;
			SimpleShop.applyHudVisibility();
		end
	end

	local menuOption = options:getOption("ShowContextMenu");
	if not menuOption then
		menuOption = options:addTickBox("ShowContextMenu",
			"UI_SimpleShop_OptShowContextMenu", false, "UI_SimpleShop_OptShowContextMenu_tt");
		function menuOption.onChangeApply(option, value)
			SimpleShop.showContextMenuOverride = value and true or false;
		end
	end

	local showOption = options:getOption("ShowManageButton");
	if not showOption then
		showOption = options:addTickBox("ShowManageButton",
			"UI_SimpleShop_OptShowManageButton", false, "UI_SimpleShop_OptShowManageButton_tt");
		-- 原生 ModOptions 用 option:onChangeApply(新值) 调用，且回调早于写入新值，
		-- 所以先用回调参数落一份覆盖值，重建窗口时读到的就是新状态（改完即生效）
		function showOption.onChangeApply(option, value)
			SimpleShop.showManageButtonOverride = value and true or false;
			SimpleShop.rebuildUpgradeScreens();
		end
	end

	local none = (Keyboard and Keyboard.KEY_NONE) or 0;
	if not options:getOption(SimpleShop.keyBindIds.openShop) then
		options:addKeyBind(SimpleShop.keyBindIds.openShop,
			"UI_SimpleShop_OptOpenKey", none, "UI_SimpleShop_OptOpenKey_tt");
	end
	if not options:getOption(SimpleShop.keyBindIds.manageItems) then
		options:addKeyBind(SimpleShop.keyBindIds.manageItems,
			"UI_SimpleShop_OptManageKey", none, "UI_SimpleShop_OptManageKey_tt");
	end

	SimpleShop.modOptionsRegistered = true;

	-- 立即从 ModOptions.ini 回填上次保存的键位，不必先打开选项页
	pcall(function() PZAPI.ModOptions:load(); end);
end

-- 读取配置项（缺省返回 default）
SimpleShop.getModOption = function(id, default)
	if PZAPI == nil or PZAPI.ModOptions == nil then return default end
	local options = PZAPI.ModOptions:getOptions(SimpleShop.modOptionsId);
	if not options then return default end
	local option = options:getOption(id);
	if not option then return default end
	local value = option:getValue();
	if value == nil then return default end
	return value;
end

-- 是否允许进入商品配置：需要沙箱开关"允许配置商品"开启且有管理权限
SimpleShop.canAccessAdminPanel = function(playerNum)
	if not SimpleShop.getSandboxOption("AllowManageItems", false) then
		return false;
	end
	return SimpleShop.CanManageItems(playerNum);
end

-- 本机"显示管理按钮"开关：优先取 onChangeApply 传进来的新值（原生回调早于写回，避免读到旧值）
SimpleShop.showManageButtonOverride = nil;
SimpleShop.getShowManageButtonOption = function()
	if SimpleShop.showManageButtonOverride ~= nil then
		return SimpleShop.showManageButtonOverride == true;
	end
	return SimpleShop.getModOption("ShowManageButton", false) == true;
end

-- 是否在商店窗口显示"管理商品"按钮：
--   本机模组配置"显示管理按钮"开启 + 沙箱选项"允许配置商品"开启 + 玩家有管理权限，三者都满足
SimpleShop.canShowManageButton = function(playerNum)
	if not SimpleShop.getShowManageButtonOption() then
		return false;
	end
	return SimpleShop.canAccessAdminPanel(playerNum);
end

-- 说明：价格表范围（整个游戏 / 仅本存档）配在沙箱选项「简易商店 → 价格表范围」里，
-- 由 SimpleShopItemStore.getMode() 统一解析，这里不再提供本机开关，避免两处设置互相打架。

-- 本机"显示右键菜单"开关（默认关闭）：开启后世界/物品栏右键里才有"打开商店"
SimpleShop.showContextMenuOverride = nil;
SimpleShop.getShowContextMenuOption = function()
	if SimpleShop.showContextMenuOverride ~= nil then
		return SimpleShop.showContextMenuOverride == true;
	end
	return SimpleShop.getModOption("ShowContextMenu", false) == true;
end

-- **************************************************************************************
-- 显示商品定价窗口
-- **************************************************************************************
SimpleShop.showAdminScreen = function(playerNum)
	if not SimpleShop.canAccessAdminPanel(playerNum) then
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
-- 快捷键（默认不绑定，在 选项 -> 模组 -> 简易商店 里配置）
--   键位由原生 ModOptions 的 keybind 控件维护、存在 ModOptions.ini；
--   这里只负责把玩家设置的值读出来和按键比对（不再往全局 keyBinding 表里插条目）
-- **************************************************************************************
SimpleShop.keyBindIds = {
	openShop = "OpenSimpleShop",
	manageItems = "ManageSimpleShop",
};

-- 读取玩家为某个动作绑定的按键；未绑定返回 nil
SimpleShop.getKeyBind = function(id)
	local key = SimpleShop.getModOption(id, nil);
	if type(key) ~= "number" or key <= 0 then return nil end
	if Keyboard and key == Keyboard.KEY_NONE then return nil end
	return key;
end

-- 快捷键入口：打开商店（需要活着）
SimpleShop.openShopByKey = function()
	if not getPlayer() then return end

	local playerNum = SimpleShop.getCurrentPlayerIndexNum();
	if playerNum == nil then return end
	local player = getSpecificPlayer(playerNum);
	if not player or not player:isAlive() then return end

	showUpgradeScreen(playerNum);
end

-- 快捷键入口：商品定价（内部会校验管理员权限）
SimpleShop.openAdminByKey = function()
	if not getPlayer() then return end

	local playerNum = SimpleShop.getCurrentPlayerIndexNum();
	if playerNum == nil then return end
	local player = getSpecificPlayer(playerNum);
	if not player or not player:isAlive() then return end

	SimpleShop.showAdminScreen(playerNum);
end

-- 聊天框/输入框正在接收键盘输入时不响应快捷键（API 缺失的版本自动跳过该保护）
SimpleShop.isTyping = function()
	local ok, focus = pcall(function()
		if UIManager == nil then return nil end
		local getDefault = UIManager.getDefaultUIManager;
		if type(getDefault) ~= "function" then return nil end
		local manager = getDefault();
		if not manager then return nil end
		return manager:getKeyboardFocus();
	end);
	return ok and focus ~= nil;
end

SimpleShop.handleKeyPressed = function(key)
	if key == nil then return end
	if SimpleShop.isTyping() then return end

	local openKey = SimpleShop.getKeyBind(SimpleShop.keyBindIds.openShop);
	if openKey and key == openKey then
		SimpleShop.openShopByKey();
		return;
	end

	local manageKey = SimpleShop.getKeyBind(SimpleShop.keyBindIds.manageItems);
	if manageKey and key == manageKey then
		SimpleShop.openAdminByKey();
	end
end

-- 主菜单/无玩家/UI 初始化阶段也可能收到按键，整体兜底避免刷错误日志
SimpleShop.onKeyStartPressed = function(key)
	local ok, err = pcall(SimpleShop.handleKeyPressed, key);
	if not ok then
		print("[SimpleShop] keybind handler error: " .. tostring(err));
	end
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
-- 填充世界对象上下文菜单（只保留"打开商店"；商品管理走商店窗口按钮或快捷键）
-- **************************************************************************************
SimpleShop.doWorldContextMenu = function(playerNum, context, worldobjects)
	-- 模组配置可关掉右键入口
	if not SimpleShop.getShowContextMenuOption() then return end

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
-- 填充库存对象上下文菜单（只保留"打开商店"；商品管理走商店窗口按钮或快捷键）
-- **************************************************************************************
SimpleShop.doInventoryContextMenu = function(playerNum, context, items)
	-- 模组配置可关掉右键入口
	if not SimpleShop.getShowContextMenuOption() then return end

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
	-- 兜底注册快捷键配置（Mod Options 可能晚于本文件加载）
	SimpleShop.registerModOptions();

	-- 加载客户端网络命令模块（联机支持）
	require "SimpleShopClientCommands"
	-- 联机时主动拉取服务端的商品价格表
	if isClient() then
		SimpleShopClientCommands.SendPricesRequest();
	end
	-- 悬浮余额面板
	SimpleShop.initHud();
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
	-- 死亡后先收起悬浮余额面板，复活时由 OnCreatePlayer 重建
	SimpleShop.destroyHud();
	-- 再次初始化玩家金钱
	Events.OnCreatePlayer.Add(SimpleShop.InitPlayer);
	-- 复活（新角色）后重新挂上悬浮余额面板
	Events.OnCreatePlayer.Add(SimpleShop.initHud);
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

-- 模组选项（快捷键）：立即尝试注册（Mod Options 已加载时），OnGameBoot 再兜底一次
SimpleShop.registerModOptions();
if Events.OnGameBoot then
	Events.OnGameBoot.Add(SimpleShop.registerModOptions);
end
if Events.OnKeyStartPressed then
	Events.OnKeyStartPressed.Add(SimpleShop.onKeyStartPressed);
end