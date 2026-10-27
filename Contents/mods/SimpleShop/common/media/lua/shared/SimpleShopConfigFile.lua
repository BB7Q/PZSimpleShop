-- SimpleShop 全局配置读写（整个游戏生效，不随存档变化）
--   引擎的 getFileReader / getFileWriter 把路径解析到"用户 Zomboid 目录/Lua/"下（AutoLoot 也是这样存的）：
--     Windows: C:\Users\<你>\Zomboid\Lua\SimpleShopPrices.ini
--     Linux  : ~/Zomboid/Lua/SimpleShopPrices.ini
--   配置文件放在存档之外，所以同一台机器上所有存档、所有角色共用同一份商品清单与陈列顺序。
--   联机时这个文件在服务端（主机）机器上，客户端通过服务端下发同步，不需要也不能自己写。
--
-- 两个文件：
--   SimpleShopConfig.ini  -- 只有一行 mode=global / mode=save，决定价格表存哪儿
--   SimpleShopPrices.ini  -- mode=global 时的价格表（mode=save 时不读也不写，价格表在世界 ModData 里）
--
-- 价格表文件格式（一行一条，TAB 分隔，# 开头为注释）：
--   version=1
--   P<TAB>Full.Type<TAB>价格       -- 上架商品，价格 0 ~ 999999 的整数
--   O<TAB>序号<TAB>Full.Type        -- 自定义陈列顺序，序号从 1 开始，越小越靠前
--   也兼容手写：Base.Bread = 75    （等号写法按价格行处理；顺序仍要写 O 行）

SimpleShopConfigFile = SimpleShopConfigFile or {};

SimpleShopConfigFile.FILE = "SimpleShopPrices.ini";
SimpleShopConfigFile.MODE_FILE = "SimpleShopConfig.ini";
SimpleShopConfigFile.VERSION = 1;
SimpleShopConfigFile.MAX_PRICE = 999999;

local function log(msg)
	print("[SimpleShop] " .. tostring(msg));
end

-- PZ 的字符串没有 trim
local function trim(value)
	value = tostring(value or "");
	value = string.gsub(value, "^%s+", "");
	value = string.gsub(value, "%s+$", "");
	return value;
end

-- 价格合法性（与 SimpleShopItemStore.sanitizePrice 同口径）
local function sanitizePrice(value)
	local cost = tonumber(value);
	if not cost or cost ~= cost then return nil; end
	cost = math.floor(cost);
	if cost < 0 or cost > SimpleShopConfigFile.MAX_PRICE then return nil; end
	return cost;
end

-- **************************************************************************************
-- 读取全局配置
-- @return { prices = { [fullType] = cost }, order = { fullType, ... } }；文件不存在/没有价格行返回 nil
-- **************************************************************************************
function SimpleShopConfigFile.read()
	if type(getFileReader) ~= "function" then return nil; end

	local ok, reader = pcall(getFileReader, SimpleShopConfigFile.FILE, true);
	if not ok or not reader then return nil; end

	local prices, orderPairs = {}, {};
	local priced = 0;

	local line = reader:readLine();
	while line ~= nil do
		line = string.gsub(tostring(line), "\r", "");
		if line ~= "" and string.sub(line, 1, 1) ~= "#" then
			local kind, rest = string.match(line, "^(%a)\t(.*)$");
			if (kind == "P" or kind == "O") and rest then
				local first, second = string.match(rest, "^(.-)\t(.*)$");
				if kind == "P" and first then
					local fullType = trim(first);
					local cost = sanitizePrice(trim(second));
					if fullType ~= "" and cost then
						prices[fullType] = cost;
						priced = priced + 1;
					end
				elseif kind == "O" and first then
					local index = tonumber(trim(first));
					local fullType = trim(second);
					if index and index >= 1 and fullType ~= "" then
						orderPairs[#orderPairs + 1] = { index = index, fullType = fullType };
					end
				end
			else
				-- 兼容手写的 "Base.Bread = 75"
				local key, value = string.match(line, "^([^=]+)=(.*)$");
				if key then
					local fullType = trim(key);
					local cost = sanitizePrice(trim(value));
					if fullType ~= "" and fullType ~= "version" and cost then
						prices[fullType] = cost;
						priced = priced + 1;
					end
				end
			end
		end
		line = reader:readLine();
	end
	reader:close();

	-- 一行价格都没有：文件不存在或被清空，交给调用方回退到存档/默认清单（不能当成"空商店"用）
	if priced == 0 then return nil; end

	table.sort(orderPairs, function(a, b) return a.index < b.index; end);
	local order = {};
	for _, entry in ipairs(orderPairs) do
		order[#order + 1] = entry.fullType;
	end

	return { prices = prices, order = order };
end

-- **************************************************************************************
-- 写入全局配置（整体覆盖）
-- @param prices fullType -> cost
-- @param order 陈列顺序数组（只写入仍然上架的商品）
-- @return 是否写成功
-- **************************************************************************************
function SimpleShopConfigFile.write(prices, order)
	if type(getFileWriter) ~= "function" then return false; end

	local ok, writer = pcall(getFileWriter, SimpleShopConfigFile.FILE, true, false);
	if not ok or not writer then
		log("cannot open " .. tostring(SimpleShopConfigFile.FILE) .. " for writing");
		return false;
	end

	local version = tostring(SimpleShopConfigFile.VERSION);
	writer:write("# SimpleShop global config (applies to every save on this machine)\n");
	writer:write("# P<TAB>ItemType<TAB>price   listed item\n");
	writer:write("# O<TAB>index<TAB>ItemType   custom display order\n");
	writer:write("version=" .. version .. "\n");

	-- 价格按物品 ID 排序：文件可读，也便于用 git/diff 看改动
	local keys = {};
	for fullType, cost in pairs(prices or {}) do
		if type(fullType) == "string" and type(cost) == "number" then
			keys[#keys + 1] = fullType;
		end
	end
	table.sort(keys);
	for _, fullType in ipairs(keys) do
		writer:write("P\t" .. fullType .. "\t" .. tostring(math.floor(prices[fullType])) .. "\n");
	end

	local ordered, seen = {}, {};
	for _, fullType in ipairs(order or {}) do
		if type(fullType) == "string" and not seen[fullType] and (prices or {})[fullType] ~= nil then
			seen[fullType] = true;
			ordered[#ordered + 1] = fullType;
		end
	end
	for index, fullType in ipairs(ordered) do
		writer:write("O\t" .. tostring(index) .. "\t" .. fullType .. "\n");
	end

	writer:close();
	return true;
end

-- **************************************************************************************
-- 存储模式（SimpleShopConfig.ini 里的 mode= 行）
--   global = 整个游戏生效（价格表写 SimpleShopPrices.ini，所有存档共用）
--   save   = 只在当前存档生效（价格表存在世界级全局 ModData 里，随存档）
-- @return "global" / "save"，文件不存在或内容非法时返回 nil
-- **************************************************************************************
function SimpleShopConfigFile.readMode()
	if type(getFileReader) ~= "function" then return nil; end

	local ok, reader = pcall(getFileReader, SimpleShopConfigFile.MODE_FILE, true);
	if not ok or not reader then return nil; end

	local mode = nil;
	local line = reader:readLine();
	while line ~= nil do
		line = string.gsub(tostring(line), "\r", "");
		if line ~= "" and string.sub(line, 1, 1) ~= "#" then
			local key, value = string.match(line, "^([^=]+)=(.*)$");
			if key and trim(key) == "mode" then
				local candidate = string.lower(trim(value));
				if candidate == "save" or candidate == "global" then
					mode = candidate;
				end
			end
		end
		line = reader:readLine();
	end
	reader:close();
	return mode;
end

-- 写入存储模式（保留文件里的其它行，只替换/追加 mode=）
-- @return 是否写成功
function SimpleShopConfigFile.writeMode(mode)
	if type(getFileReader) ~= "function" or type(getFileWriter) ~= "function" then return false; end
	mode = string.lower(tostring(mode or ""));
	if mode ~= "save" and mode ~= "global" then return false; end

	-- 先把除 mode= 之外的行收集起来，避免把别人手工加的内容冲掉
	local kept = {};
	local okRead, reader = pcall(getFileReader, SimpleShopConfigFile.MODE_FILE, true);
	if okRead and reader then
		local line = reader:readLine();
		while line ~= nil do
			local raw = string.gsub(tostring(line), "\r", "");
			local key = string.match(raw, "^([^=]+)=");
			if raw ~= "" and string.sub(raw, 1, 1) ~= "#" and (not key or trim(key) ~= "mode") then
				kept[#kept + 1] = raw;
			end
			line = reader:readLine();
		end
		reader:close();
	end

	local okWrite, writer = pcall(getFileWriter, SimpleShopConfigFile.MODE_FILE, true, false);
	if not okWrite or not writer then
		log("cannot open " .. tostring(SimpleShopConfigFile.MODE_FILE) .. " for writing");
		return false;
	end
	writer:write("# SimpleShop config\n");
	writer:write("# mode=global : price table is shared by every save on this machine\n");
	writer:write("# mode=save   : price table lives in the current save only\n");
	writer:write("mode=" .. mode .. "\n");
	for _, line in ipairs(kept) do
		writer:write(line .. "\n");
	end
	writer:close();
	return true;
end
