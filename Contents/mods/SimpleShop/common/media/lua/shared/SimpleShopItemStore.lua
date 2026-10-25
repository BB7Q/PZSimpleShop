-- SimpleShop 商品价格存储
-- 价格表保存在世界级全局 ModData 中，随存档持久化（多人模式下由服务端权威维护）
-- 数据结构: { initialized = true, prices = { ["Base.Bread"] = 75, ... } }

SimpleShopItemStore = SimpleShopItemStore or {};

SimpleShopItemStore.KEY = "SimpleShopPrices";
SimpleShopItemStore.prices = {};        -- 当前生效的价格表（fullType -> cost）
SimpleShopItemStore.isLoaded = false;   -- 是否已完成加载/同步
SimpleShopItemStore.listeners = {};     -- 价格变化监听器
SimpleShopItemStore.MAX_PRICE = 999999; -- 单个商品最高价格
SimpleShopItemStore.scriptItems = nil;  -- 全量物品脚本缓存（管理界面用）

local function log(msg)
	print("[SimpleShop] " .. tostring(msg));
end

-- **************************************************************************************
-- 全局 ModData 访问
-- **************************************************************************************
function SimpleShopItemStore.getModData()
	return ModData.getOrCreate(SimpleShopItemStore.KEY);
end

-- **************************************************************************************
-- 价格合法性校验（0 ~ MAX_PRICE 的整数）
-- @return 合法价格或nil
-- **************************************************************************************
function SimpleShopItemStore.sanitizePrice(value)
	local cost = tonumber(value);
	if not cost or cost ~= cost then return nil; end
	cost = math.floor(cost);
	if cost < 0 or cost > SimpleShopItemStore.MAX_PRICE then return nil; end
	return cost;
end

-- **************************************************************************************
-- 默认价格表（来自 SimpleShopItems.lua）
-- **************************************************************************************
function SimpleShopItemStore.getDefaultPrices()
	local defaults = {};
	local source = SimpleShopItems;
	if type(source) ~= "table" then
		source = (type(SimpleShop) == "table" and SimpleShop.settings and SimpleShop.settings["ITEMS"]) or {};
	end
	for fullType, cost in pairs(source) do
		if type(fullType) == "string" and type(cost) == "number" then
			defaults[fullType] = math.floor(cost);
		end
	end
	return defaults;
end

-- **************************************************************************************
-- 价格查询
-- **************************************************************************************
function SimpleShopItemStore.getPrices()
	return SimpleShopItemStore.prices;
end

function SimpleShopItemStore.getPrice(fullType)
	if type(fullType) ~= "string" then return nil; end
	return SimpleShopItemStore.prices[fullType];
end

function SimpleShopItemStore.hasPrice(fullType)
	return SimpleShopItemStore.getPrice(fullType) ~= nil;
end

function SimpleShopItemStore.getCount()
	local count = 0;
	for _ in pairs(SimpleShopItemStore.prices) do count = count + 1; end
	return count;
end

-- **************************************************************************************
-- 监听器（价格变化后刷新界面）
-- **************************************************************************************
function SimpleShopItemStore.addListener(fn)
	if type(fn) ~= "function" then return; end
	for _, existing in ipairs(SimpleShopItemStore.listeners) do
		if existing == fn then return; end
	end
	table.insert(SimpleShopItemStore.listeners, fn);
end

function SimpleShopItemStore.removeListener(fn)
	for i = #SimpleShopItemStore.listeners, 1, -1 do
		if SimpleShopItemStore.listeners[i] == fn then
			table.remove(SimpleShopItemStore.listeners, i);
		end
	end
end

function SimpleShopItemStore.notify()
	for _, fn in ipairs(SimpleShopItemStore.listeners) do
		local ok, err = pcall(fn);
		if not ok then log("listener error: " .. tostring(err)); end
	end
end

-- **************************************************************************************
-- 初始化（OnInitGlobalModData / OnGameStart 时调用）
-- **************************************************************************************
function SimpleShopItemStore.initialize(isNewGame)
	-- 联机客户端：本地没有权威数据，向服务端请求
	if isClient() then
		SimpleShopItemStore.isLoaded = false;
		ModData.request(SimpleShopItemStore.KEY);
		if SimpleShopClientCommands and SimpleShopClientCommands.SendPricesRequest then
			SimpleShopClientCommands.SendPricesRequest();
		end
		return;
	end

	local modData = SimpleShopItemStore.getModData();
	if type(modData.prices) ~= "table" or not modData.initialized then
		modData.prices = SimpleShopItemStore.getDefaultPrices();
		modData.initialized = true;
		log("initialized default price table");
	end
	SimpleShopItemStore.prices = modData.prices;
	SimpleShopItemStore.isLoaded = true;
	log("price table loaded (" .. tostring(SimpleShopItemStore.getCount()) .. " items)");
end

-- **************************************************************************************
-- 用服务端下发的价格表整体替换本地价格表（客户端用）
-- @param source fullType -> cost 的表
-- **************************************************************************************
function SimpleShopItemStore.applyServerPrices(source)
	if type(source) ~= "table" then return false; end

	local target = SimpleShopItemStore.prices;
	if type(target) ~= "table" then
		target = {};
		SimpleShopItemStore.prices = target;
	end

	-- 服务端/单机下 target 与 source 是同一张表，无需拷贝
	if source ~= target then
		for k in pairs(target) do target[k] = nil; end
		for k, v in pairs(source) do
			if type(k) == "string" and type(v) == "number" then
				target[k] = v;
			end
		end
	end

	SimpleShopItemStore.isLoaded = true;
	SimpleShopItemStore.notify();
	return true;
end

-- **************************************************************************************
-- 收到服务端同步的价格表（全局 ModData 通道）
-- **************************************************************************************
function SimpleShopItemStore.onReceiveGlobalModData(key, modData)
	if key ~= SimpleShopItemStore.KEY then return; end
	SimpleShopItemStore.applyServerPrices(modData and modData.prices);
end

-- **************************************************************************************
-- 权威写入（仅单人/主机/服务端调用）
-- **************************************************************************************
function SimpleShopItemStore.applyPricesChange(mutator)
	local modData = SimpleShopItemStore.getModData();
	if type(modData.prices) ~= "table" then
		modData.prices = SimpleShopItemStore.getDefaultPrices();
	end
	modData.initialized = true;
	SimpleShopItemStore.prices = modData.prices;

	mutator(modData.prices);

	SimpleShopItemStore.isLoaded = true;
	-- 同步给所有客户端（单人游戏下无副作用）
	ModData.transmit(SimpleShopItemStore.KEY);
	SimpleShopItemStore.notify();
	return true;
end

-- **************************************************************************************
-- 对外接口：上架/改价
-- **************************************************************************************
function SimpleShopItemStore.setPrice(fullType, cost)
	cost = SimpleShopItemStore.sanitizePrice(cost);
	if type(fullType) ~= "string" or fullType == "" or not cost then
		return false;
	end

	-- 联机客户端：交给服务端写入
	if isClient() then
		return SimpleShopClientCommands.SendSetPriceRequest(fullType, cost);
	end

	return SimpleShopItemStore.applyPricesChange(function(prices)
		prices[fullType] = cost;
	end);
end

-- **************************************************************************************
-- 对外接口：下架
-- **************************************************************************************
function SimpleShopItemStore.removePrice(fullType)
	if type(fullType) ~= "string" or fullType == "" then return false; end

	if isClient() then
		return SimpleShopClientCommands.SendRemovePriceRequest(fullType);
	end

	return SimpleShopItemStore.applyPricesChange(function(prices)
		prices[fullType] = nil;
	end);
end

-- **************************************************************************************
-- 对外接口：恢复默认商品清单
-- **************************************************************************************
function SimpleShopItemStore.resetToDefault()
	if isClient() then
		return SimpleShopClientCommands.SendResetPricesRequest();
	end

	local defaults = SimpleShopItemStore.getDefaultPrices();
	return SimpleShopItemStore.applyPricesChange(function(prices)
		for fullType in pairs(prices) do prices[fullType] = nil; end
		for fullType, cost in pairs(defaults) do prices[fullType] = cost; end
	end);
end

-- **************************************************************************************
-- 物品所属模块名（fullType 的 "模块." 前缀，通常即物品来源模组）
-- **************************************************************************************
function SimpleShopItemStore.getModuleOf(fullType)
	local module = string.match(tostring(fullType or ""), "^([^%.]+)%.");
	return module or "Base";
end

-- **************************************************************************************
-- 内部/兼容用的变体物品：不进商店列表
--   - xxx_Hidden 后缀是模组常见约定（同一件衣服的内部样式副本，显示名与本体完全相同）
--   - Hidden / Obsolete 属性由引擎声明
-- **************************************************************************************
local function isInternalItem(script, fullType)
	if string.sub(fullType, -7) == "_Hidden" then
		return true;
	end
	if script:isHidden() or script:getObsolete() then
		return true;
	end
	return false;
end

-- **************************************************************************************
-- 全量物品脚本（包含其他模组添加的物品），首次调用时构建并缓存
--   同时预计算小写检索键：搜索/排序时不必对每个物品反复 string.lower（上万条时开销很大）
-- **************************************************************************************
function SimpleShopItemStore.getAllScriptItems()
	if SimpleShopItemStore.scriptItems then
		return SimpleShopItemStore.scriptItems;
	end

	local result = {};
	local known = {};
	local manager = getScriptManager();
	local allItems = manager and manager:getAllItems();
	if allItems then
		for i = 0, allItems:size() - 1 do
			local script = allItems:get(i);
			if script then
				local fullType = script:getFullName();
				if fullType and fullType ~= "" and not known[fullType] and not isInternalItem(script, fullType) then
					local displayName = script:getDisplayName() or fullType;
					known[fullType] = true;
					result[#result + 1] = {
						itemType = fullType,
						itemName = displayName,
						category = script:getDisplayCategory() or "Other",
						module = SimpleShopItemStore.getModuleOf(fullType),
						iconName = script:getIcon(),
						searchName = string.lower(displayName),
						searchType = string.lower(fullType),
					};
				end
			end
		end
	end

	table.sort(result, function(a, b)
		if a.searchName == b.searchName then return a.itemType < b.itemType; end
		return a.searchName < b.searchName;
	end);

	SimpleShopItemStore.scriptItems = result;
	SimpleShopItemStore.scriptItemSet = known;
	log("item scripts cached: " .. tostring(#result));
	return result;
end

-- **************************************************************************************
-- 物品是否仍然存在于脚本中（用于识别"脚本已被移除但有价格残留"的条目）
-- **************************************************************************************
function SimpleShopItemStore.isKnownScriptItem(fullType)
	if not SimpleShopItemStore.scriptItemSet then
		SimpleShopItemStore.getAllScriptItems();
	end
	return SimpleShopItemStore.scriptItemSet[fullType] == true;
end

-- **************************************************************************************
-- 按物品实例取图标（管理界面用，找不到返回nil）
-- **************************************************************************************
function SimpleShopItemStore.getIconTexture(scriptItem)
	if not scriptItem or not scriptItem.iconName then return nil; end
	if type(tryGetTexture) ~= "function" then return nil; end
	local ok, texture = pcall(tryGetTexture, "Item_" .. tostring(scriptItem.iconName));
	if not ok then return nil; end
	return texture;
end

-- **************************************************************************************
-- 注册事件
-- **************************************************************************************
if Events.OnInitGlobalModData then
	Events.OnInitGlobalModData.Add(SimpleShopItemStore.initialize);
end
if Events.OnReceiveGlobalModData then
	Events.OnReceiveGlobalModData.Add(SimpleShopItemStore.onReceiveGlobalModData);
end
