require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISButton"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "SimpleShop"
require "SimpleShopItemStore"

-- **************************************************************************************
-- 商品定价窗口：选择游戏内任意物品（含其他模组物品）并设置价格
-- 布局：工具栏（搜索 / 视图 / 分类）→ 物品列表 → 分页栏 → 操作栏 → 状态行
-- **************************************************************************************
ISSimpleShopAdmin = ISCollapsableWindow:derive("ISSimpleShopAdmin");

-- 行内是「名称 + 物品 ID」两行文本，行高要留够两行文字与上下留白
local ITEM_HEIGHT = 58;
local ALL_CATEGORIES = "all";
local ALL_MODS = "all";
local PAD = 16;

function ISSimpleShopAdmin:initialise()
	ISCollapsableWindow.initialise(self);
	self:create();
end

-- 分类显示名：缺少 IGUI_ItemCat_XXX 翻译时回退为原始分类名
local function categoryLabel(category)
	local key = "IGUI_ItemCat_" .. tostring(category);
	local text = getText(key);
	if not text or text == "" or text == key then
		return tostring(category);
	end
	return text;
end

-- 来源模组显示名：原版模块显示"游戏本体"，其余优先取模组 info 的名称，失败回退模块名
local function moduleLabel(module)
	module = tostring(module or "");
	if module == "" or module == "Base" then
		return getText("UI_SimpleShop_VanillaModule");
	end

	if type(getModInfoByID) == "function" then
		local ok, info = pcall(getModInfoByID, module);
		if ok and info then
			local okName, name = pcall(function() return info:getName(); end);
			if okName and type(name) == "string" and name ~= "" then
				return name;
			end
		end
	end
	return module;
end

function ISSimpleShopAdmin:create()
	local titleHeight = self:titleBarHeight();
	local panelHeight = self.height - titleHeight;
	self.panel = ISPanel:new(0, titleHeight, self.width, panelHeight);
	self.panel:initialise();
	self.panel:instantiate();
	self:addChild(self.panel);

	self.needRefresh = false;
	self.nextRefresh = 0;
	self.iconCache = {};
	self.selectedType = nil;
	self.page = 1;
	self.pageCount = 1;
	self.filtered = {};
	self.showAll = false;
	self.mod = ALL_MODS;
	self.category = ALL_CATEGORIES;

	local w = self.width;
	local rowY = 8;
	local rowH = 26;
	local rowY2 = rowY + rowH + 8;

	-- 工具栏（第 1 行）：搜索框 / 视图切换
	self.searchBox = ISTextEntryBox:new("", PAD, rowY, 260, rowH);
	self.searchBox:initialise();
	self.searchBox:instantiate();
	self.searchBox:setFont(UIFont.Small);
	-- ISTextEntryBox 只有 onTextChangeFunction(target, box) 会被调用
	self.searchBox.target = self;
	self.searchBox.onTextChangeFunction = function(target, box)
		self.needRefresh = true;
	end
	self.searchBox.tooltip = getText("UI_SimpleShop_SearchLabel");
	self.panel:addChild(self.searchBox);

	local viewW = 104;
	self.viewListedButton = self:createButton(PAD + 268, rowY, viewW, rowH, getText("UI_SimpleShop_ViewListed"), "view_listed", self.onViewClicked);
	self.viewAllButton = self:createButton(PAD + 274 + viewW, rowY, viewW, rowH, getText("UI_SimpleShop_ViewAll"), "view_all", self.onViewClicked);

	-- 工具栏（第 2 行）：先按来源模组、再按物品类型的两级筛选
	local filterW = math.min(270, math.floor((w - PAD * 2 - 10) / 2));
	self.modCombo = ISComboBox:new(PAD, rowY2, filterW, rowH);
	self.modCombo:initialise();
	self.modCombo:instantiate();
	self.modCombo.font = UIFont.Small;
	-- ISComboBox 的回调签名是 onChange(target, comboBox)，必须走 setOnChange 指定 target
	self.modCombo:setOnChange(self, self.onModChanged);
	self.modCombo.tooltip = getText("UI_SimpleShop_ModFilter");
	self.panel:addChild(self.modCombo);
	self.modOptions = { ALL_MODS };

	self.categoryCombo = ISComboBox:new(PAD + filterW + 10, rowY2, filterW, rowH);
	self.categoryCombo:initialise();
	self.categoryCombo:instantiate();
	self.categoryCombo.font = UIFont.Small;
	self.categoryCombo:setOnChange(self, self.onCategoryChanged);
	self.categoryCombo.tooltip = getText("UI_SimpleShop_CategoryFilter");
	self.panel:addChild(self.categoryCombo);
	self.categoryOptions = { ALL_CATEGORIES };

	-- 列表
	local listY = rowY2 + rowH + 10;
	local pagerH = 26;
	local actionH = 30;
	local bottomReserve = pagerH + 8 + actionH + 8 + 20 + 8;
	local listH = panelHeight - listY - bottomReserve;

	self.itemList = ISScrollingListBox:new(PAD, listY, w - PAD * 2, listH);
	self.itemList:initialise();
	self.itemList:instantiate();
	self.itemList.backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.85 };
	self.itemList.borderColor = { r = 0.55, g = 0.55, b = 0.55, a = 1 };
	self.itemList.borderWidth = 2;
	self.itemList.drawBorder = true;
	self.itemList.itemheight = ITEM_HEIGHT;
	self.itemList.font = UIFont.Small;
	self.itemList:setOnMouseDownFunction(self, self.onSelectItem);

	local window = self;
	function self.itemList:doDrawItem(itemY, item, alt)
		return window:drawListItem(self, itemY, item, alt);
	end
	self.panel:addChild(self.itemList);

	self.pageSize = math.max(5, math.floor((listH - 4) / ITEM_HEIGHT));

	-- 分页栏
	local pagerY = listY + listH + 8;
	self.prevButton = self:createButton(PAD, pagerY, 78, pagerH, getText("UI_SimpleShop_PrevPage"), "prev_page", self.onPrevPage);
	self.nextButton = self:createButton(PAD + 84, pagerY, 78, pagerH, getText("UI_SimpleShop_NextPage"), "next_page", self.onNextPage);
	self.pageLabel = ISLabel:new(PAD + 176, pagerY + 5, 20, "", 0.85, 0.85, 0.85, 1, UIFont.Small, true);
	self.pageLabel:initialise();
	self.pageLabel:instantiate();
	self.panel:addChild(self.pageLabel);

	-- 已上架计数：ISLabel 没有右对齐，x 由 updateCountLabel 按文本宽度回算
	self.countLabel = ISLabel:new(PAD, pagerY + 5, 20, "", 0.85, 0.85, 0.6, 1, UIFont.Small);
	self.countLabel:initialise();
	self.countLabel:instantiate();
	self.panel:addChild(self.countLabel);

	-- 操作栏
	local actionY = pagerY + pagerH + 8;
	self.priceLabel = ISLabel:new(PAD, actionY + 6, 20, getText("UI_SimpleShop_Price"), 1, 1, 1, 1, UIFont.Small, true);
	self.priceLabel:initialise();
	self.priceLabel:instantiate();
	self.panel:addChild(self.priceLabel);

	self.priceEntry = ISTextEntryBox:new("", PAD + 42, actionY, 110, actionH);
	self.priceEntry:initialise();
	self.priceEntry:instantiate();
	self.priceEntry:setFont(UIFont.Small);
	self.priceEntry:setOnlyNumbers(true);
	self.panel:addChild(self.priceEntry);

	self.setButton = self:createButton(PAD + 160, actionY, 108, actionH, getText("UI_SimpleShop_SetPrice"), "set_price", self.onSetPrice);
	self.removeButton = self:createButton(PAD + 276, actionY, 80, actionH, getText("UI_SimpleShop_Remove"), "remove_price", self.onRemovePrice);
	self.resetButton = self:createButton(PAD + 364, actionY, 108, actionH, getText("UI_SimpleShop_ResetDefault"), "reset_prices", self.onResetPrices);
	self.closeButton = self:createButton(w - PAD - 84, actionY, 84, actionH, getText("UI_SimpleShop_Close"), "close", self.onCloseMouseDown);

	self.statusLabel = ISLabel:new(PAD, actionY + actionH + 4, 20, "", 0.85, 0.85, 0.6, 1, UIFont.Small, true);
	self.statusLabel:initialise();
	self.statusLabel:instantiate();
	self.panel:addChild(self.statusLabel);

	-- 徽标宽度只与文案有关，提前量好避免逐帧测量
	self.badgeText = getText("UI_SimpleShop_ListedCount");
	self.badgeWidth = getTextManager():MeasureStringX(UIFont.Small, self.badgeText) + 12;
	self.priceAreaWidth = math.max(96, self.badgeWidth + 96);
	-- 行内字体高度也要量一次：徽标背景必须比文字高，不能写死像素
	self.rowFontH = getTextManager():getFontHeight(UIFont.Small) or 14;

	self.priceListener = function()
		self.needRefresh = true;
	end
	SimpleShopItemStore.addListener(self.priceListener);

	self:updateViewButtons();
	self:rebuildFilters();
	self:rebuildList(true);
end

function ISSimpleShopAdmin:createButton(x, y, width, height, text, internal, onclick)
	local button = ISButton:new(x, y, width, height, text, self, onclick);
	button:initialise();
	button.internal = internal;
	button.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 1 };
	button:setFont(UIFont.Small);
	button:ignoreWidthChange();
	button:ignoreHeightChange();
	self.panel:addChild(button);
	return button;
end

-- **************************************************************************************
-- 视图切换 / 分类
-- **************************************************************************************
function ISSimpleShopAdmin:onViewClicked(button)
	self.showAll = (button and button.internal == "view_all");
	self:updateViewButtons();
	self:rebuildList(true);
end

-- ISComboBox 触发 onChange(self.target, self)：target 就是 self，真正的下拉框是第一个参数
function ISSimpleShopAdmin:onModChanged(comboBox)
	local index = (comboBox and comboBox.selected) or 1;
	self.mod = self.modOptions[index] or ALL_MODS;
	-- 一级变化后重建二级选项；当前分类在新模组下不存在时自动回退"全部分类"
	self:refreshCategoryOptions();
	self:rebuildList(true);
end

function ISSimpleShopAdmin:onCategoryChanged(comboBox)
	local index = (comboBox and comboBox.selected) or 1;
	self.category = self.categoryOptions[index] or ALL_CATEGORIES;
	self:rebuildList(true);
end

function ISSimpleShopAdmin:updateViewButtons()
	local function paint(button, active)
		if not button then return end
		if active then
			button.backgroundColor = { r = 0.18, g = 0.38, b = 0.22, a = 0.9 };
			button.textColor = { r = 1, g = 1, b = 0.75, a = 1 };
		else
			button.backgroundColor = { r = 0.08, g = 0.08, b = 0.08, a = 0.9 };
			button.textColor = { r = 0.8, g = 0.8, b = 0.8, a = 1 };
		end
	end
	paint(self.viewListedButton, not self.showAll);
	paint(self.viewAllButton, self.showAll);
end

-- 扫描物品脚本，按来源模组聚合物品类型（一级：模组，二级：物品类型）
function ISSimpleShopAdmin:rebuildFilters()
	local groups = {};   -- module -> { seen = {category=true}, list = {category...} }
	for _, script in ipairs(SimpleShopItemStore.getAllScriptItems()) do
		local module = script.module or SimpleShopItemStore.getModuleOf(script.itemType);
		local group = groups[module];
		if not group then
			group = { seen = {}, list = {} };
			groups[module] = group;
		end
		local category = script.category or "Other";
		if not group.seen[category] then
			group.seen[category] = true;
			group.list[#group.list + 1] = category;
		end
	end

	local modules = {};
	for module, group in pairs(groups) do
		table.sort(group.list, function(a, b)
			return string.lower(categoryLabel(a)) < string.lower(categoryLabel(b));
		end);
		modules[#modules + 1] = module;
	end
	-- 原版模块排最前，其余按显示名排序
	table.sort(modules, function(a, b)
		local aVanilla, bVanilla = (a == "Base"), (b == "Base");
		if aVanilla ~= bVanilla then return aVanilla; end
		return string.lower(moduleLabel(a)) < string.lower(moduleLabel(b));
	end);

	self.modCategories = groups;
	self.modList = modules;

	local combo = self.modCombo;
	combo:clear();
	combo.selected = 0;
	combo:addOption(getText("UI_SimpleShop_AllMods"));
	self.modOptions = { ALL_MODS };
	for _, module in ipairs(modules) do
		combo:addOption(moduleLabel(module));
		self.modOptions[#self.modOptions + 1] = module;
	end

	local selected = 1;
	for index, module in ipairs(self.modOptions) do
		if module == self.mod then
			selected = index;
			break;
		end
	end
	combo.selected = selected;

	self:refreshCategoryOptions();
end

-- 按当前一级（来源模组）重算二级（物品类型）选项
function ISSimpleShopAdmin:refreshCategoryOptions()
	local names, seen = {}, {};

	local function collect(list)
		for _, category in ipairs(list or {}) do
			if not seen[category] then
				seen[category] = true;
				names[#names + 1] = category;
			end
		end
	end

	if self.mod == ALL_MODS then
		for _, module in ipairs(self.modList or {}) do
			local group = self.modCategories and self.modCategories[module];
			if group then collect(group.list); end
		end
	else
		local group = self.modCategories and self.modCategories[self.mod];
		if group then collect(group.list); end
	end

	table.sort(names, function(a, b)
		return string.lower(categoryLabel(a)) < string.lower(categoryLabel(b));
	end);

	local combo = self.categoryCombo;
	combo:clear();
	combo.selected = 0;
	combo:addOption(getText("UI_SimpleShop_AllCategories"));
	self.categoryOptions = { ALL_CATEGORIES };
	for _, category in ipairs(names) do
		combo:addOption(categoryLabel(category));
		self.categoryOptions[#self.categoryOptions + 1] = category;
	end

	-- 当前分类不在新列表里时回退"全部分类"，避免筛出空结果
	local previous = self.category or ALL_CATEGORIES;
	local selected = 1;
	for index, category in ipairs(self.categoryOptions) do
		if category == previous then
			selected = index;
			break;
		end
	end
	self.category = self.categoryOptions[selected];
	combo.selected = selected;
end

-- **************************************************************************************
-- 过滤 + 分页
-- **************************************************************************************
function ISSimpleShopAdmin:passesFilters(scriptItem, searchLower, prices)
	if self.mod ~= ALL_MODS and scriptItem.module ~= self.mod then
		return false;
	end
	if self.category ~= ALL_CATEGORIES and scriptItem.category ~= self.category then
		return false;
	end
	if searchLower ~= "" then
		-- searchName/searchType 是缓存里预计算的小写键，避免对上万条物品反复 string.lower
		local nameKey = scriptItem.searchName or string.lower(scriptItem.itemName or "");
		local typeKey = scriptItem.searchType or string.lower(scriptItem.itemType or "");
		if not string.find(nameKey, searchLower, 1, true) and not string.find(typeKey, searchLower, 1, true) then
			return false;
		end
	end
	if not self.showAll and prices[scriptItem.itemType] == nil then
		return false;
	end
	return true;
end

-- 行排序：名称小写优先、同名前缀的按 fullType 稳定排序（与缓存排序口径一致）
local function rowBefore(a, b)
	local an = a.searchName or string.lower(a.itemName or a.itemType or "");
	local bn = b.searchName or string.lower(b.itemName or b.itemType or "");
	if an == bn then return (a.itemType or "") < (b.itemType or ""); end
	return an < bn;
end

function ISSimpleShopAdmin:rebuildList(resetPage)
	local prices = SimpleShopItemStore.getPrices() or {};
	local searchLower = string.lower(self.searchBox:getInternalText() or "");

	-- 直接引用脚本缓存条目：不复制行、不重复排序（缓存本身已按名称排好）
	local rows = {};
	for _, script in ipairs(SimpleShopItemStore.getAllScriptItems()) do
		if self:passesFilters(script, searchLower, prices) then
			rows[#rows + 1] = script;
		end
	end

	-- 已上架但脚本已不存在（来源模组被移除）的条目也能下架；单独排序后与主表归并，避免对整表重排
	local ghosts = nil;
	for itemType in pairs(prices) do
		if not SimpleShopItemStore.isKnownScriptItem(itemType) then
			local module = SimpleShopItemStore.getModuleOf(itemType);
			if (self.mod == ALL_MODS or module == self.mod) and self.category == ALL_CATEGORIES then
				local itemLower = string.lower(itemType);
				if searchLower == "" or string.find(itemLower, searchLower, 1, true) ~= nil then
					ghosts = ghosts or {};
					ghosts[#ghosts + 1] = {
						itemType = itemType,
						itemName = itemType,
						module = module,
						ghost = true,
						searchName = itemLower,
					};
				end
			end
		end
	end

	if ghosts then
		table.sort(ghosts, rowBefore);
		local merged = {};
		local i, j = 1, 1;
		while i <= #rows or j <= #ghosts do
			if j > #ghosts or (i <= #rows and not rowBefore(ghosts[j], rows[i])) then
				merged[#merged + 1] = rows[i];
				i = i + 1;
			else
				merged[#merged + 1] = ghosts[j];
				j = j + 1;
			end
		end
		rows = merged;
	end

	self.filtered = rows;
	self.pageCount = math.max(1, math.ceil(#rows / self.pageSize));
	self.page = resetPage and 1 or math.min(self.page, self.pageCount);
	if self.page < 1 then self.page = 1; end

	self:updateCountLabel();
	self:renderPage();
end

-- 已上架计数右对齐到列表右边缘：ISLabel 只支持左对齐，所以按文本宽度回算 x
function ISSimpleShopAdmin:updateCountLabel()
	if not self.countLabel then return; end
	local text = getText("UI_SimpleShop_ListedCount") .. ": " .. SimpleShopItemStore.getCount();
	self.countLabel.name = text;
	local textW = getTextManager():MeasureStringX(UIFont.Small, text);
	self.countLabel.width = textW;
	self.countLabel:setX(self.width - PAD - textW);
end

function ISSimpleShopAdmin:renderPage()
	local list = self.itemList;
	list:clear();
	list.selected = 0;
	list:setYScroll(0);

	local startIndex = (self.page - 1) * self.pageSize + 1;
	local endIndex = math.min(startIndex + self.pageSize - 1, #self.filtered);
	for index = startIndex, endIndex do
		local row = self.filtered[index];
		list:addItem(row.itemName or row.itemType, row);
	end

	if self.selectedType then
		for index, entry in ipairs(list.items) do
			if entry.item.itemType == self.selectedType then
				list.selected = index;
				break;
			end
		end
	end

	self.pageLabel.name = getText("UI_SimpleShop_PageInfo") .. " " .. self.page .. " / " .. self.pageCount
		.. "    " .. getText("UI_SimpleShop_Total") .. ": " .. #self.filtered;

	self.prevButton.enable = self.page > 1;
	self.nextButton.enable = self.page < self.pageCount;
end

function ISSimpleShopAdmin:onPrevPage(button)
	if self.page > 1 then
		self.page = self.page - 1;
		self:renderPage();
	end
end

function ISSimpleShopAdmin:onNextPage(button)
	if self.page < self.pageCount then
		self.page = self.page + 1;
		self:renderPage();
	end
end

-- **************************************************************************************
-- 列表渲染：图标 / 名称 / ID / 已上架标记 / 价格
-- **************************************************************************************
function ISSimpleShopAdmin:drawListItem(list, y, item, alt)
	local data = item.item;
	local width = list:getWidth();
	local height = list.itemheight;
	local scrollWidth = 0;
	if list.vscroll and list.vscroll:getHeight() < list:getScrollHeight() then
		scrollWidth = list.vscroll:getWidth();
	end
	local rightEdge = width - 14 - scrollWidth;

	list:setStencilRect(0, 0, width, list:getHeight());

	if list.selected == item.index then
		list:drawRect(0, y, width, height, 0.45, 0.25, 0.5, 0.45);
	elseif alt then
		list:drawRect(0, y, width, height, 0.35, 0.07, 0.07, 0.07);
	end
	list:drawRect(0, y + height - 1, width, 1, 0.3, 0.35, 0.35, 0.35);

	-- 图标、文本块、价格徽标都按行高与字体高度垂直居中，改 ITEM_HEIGHT 不必再逐处调偏移
	local fontH = self.rowFontH or 14;
	local iconSize = math.min(40, height - 16);
	local iconX = 10;
	local textX = iconX + iconSize + 10;
	local texture = self:getIconTexture(data);
	if texture then
		list:drawTexture(texture, iconX, y + math.floor((height - iconSize) / 2), 1, iconSize, iconSize, 1);
	end

	-- 名称 + ID 两行作为一个文本块整体居中：两行文字 + 行距 6
	local textWidth = rightEdge - textX - self.priceAreaWidth;
	local textBlockH = fontH * 2 + 6;
	local nameY = y + math.floor((height - textBlockH) / 2);
	local idY = nameY + fontH + 6;
	list:drawText(self:trimText(data.itemName or data.itemType, textWidth), textX, nameY, 1, 1, 1, 1, UIFont.Small);
	list:drawText(self:trimText(data.itemType, textWidth), textX, idY, 0.62, 0.62, 0.62, 1, UIFont.Small);

	-- 徽标高度 = 字体高度 + 上下内边距，保证背景始终罩住文字
	local price = SimpleShopItemStore.getPrice(data.itemType);
	local badgeH = fontH + 8;
	local badgeY = y + math.floor((height - badgeH) / 2);
	local badgeTextY = badgeY + math.floor((badgeH - fontH) / 2);
	if price ~= nil then
		local badgeX = rightEdge - self.priceAreaWidth;
		list:drawRect(badgeX, badgeY, self.badgeWidth, badgeH, 0.9, 0.18, 0.45, 0.22);
		list:drawText(self.badgeText, badgeX + 6, badgeTextY, 0.85, 1, 0.88, 1, UIFont.Small);
		list:drawTextRight("$" .. tostring(price), rightEdge, badgeTextY, 1, 0.92, 0.45, 1, UIFont.Small);
	else
		list:drawTextRight(getText("UI_SimpleShop_NotListed"), rightEdge, badgeTextY, 0.62, 0.62, 0.62, 1, UIFont.Small);
	end

	list:clearStencilRect();
	return y + height;
end

-- 超出列宽时按 UTF-8 字符边界截断并加省略号，避免与右侧价格区域重叠
function ISSimpleShopAdmin:trimText(text, maxWidth)
	text = tostring(text or "");
	if maxWidth <= 0 then return ""; end

	local manager = getTextManager();
	if manager:MeasureStringX(UIFont.Small, text) <= maxWidth then
		return text;
	end

	local cut = #text;
	while cut > 1 do
		cut = cut - 1;
		-- 回退到字符起始字节（UTF-8 续字节为 128..191），避免截断多字节字符
		while cut > 1 do
			local byte = string.byte(text, cut) or 0;
			if byte < 128 or byte >= 192 then break; end
			cut = cut - 1;
		end
		local candidate = string.sub(text, 1, cut - 1) .. "…";
		if manager:MeasureStringX(UIFont.Small, candidate) <= maxWidth then
			return candidate;
		end
	end
	return "…";
end

function ISSimpleShopAdmin:getIconTexture(data)
	local key = data.itemType;
	local cached = self.iconCache[key];
	if cached ~= nil then
		return cached or nil;
	end

	local texture = nil;
	-- 优先取真实物品实例的图标（自带模组贴图），失败再按脚本 icon 名拼 Item_ 查找
	local item = instanceItem(key);
	if item then
		local ok, result = pcall(function() return item:getTexture(); end);
		if ok then texture = result; end
	end
	if not texture and data.iconName and type(tryGetTexture) == "function" then
		local ok, result = pcall(tryGetTexture, "Item_" .. tostring(data.iconName));
		if ok then texture = result; end
	end

	self.iconCache[key] = texture or false;
	return texture;
end

-- **************************************************************************************
-- 交互
-- **************************************************************************************
-- ISScrollingListBox:setOnMouseDownFunction 的回调实际按 fn(target, item) 调用，
-- target 就是本窗口，所以方法只能声明 (self, item)：多写一个 target 会让 data 恒为 nil
function ISSimpleShopAdmin:onSelectItem(data)
	if not data or not data.itemType then return; end
	self.selectedType = data.itemType;
	local price = SimpleShopItemStore.getPrice(data.itemType);
	if price ~= nil then
		self.priceEntry:setText(tostring(price));
	else
		self.priceEntry:setText("");
	end
	self:setStatus(data.itemName or data.itemType, false);
end

-- 当前选中物品：优先读列表自身选中行，selectedType 只作回退
-- （鼠标回调未触发 / 刷新后选中行被清空时，也不会把"已选中"判成"未选中"）
function ISSimpleShopAdmin:getSelectedItem()
	local list = self.itemList;
	local entry = list and list.items and list.items[list.selected or 0];
	local data = entry and entry.item;
	if data and data.itemType then
		return data;
	end

	if self.selectedType then
		local filtered = self.filtered;
		if filtered then
			for i = 1, #filtered do
				if filtered[i].itemType == self.selectedType then
					return filtered[i];
				end
			end
		end
	end
	return nil;
end

function ISSimpleShopAdmin:onSetPrice(button)
	local data = self:getSelectedItem();
	if not data then
		self:setStatus(getText("UI_SimpleShop_SelectItem"), true);
		return;
	end

	local cost = SimpleShopItemStore.sanitizePrice(self.priceEntry:getInternalText());
	if not cost then
		self:setStatus(getText("UI_SimpleShop_InvalidPrice"), true);
		return;
	end

	self.selectedType = data.itemType;
	if SimpleShopItemStore.setPrice(data.itemType, cost) then
		self:setStatus(getText("UI_SimpleShop_PriceSaved") .. " " .. data.itemType .. " = " .. tostring(cost), false);
	else
		self:setStatus(getText("UI_SimpleShop_NoPermission"), true);
	end
	self.needRefresh = true;
end

function ISSimpleShopAdmin:onRemovePrice(button)
	local data = self:getSelectedItem();
	if not data then
		self:setStatus(getText("UI_SimpleShop_SelectItem"), true);
		return;
	end
	if not SimpleShopItemStore.hasPrice(data.itemType) then
		self:setStatus(getText("UI_SimpleShop_NotListedHint"), true);
		return;
	end

	self.selectedType = data.itemType;
	if SimpleShopItemStore.removePrice(data.itemType) then
		self:setStatus(getText("UI_SimpleShop_PriceRemoved") .. " " .. data.itemType, false);
	else
		self:setStatus(getText("UI_SimpleShop_NoPermission"), true);
	end
	self.needRefresh = true;
end

function ISSimpleShopAdmin:onResetPrices(button)
	if SimpleShopItemStore.resetToDefault() then
		self:setStatus(getText("UI_SimpleShop_PricesReset"), false);
	else
		self:setStatus(getText("UI_SimpleShop_NoPermission"), true);
	end
	self.needRefresh = true;
end

function ISSimpleShopAdmin:onCloseMouseDown(button)
	if button and button.internal == "close" then
		self:setVisible(false);
	end
end

function ISSimpleShopAdmin:close()
	self:setVisible(false);
end

function ISSimpleShopAdmin:setStatus(text, isError)
	if self.statusLabel then
		-- 状态文案可能带物品类型名，超宽会画出窗口右边缘，先按可用宽度截断
		self.statusLabel.name = self:trimText(tostring(text or ""), self.width - PAD * 2);
		self.statusLabel.r = isError and 0.95 or 0.85;
		self.statusLabel.g = isError and 0.45 or 0.85;
		self.statusLabel.b = isError and 0.45 or 0.65;
	end
end

-- **************************************************************************************
-- 每帧检查是否需要刷新（搜索输入 / 价格同步后延迟刷新，避免频繁重建）
-- **************************************************************************************
function ISSimpleShopAdmin:update()
	ISCollapsableWindow.update(self);
	if self.needRefresh then
		local now = getTimestampMs();
		if now >= (self.nextRefresh or 0) then
			self.needRefresh = false;
			self.nextRefresh = now + 120;
			self:rebuildList(false);
		end
	end
end

function ISSimpleShopAdmin:new(x, y, width, height, playerNum, settings)
	local o = {};
	o = ISCollapsableWindow:new(x, y, width, height);
	setmetatable(o, self);
	self.__index = self;
	o.playerId = playerNum;
	o.settings = settings;
	o.title = getText("UI_SimpleShop_AdminTitle");
	o.resizable = false;
	o:setResizable(false);
	return o;
end
