-- SimpleShop 商品价格存储
-- 价格表与商品陈列顺序保存在世界级全局 ModData 中，随存档持久化（多人模式下由服务端权威维护）
-- 数据结构: { initialized = true, prices = { ["Base.Bread"] = 75, ... }, order = { "Base.Bread", ... } }

SimpleShopItemStore = SimpleShopItemStore or {};

SimpleShopItemStore.KEY = "SimpleShopPrices";
SimpleShopItemStore.prices = {};        -- 当前生效的价格表（fullType -> cost）
SimpleShopItemStore.order = {};         -- 自定义陈列顺序（fullType 数组，管理员在定价窗口调整）
SimpleShopItemStore.orderIndexMap = nil; -- order 的下标缓存（fullType -> 位置）
SimpleShopItemStore.isLoaded = false;   -- 是否已完成加载/同步
SimpleShopItemStore.listeners = {};     -- 价格/顺序变化监听器
SimpleShopItemStore.MAX_PRICE = 999999; -- 单个商品最高价格
SimpleShopItemStore.scriptItems = nil;  -- 全量物品脚本缓存（管理界面用）
SimpleShopItemStore.nameCache = {};     -- fullType -> 小写显示名（未指定顺序时的兜底排序键）

local function log(msg)
	print("[SimpleShop] " .. tostring(msg));
end

-- **************************************************************************************
-- 沙箱配置读取（世界级设置，单机与联机通用；客户端拿到的也是服务端同步的值）
--   选项定义见 common/media/sandbox-options.txt，运行时读取 SandboxVars.SimpleShop.<name>
-- **************************************************************************************
SimpleShopItemStore.SANDBOX_PAGE = "SimpleShop";

function SimpleShopItemStore.getSandboxOption(name, default)
	if type(SandboxVars) ~= "table" then return default; end
	local page = SandboxVars[SimpleShopItemStore.SANDBOX_PAGE];
	if type(page) ~= "table" then return default; end
	local value = page[name];
	if value == nil then return default; end
	return value;
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
-- 物品脚本是否仍然存在（只查脚本管理器，不实例化物品，O(1) 哈希查找）
--   判别失败或管理器未就绪时一律按"存在"处理：宁可不清理，也不能误删存档里的价格
-- **************************************************************************************
function SimpleShopItemStore.scriptExists(fullType)
	if type(fullType) ~= "string" or fullType == "" then return false; end
	if type(getScriptManager) ~= "function" then return true; end
	local manager = getScriptManager();
	if not manager then return true; end
	local ok, script = pcall(function() return manager:getItem(fullType); end);
	if not ok then return true; end
	return script ~= nil;
end

-- **************************************************************************************
-- 默认价格表（来自 SimpleShopItems.lua）
--   只收取当前版本仍然存在的物品，避免默认清单里残留已删除的条目
-- **************************************************************************************
function SimpleShopItemStore.getDefaultPrices()
	local defaults = {};
	local source = SimpleShopItems;
	if type(source) ~= "table" then
		source = (type(SimpleShop) == "table" and SimpleShop.settings and SimpleShop.settings["ITEMS"]) or {};
	end
	local total, kept = 0, 0;
	for fullType, cost in pairs(source) do
		if type(fullType) == "string" and type(cost) == "number" then
			total = total + 1;
			if SimpleShopItemStore.scriptExists(fullType) then
				defaults[fullType] = math.floor(cost);
				kept = kept + 1;
			end
		end
	end
	-- 兜底：脚本还没就绪时会把整份默认清单判成"不存在"，那样会在首次开档写入空价格表，这里保留原清单
	if total > 0 and kept == 0 then
		for fullType, cost in pairs(source) do
			if type(fullType) == "string" and type(cost) == "number" then
				defaults[fullType] = math.floor(cost);
			end
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
-- 陈列顺序（管理员可上移/下移；未指定顺序的商品排在已指定商品之后，按名称排列）
-- **************************************************************************************
function SimpleShopItemStore.getOrder()
	return SimpleShopItemStore.order;
end

function SimpleShopItemStore.invalidateOrderCache()
	SimpleShopItemStore.orderIndexMap = nil;
end

-- order 下标表：fullType -> 位置（越小越靠前）
function SimpleShopItemStore.getOrderIndexMap()
	if SimpleShopItemStore.orderIndexMap then
		return SimpleShopItemStore.orderIndexMap;
	end
	local map = {};
	local order = SimpleShopItemStore.order;
	if type(order) == "table" then
		for index, fullType in ipairs(order) do
			if type(fullType) == "string" and map[fullType] == nil then
				map[fullType] = index;
			end
		end
	end
	SimpleShopItemStore.orderIndexMap = map;
	return map;
end

-- 商品名称排序键：只在"没有指定陈列顺序"时兜底使用
function SimpleShopItemStore.getSortName(fullType)
	fullType = tostring(fullType or "");
	local cached = SimpleShopItemStore.nameCache[fullType];
	if cached then return cached; end

	local name = nil;
	local manager = getScriptManager();
	if manager then
		local okScript, script = pcall(function() return manager:getItem(fullType); end);
		if okScript and script then
			local okName, value = pcall(function() return script:getDisplayName(); end);
			if okName then name = value; end
		end
	end
	local key = string.lower(name or fullType);
	SimpleShopItemStore.nameCache[fullType] = key;
	return key;
end

-- 完整陈列顺序：order 里仍在上架的按原顺序在前，其余商品按名称追加在后
-- @param prices 价格表（默认取当前生效表）
-- @param order 顺序数组（默认取当前生效顺序）
function SimpleShopItemStore.buildDisplayOrder(prices, order)
	local items = prices or SimpleShopItemStore.prices or {};
	order = order or SimpleShopItemStore.order;

	local result, seen = {}, {};
	if type(order) == "table" then
		for _, fullType in ipairs(order) do
			if type(fullType) == "string" and items[fullType] ~= nil and not seen[fullType] then
				seen[fullType] = true;
				result[#result + 1] = fullType;
			end
		end
	end

	local rest = {};
	for fullType in pairs(items) do
		if not seen[fullType] then
			rest[#rest + 1] = fullType;
		end
	end
	table.sort(rest, function(a, b)
		local an, bn = SimpleShopItemStore.getSortName(a), SimpleShopItemStore.getSortName(b);
		if an == bn then return a < b; end
		return an < bn;
	end);
	for _, fullType in ipairs(rest) do
		result[#result + 1] = fullType;
	end
	return result;
end

local function containsType(list, fullType)
	for _, value in ipairs(list) do
		if value == fullType then return true; end
	end
	return false;
end

-- 在 order 里移动商品：delta 为 -1 上移、1 下移（可为更大步长）
-- 移动前先把当前展示顺序固化，保证第一次调整就得到可预期的结果
-- @return 是否真的发生了移动（已在顶部/底部时返回 false）
function SimpleShopItemStore.moveInOrder(prices, order, fullType, delta)
	if type(fullType) ~= "string" or fullType == "" then return false; end
	if prices[fullType] == nil then return false; end

	delta = math.floor(tonumber(delta) or 0);
	if delta == 0 then return false; end

	local current = SimpleShopItemStore.buildDisplayOrder(prices, order);
	local index = nil;
	for i = 1, #current do
		if current[i] == fullType then
			index = i;
			break;
		end
	end
	if not index then return false; end

	local target = math.max(1, math.min(#current, index + delta));
	if target == index then return false; end

	local moving = current[index];
	table.remove(current, index);
	table.insert(current, target, moving);

	for i = #order, 1, -1 do
		order[i] = nil;
	end
	for i = 1, #current do
		order[i] = current[i];
	end
	return true;
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
	-- 陈列顺序：老存档没有该字段时按空表处理（此时列表回退为按名称排列）
	if type(modData.order) ~= "table" then
		modData.order = {};
	end
	SimpleShopItemStore.prices = modData.prices;
	SimpleShopItemStore.order = modData.order;
	SimpleShopItemStore.invalidateOrderCache();
	SimpleShopItemStore.isLoaded = true;
	-- 老存档里可能有"来源模组已移除/官方已删除"的商品残留：加载后立刻清掉，不再读进列表也不再存回
	local okPrune, errPrune = pcall(SimpleShopItemStore.pruneMissingItems);
	if not okPrune then log("prune missing items failed: " .. tostring(errPrune)); end
	log("price table loaded (" .. tostring(SimpleShopItemStore.getCount()) .. " items, "
		.. tostring(#SimpleShopItemStore.order) .. " ordered)");
end

-- **************************************************************************************
-- 用服务端下发的价格表/陈列顺序整体替换本地状态（客户端用）
-- @param prices fullType -> cost 的表
-- @param order 陈列顺序数组；为 nil 表示本次不同步顺序（保持本地值）
-- **************************************************************************************
function SimpleShopItemStore.applyServerState(prices, order)
	if type(prices) ~= "table" then return false; end

	local target = SimpleShopItemStore.prices;
	if type(target) ~= "table" then
		target = {};
		SimpleShopItemStore.prices = target;
	end

	-- 服务端/单机下 target 与 source 是同一张表，无需拷贝
	if prices ~= target then
		for k in pairs(target) do target[k] = nil; end
		for k, v in pairs(prices) do
			if type(k) == "string" and type(v) == "number" then
				target[k] = v;
			end
		end
	end

	if type(order) == "table" then
		local targetOrder = SimpleShopItemStore.order;
		if type(targetOrder) ~= "table" then
			targetOrder = {};
			SimpleShopItemStore.order = targetOrder;
		end
		if order ~= targetOrder then
			for i = #targetOrder, 1, -1 do targetOrder[i] = nil; end
			for _, fullType in ipairs(order) do
				if type(fullType) == "string" then
					targetOrder[#targetOrder + 1] = fullType;
				end
			end
		end
	end

	SimpleShopItemStore.invalidateOrderCache();
	SimpleShopItemStore.isLoaded = true;
	SimpleShopItemStore.notify();
	return true;
end

-- 兼容旧调用：只同步价格表
function SimpleShopItemStore.applyServerPrices(source)
	return SimpleShopItemStore.applyServerState(source, nil);
end

-- **************************************************************************************
-- 收到服务端同步的状态（全局 ModData 通道，价格 + 陈列顺序）
-- **************************************************************************************
function SimpleShopItemStore.onReceiveGlobalModData(key, modData)
	if key ~= SimpleShopItemStore.KEY then return; end
	SimpleShopItemStore.applyServerState(modData and modData.prices, modData and modData.order);
end

-- **************************************************************************************
-- 权威写入（仅单人/主机/服务端调用）
--   mutator(prices, order) 返回 false 表示没有实际变化（跳过同步/通知）
-- **************************************************************************************
function SimpleShopItemStore.applyChange(mutator)
	local modData = SimpleShopItemStore.getModData();
	if type(modData.prices) ~= "table" then
		modData.prices = SimpleShopItemStore.getDefaultPrices();
	end
	if type(modData.order) ~= "table" then
		modData.order = {};
	end
	modData.initialized = true;
	SimpleShopItemStore.prices = modData.prices;
	SimpleShopItemStore.order = modData.order;

	if mutator(modData.prices, modData.order) == false then
		return false;
	end

	SimpleShopItemStore.invalidateOrderCache();
	SimpleShopItemStore.isLoaded = true;
	-- 同步给所有客户端（单人游戏下无副作用）
	ModData.transmit(SimpleShopItemStore.KEY);
	SimpleShopItemStore.notify();
	return true;
end

-- 兼容旧调用：只写价格表
function SimpleShopItemStore.applyPricesChange(mutator)
	return SimpleShopItemStore.applyChange(mutator);
end

-- **************************************************************************************
-- 对外接口：上架/改价（新上架的商品排到陈列顺序末尾，改价保持原位）
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

	return SimpleShopItemStore.applyChange(function(prices, order)
		local isNew = prices[fullType] == nil;
		prices[fullType] = cost;
		if isNew and not containsType(order, fullType) then
			order[#order + 1] = fullType;
		end
	end);
end

-- **************************************************************************************
-- 对外接口：下架（同时移出陈列顺序）
-- **************************************************************************************
function SimpleShopItemStore.removePrice(fullType)
	if type(fullType) ~= "string" or fullType == "" then return false; end

	if isClient() then
		return SimpleShopClientCommands.SendRemovePriceRequest(fullType);
	end

	return SimpleShopItemStore.applyChange(function(prices, order)
		prices[fullType] = nil;
		for index = #order, 1, -1 do
			if order[index] == fullType then
				table.remove(order, index);
			end
		end
	end);
end

-- **************************************************************************************
-- 清理"脚本已不存在"的残留商品（价格表 + 陈列顺序）
--   与商店列表口径一致：列表只显示还用 instanceItem 实例化得出来的物品，价格表也照此收敛
--   开销：对现有价格表的每个 key 做一次脚本管理器哈希查找（商品数量级几百），开局执行一次
--   联机客户端不清理（数据以服务端下发为准）；判别失败时 scriptExists 返回 true，不会误删
-- @return 清理掉的商品数量
-- **************************************************************************************
function SimpleShopItemStore.pruneMissingItems()
	if isClient() then return 0; end

	-- 先只统计，不边遍历边删：整表都判成"不存在"通常意味着物品脚本还没就绪，此时不能动存档
	local prices = SimpleShopItemStore.getPrices();
	if type(prices) ~= "table" then return 0; end

	local total, missing = 0, {};
	for fullType in pairs(prices) do
		total = total + 1;
		if not SimpleShopItemStore.scriptExists(fullType) then
			missing[#missing + 1] = fullType;
		end
	end
	if #missing == 0 then return 0; end
	if #missing == total then
		log("skip pruning: all " .. tostring(total) .. " item(s) look missing, item scripts may not be ready");
		return 0;
	end

	SimpleShopItemStore.applyChange(function(modPrices, order)
		for _, fullType in ipairs(missing) do
			modPrices[fullType] = nil;
		end
		for index = #order, 1, -1 do
			local fullType = order[index];
			if type(fullType) ~= "string" or not SimpleShopItemStore.scriptExists(fullType) then
				table.remove(order, index);
			end
		end
	end);

	log("pruned " .. tostring(#missing) .. " missing item(s) from price table");
	return #missing;
end

-- **************************************************************************************
-- 对外接口：恢复默认商品清单（同时清空自定义陈列顺序，回到按名称排列）
-- **************************************************************************************
function SimpleShopItemStore.resetToDefault()
	if isClient() then
		return SimpleShopClientCommands.SendResetPricesRequest();
	end

	local defaults = SimpleShopItemStore.getDefaultPrices();
	return SimpleShopItemStore.applyChange(function(prices, order)
		for fullType in pairs(prices) do prices[fullType] = nil; end
		for fullType, cost in pairs(defaults) do prices[fullType] = cost; end
		for index = #order, 1, -1 do order[index] = nil; end
	end);
end

-- **************************************************************************************
-- 对外接口：调整商品陈列顺序
-- @param fullType 物品类型
-- @param delta -1 上移、1 下移（可为更大步长）
-- **************************************************************************************
function SimpleShopItemStore.moveOrder(fullType, delta)
	if type(fullType) ~= "string" or fullType == "" then return false; end
	delta = math.floor(tonumber(delta) or 0);
	if delta == 0 then return false; end

	-- 联机客户端：交给服务端调序
	if isClient() then
		if SimpleShopClientCommands and SimpleShopClientCommands.SendMoveOrderRequest then
			return SimpleShopClientCommands.SendMoveOrderRequest(fullType, delta);
		end
		return false;
	end

	return SimpleShopItemStore.applyChange(function(prices, order)
		return SimpleShopItemStore.moveInOrder(prices, order, fullType, delta);
	end);
end

-- **************************************************************************************
-- 对外接口：置顶/置底
-- @param toBottom true 移到末尾，false 移到最前
-- **************************************************************************************
SimpleShopItemStore.MOVE_TO_EDGE_STEP = 999999;

function SimpleShopItemStore.moveOrderToEdge(fullType, toBottom)
	local delta = toBottom and SimpleShopItemStore.MOVE_TO_EDGE_STEP or -SimpleShopItemStore.MOVE_TO_EDGE_STEP;
	return SimpleShopItemStore.moveOrder(fullType, delta);
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
					-- 名称缓存：未指定陈列顺序的商品靠它按名称兜底排序
					SimpleShopItemStore.nameCache[fullType] = string.lower(displayName);
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
-- 兜底：万一 OnInitGlobalModData 阶段物品脚本还没完全就绪，进游戏后再收敛一次（已清理过时无开销）
if Events.OnGameStart then
	Events.OnGameStart.Add(function()
		if not SimpleShopItemStore.isLoaded then return end
		local ok, err = pcall(SimpleShopItemStore.pruneMissingItems);
		if not ok then log("prune missing items failed: " .. tostring(err)); end
	end);
end
