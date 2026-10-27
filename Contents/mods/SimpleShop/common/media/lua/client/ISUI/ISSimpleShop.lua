require "ISUI/ISCollapsableWindow"
require "SimpleShop"
require "SimpleShopDataManager"
require "SimpleShopItemStore"
require "SimpleShopClientCommands"

ISSimpleShop = ISCollapsableWindow:derive("ISSimpleShop");

function ISSimpleShop:initialise()
	ISCollapsableWindow.initialise(self);
	self:create();
end

function ISSimpleShop:render()
	local margin = self.margin or 20;

	-- 更新显示信息
	if self.playerLabel then
		self.playerLabel.name = self.char:getDescriptor():getForename().." "..self.char:getDescriptor():getSurname();
	end
	-- 商品数量紧跟在玩家名右侧（限制最大 x，避免和右侧金钱重叠）
	if self.countLabel and self.playerLabel and self.playerLabel.name then
		local nameWidth = getTextManager():MeasureStringX(UIFont.Medium, self.playerLabel.name);
		local countX = margin + math.max(120, nameWidth) + 24;
		self.countLabel:setX(math.min(countX, self.width - margin - 180));
	end
	-- 使用新的API获取玩家金钱，并按文字宽度右对齐
	if self.moneyLabel then
		local playerMoney = SimpleShop.GetPlayerMoney() or 0;
		local moneyText = getText("UI_SimpleShop_Money") .. ": " .. playerMoney;
		self.moneyLabel.name = moneyText;
		local moneyWidth = getTextManager():MeasureStringX(UIFont.Small, moneyText);
		self.moneyLabel:setX(self.width - margin - moneyWidth);
	end

	-- 绘制窗口边框
	local borderWidth = 2
	self:drawRectBorder(0, 0, self.width, self.height, borderWidth, 0.7, 0.7, 0.7, 1)

	-- 调用父类的render方法
	ISCollapsableWindow.render(self);
end

-- **************************************************************************************
-- 底部操作按钮：文案长度随语言/字号变化（英文 "Manage Items" 比"管理商品"长得多），
-- 先量文案算宽度、必要时加宽窗口，再按最终宽度摆按钮，避免整排按钮被窗口边缘裁掉
-- **************************************************************************************
function ISSimpleShop:buildActionButtonDefs()
	-- 管理员（且本机模组选项勾了"显示管理按钮"、世界沙箱开了"允许配置商品"）额外显示"管理商品"按钮
	local canManage = SimpleShop.canShowManageButton(self.playerId);
	local defs = {
		{ text = getText("UI_SimpleShop_Buy") .. " x1", internal = "buy1", onclick = function() self:onBuyMouseDown(1) end },
		{ text = getText("UI_SimpleShop_Buy") .. " x5", internal = "buy5", onclick = function() self:onBuyMouseDown(5) end },
		{ text = getText("UI_SimpleShop_Buy") .. " x10", internal = "buy10", onclick = function() self:onBuyMouseDown(10) end },
	};
	if canManage then
		defs[#defs + 1] = { text = getText("UI_SimpleShop_Manage"), internal = "admin", onclick = function() SimpleShop.showAdminScreen(self.playerId) end };
	end
	defs[#defs + 1] = { text = getText("UI_SimpleShop_Close"), internal = "close", onclick = self.onCloseMouseDown };
	return defs, canManage and true or false;
end

-- 按最长文案统一按钮宽度；整排放不进窗口时先加宽窗口，仍不行再依次收间距、收内边距
function ISSimpleShop:layoutActionButtons(margin)
	local defs, canManage = self:buildActionButtonDefs();
	local count = #defs;
	local height = 30;
	local gap = 10;
	local sidePadding = 22;   -- 文字左右各留 11px
	local minWidth = 80;

	local maxTextWidth = 0;
	for _, def in ipairs(defs) do
		local textWidth = getTextManager():MeasureStringX(UIFont.Small, def.text);
		if textWidth > maxTextWidth then
			maxTextWidth = textWidth;
		end
	end
	local width = math.max(minWidth, math.ceil(maxTextWidth) + sidePadding);

	local function rowWidth(w, g)
		return w * count + g * (count - 1);
	end

	local screenWidth = getPlayerScreenWidth(self.playerId) or getCore():getScreenWidth();
	local available = self.width - margin * 2;

	-- 1) 优先加宽窗口（上限为屏幕宽度 - 20），保证每个按钮都能完整显示文字
	if rowWidth(width, gap) > available then
		local needed = math.ceil(rowWidth(width, gap)) + margin * 2;
		local maxWindowWidth = math.max(self.width, math.floor(screenWidth - 20));
		local targetWidth = math.min(needed, maxWindowWidth);
		if targetWidth > self.width then
			self:setWidth(targetWidth);
			self:setX(math.max(0, math.floor((screenWidth - targetWidth) / 2)));
			available = self.width - margin * 2;
		end
	end

	-- 2) 窗口已到屏幕上限还放不下：先收间距，再收按钮内边距
	while gap > 4 and rowWidth(width, gap) > available do
		gap = gap - 2;
	end
	while width > minWidth and rowWidth(width, gap) > available do
		width = width - 2;
	end
	-- 3) 极端窄屏兜底：按可用宽度均分，宁可文字略挤也不越出窗口
	if rowWidth(width, gap) > available then
		width = math.max(40, math.floor((available - gap * (count - 1)) / count));
	end

	local startX = math.max(margin, math.floor((self.width - rowWidth(width, gap)) / 2));
	return { defs = defs, canManage = canManage, width = width, height = height, gap = gap, startX = startX };
end

function ISSimpleShop:create()
	-- 使用统一的边距变量（render 中对齐也要用）
	local margin = 20;
	self.margin = margin;

	-- 先算底部按钮布局（可能顺带加宽窗口），面板宽度必须用加宽后的值
	local actionLayout = self:layoutActionButtons(margin);

	-- 创建内部面板以放置内容，增加标题栏高度
	local titleHeight = self:titleBarHeight();
	local panelHeight = self.height - titleHeight;
	self.panel = ISPanel:new(0, titleHeight, self.width, panelHeight);
	self.panel:initialise();
	self.panel:instantiate();
	self:addChild(self.panel);

	local y = 10;

	-- 第一行：玩家信息和金钱（左侧）
	self.playerLabel = ISLabel:new(margin, y, 20, "", 1, 1, 1, 1, UIFont.Medium);
	self.playerLabel:initialise();
	self.playerLabel:instantiate();
	self.panel:addChild(self.playerLabel);

	-- 商品数量显示在玩家名右侧
	self.countLabel = ISLabel:new(margin + 150, y + 4, 16, "", 0.8, 0.8, 0.8, 1, UIFont.Small);
	self.countLabel:initialise();
	self.countLabel:instantiate();
	self.panel:addChild(self.countLabel);

	-- 金钱显示在右侧（render 中按文字宽度对齐到右边缘）
	self.moneyLabel = ISLabel:new(0, y, 16, "", 1, 1, 0, 1, UIFont.Small);
	self.moneyLabel:initialise();
	self.moneyLabel:instantiate();
	self.panel:addChild(self.moneyLabel);

	y = y + 30;

	-- 第二行：分类 / 排序 / 搜索 三个控件同一行，等高等距
	--   高度统一按字体算出后三个控件共用；输入框额外显式同步 Java 控件高度，
	--   底色与边框也统一成下拉框那一套，避免一亮一暗看起来像两个高度
	local controlH = math.max(25, (getTextManager():getFontHeight(UIFont.Small) or 14) + 8);
	local controlGap = 10;
	local controlY = y - 2;
	local controlsWidth = self.width - margin * 2 - controlGap * 2;
	local categoryWidth = math.floor(controlsWidth * 0.34);
	local sortWidth = math.floor(controlsWidth * 0.30);
	local searchWidth = controlsWidth - categoryWidth - sortWidth;
	local sortX = margin + categoryWidth + controlGap;
	local searchX = sortX + sortWidth + controlGap;

	self.categoryCombo = ISComboBox:new(margin, controlY, categoryWidth, controlH);
	self.categoryCombo:initialise();
	self.categoryCombo:instantiate();
	self.categoryCombo:setHeight(controlH);
	self.categoryCombo.font = UIFont.Small;
	-- ISComboBox 触发 onChange(target, comboBox)，必须走 setOnChange 指定 target
	self.categoryCombo:setOnChange(self, self.onCategorySelected);
	self.panel:addChild(self.categoryCombo);
	
	-- 搜索框在右侧
	self.searchBox = ISTextEntryBox:new("", searchX, controlY, searchWidth, controlH);
	self.searchBox:initialise();
	self.searchBox:instantiate();
	self.searchBox:setFont(UIFont.Small);
	self.searchBox:setHeight(controlH);
	-- 与 ISComboBox 同一套配色（纯黑底 + 0.5 白框），否则半透明底和亮边框会显得更高
	self.searchBox.backgroundColor = { r = 0, g = 0, b = 0, a = 1 };
	self.searchBox.borderColor = { r = 1, g = 1, b = 1, a = 0.5 };
	-- ISTextEntryBox 只有 onTextChangeFunction(target, box) 会被调用
	self.searchBox.target = self;
	self.searchBox.onTextChangeFunction = function(target, box)
		self:applyFiltersAndUpdateView();
	end
	self.panel:addChild(self.searchBox);

	-- 排序下拉框（与分类、搜索同一行，不换行）
	self.sortCombo = ISComboBox:new(sortX, controlY, sortWidth, controlH);
	self.sortCombo:initialise();
	self.sortCombo:instantiate();
	self.sortCombo:setHeight(controlH);
	self.sortCombo.font = UIFont.Small;
	self.sortCombo:setOnChange(self, self.onSortSelected);
	self.sortCombo.tooltip = getText("UI_SimpleShop_SortTooltip");
	self.panel:addChild(self.sortCombo);

	-- 底部按钮区域：等宽、等间距、整体居中（宽度/间距已由 layoutActionButtons 按文案算好）
	local buttonHeight = actionLayout.height;
	local buttonY = panelHeight - margin - buttonHeight;

	local actionButtons = {};
	for index, def in ipairs(actionLayout.defs) do
		local x = actionLayout.startX + (actionLayout.width + actionLayout.gap) * (index - 1);
		actionButtons[index] = self:createActionButton(x, buttonY, actionLayout.width, buttonHeight, def.text, def.internal, def.onclick);
	end

	self.buyButton1 = actionButtons[1];
	self.buyButton5 = actionButtons[2];
	self.buyButton10 = actionButtons[3];
	if actionLayout.canManage then
		self.adminButton = actionButtons[4];
		self.closeButton = actionButtons[5];
	else
		self.adminButton = nil;
		self.closeButton = actionButtons[4];
	end
	-- 记下本次布局用的判定结果：沙箱开关变化后由 showUpgradeScreen 比对并重建窗口
	self.manageAllowed = actionLayout.canManage and true or false;

	-- 列表区域：铺满左右边距，与上方筛选行、下方按钮各留一段间隔，避免贴在一起显得拥挤
	local listGap = 14;
	local listY = controlY + controlH + listGap;
	local listWidth = self.width - (margin * 2);
	local listHeight = buttonY - listY - listGap;

	-- 创建标准滚动列表框
	self.itemList = ISScrollingListBox:new(margin, listY, listWidth, listHeight)
	self.itemList:initialise()
	self.itemList:instantiate()
	self.itemList.backgroundColor = {r=0.05, g=0.05, b=0.05, a=0.8}
	self.itemList.borderColor = {r=0.6, g=0.6, b=0.6, a=1}
	self.itemList.borderWidth = 2
	self.itemList.itemheight = 40  -- 设置每个列表项的高度
	self.itemList.drawBorder = true  -- 确保绘制边框
	
	-- 初始化数据管理器并设置UI
	self:initializeDataManager()
	
	-- 设置列表项渲染函数
	function self.itemList:doDrawItem(y, item, alt)
		-- 设置剪切区域，确保内容不会超出列表边界
		self:setStencilRect(0, 0, self.width, self.height)
		
		-- 绘制项目背景边框 - 更明显的边框
		self:drawRectBorder(0, y, self:getWidth(), self.itemheight, 3, 0.5, 0.5, 0.5, 0.8)
		
		if self.selected == item.index then
			self:drawRect(0, y, self:getWidth(), self.itemheight, 0.3, 0.7, 0.7, 0.3)
		end
		
		-- 计算垂直居中位置
		local textY = y + (self.itemheight - 20) / 2  -- 假设文本高度为20像素
		local iconY = y + (self.itemheight - 30) / 2  -- 图标高度调整为30像素
		
		-- 绘制图标
		if item.item.icon then
			self:drawTexture(item.item.icon, 10, iconY, 1, 30, 30, 1)
		end
		
		-- 绘制物品名称
		self:drawText(item.item.itemName, 60, textY, 1, 1, 1, 1, UIFont.Small)
		
		-- 绘制价格（向左移动避免数字过大显示不全）
		self:drawText("$" .. tostring(item.item.cost), self:getWidth() - 100, textY, 1, 1, 0, 1, UIFont.Small)
		
		-- 绘制分类信息（如果可用）
		if item.item.category then
			local categoryText = getText("IGUI_ItemCat_" .. item.item.category)
			self:drawText(categoryText, self:getWidth() - 200, textY, 0.7, 0.7, 0.7, 0.7, UIFont.Small)
		end
		
		-- 清除剪切区域
		self:clearStencilRect()
		
		return y + self.itemheight
	end
	
	self.panel:addChild(self.itemList)
end

function ISSimpleShop:onBuyMouseDown(quantity)
	quantity = quantity or 1
	if self.itemList.selected >= 1 then
		local selectedItem = self.itemList.items[self.itemList.selected]
		if selectedItem and selectedItem.item then
			local itemType = selectedItem.item.itemType
			-- 以当前生效的价格表为准（服务端也会独立校验一次）
			local unitCost = SimpleShopItemStore.getPrice(itemType) or selectedItem.item.cost
			if not unitCost then return end
			local totalCost = unitCost * quantity

			-- 检查是否为联机模式（连接到远程服务器）
			if isClient() then
				-- 联机模式：发送请求到服务器
				if SimpleShopClientCommands.SendPurchaseRequest(selectedItem.item.itemType, quantity, totalCost) then
					-- 请求已发送，等待服务器响应
					return
				end
			end

			-- 单人模式或主机模式：本地处理
			-- 价格为 0 视为免费领取，跳过金钱校验
			if totalCost > 0 then
				-- 使用新的API检查是否有足够金钱
				if not SimpleShop.HasEnoughMoney(totalCost) then
					return;
				end
				-- 使用新的API扣除金钱
				if not SimpleShop.RemovePlayerMoney(totalCost) then
					return;
				end
			end

			-- 批量添加物品到玩家背包
			self.char:getInventory():AddItems(itemType, quantity);
			-- 使用新的API获取更新后的金钱并更新显示
			local newMoney = SimpleShop.GetPlayerMoney();
			if self.moneyLabel and newMoney ~= nil then
				self.moneyLabel.name = getText("UI_SimpleShop_Money") .. ": " .. newMoney;
			end
		end
	end
end

-- **************************************************************************************
-- 创建底部操作按钮
-- **************************************************************************************
function ISSimpleShop:createActionButton(x, y, width, height, text, internal, onclick)
	local button = ISButton:new(x, y, width, height, text, self, onclick);
	button:initialise();
	button.internal = internal;
	button.borderColor = {r=0.7, g=0.7, b=0.7, a=1};
	button:setFont(UIFont.Small);
	button:ignoreWidthChange();
	button:ignoreHeightChange();
	self.panel:addChild(button);
	return button;
end

-- ISComboBox 回调签名 (target, comboBox)：target 已作为 self 传入
function ISSimpleShop:onCategorySelected(comboBox)
	self:applyFiltersAndUpdateView();
end

-- 排序下拉框回调（同样由 setOnChange 指定 target）
function ISSimpleShop:onSortSelected(comboBox)
	self:applyFiltersAndUpdateView();
end

function ISSimpleShop:onCloseMouseDown(button, x, y)
	if button.internal == "close" then
		self:setVisible(false);
		-- 不调用removeFromUIManager，这样可以保留窗口对象
		-- 只是将它隐藏，下次可以再次显示
	end
end

-- **************************************************************************************
-- 数据管理器初始化
-- **************************************************************************************
function ISSimpleShop:initializeDataManager()
	-- 创建数据管理器实例
	self.dataManager = SimpleShopDataManager:new(self.settings)
	
	-- 填充分类下拉框
	self.categoryCombo:clear()
	local categoryNames = self.dataManager:getCategoryNames()
	
	for _, categoryName in ipairs(categoryNames) do
		local displayName = self.dataManager:getCategoryDisplayName(categoryName)
		self.categoryCombo:addOption(displayName)
	end
	
	-- 默认选择"所有分类"
	self.categoryCombo.selected = 1

	-- 排序选项固定，只在首次构建时填充；刷新数据管理器时保留玩家当前选择
	if self.sortCombo and #self.sortCombo.options == 0 then
		for _, mode in ipairs(SimpleShopDataManager.SORT_MODES) do
			self.sortCombo:addOption(SimpleShopDataManager.getSortLabel(mode))
		end
		self.sortCombo.selected = 1
	end

	-- 初始显示所有商品
	self:applyFiltersAndUpdateView()
end

-- **********************************************************************************
-- 商品清单或价格变化后重建数据管理器（尽量保留当前筛选条件）
-- **********************************************************************************
function ISSimpleShop:refreshDataManager()
	local previousCategory = nil;
	if self.categoryCombo and self.categoryCombo.selected and self.categoryCombo.selected >= 1 then
		previousCategory = self.categoryCombo:getOptionText(self.categoryCombo.selected);
	end

	self:initializeDataManager();

	if previousCategory then
		for index = 1, #self.categoryCombo.options do
			if self.categoryCombo:getOptionText(index) == previousCategory then
				self.categoryCombo.selected = index;
				break;
			end
		end
	end

	self:applyFiltersAndUpdateView();
end

-- **********************************************************************************
-- 应用筛选条件并更新视图
-- **********************************************************************************
function ISSimpleShop:applyFiltersAndUpdateView()
	-- 获取当前筛选条件
	local searchText = self.searchBox:getInternalText()
	local selectedCategoryName = self.categoryCombo:getOptionText(self.categoryCombo.selected)
	
	-- 将显示名称转换为内部分类名称
	local category = "all"
	if selectedCategoryName ~= getText("UI_SimpleShop_AllCategories") then
		for _, catName in ipairs(self.dataManager:getCategoryNames()) do
			if catName ~= "all" then
				local displayName = self.dataManager:getCategoryDisplayName(catName)
				if displayName == selectedCategoryName then
					category = catName
					break
				end
			end
		end
	end
	
	-- 当前排序模式（下拉框下标 -> 模式名）
	local sortMode = nil
	if self.sortCombo and self.sortCombo.selected and self.sortCombo.selected >= 1 then
		sortMode = SimpleShopDataManager.SORT_MODES[self.sortCombo.selected]
	end

	-- 应用筛选与排序条件到数据管理器
	self.dataManager:applyFilters(category, searchText, sortMode)

	-- 更新视图
	self:updateItemListView()
end

-- **********************************************************************************
-- 更新物品列表视图
-- **********************************************************************************
function ISSimpleShop:updateItemListView()
	-- 记录当前选中项，排序/筛选后尽量保持选中同一件商品
	local previousType = nil
	if self.itemList.selected and self.itemList.selected >= 1 then
		local entry = self.itemList.items[self.itemList.selected]
		if entry and entry.item then
			previousType = entry.item.itemType
		end
	end

	-- 清空当前列表
	self.itemList:clear()

	-- 从数据管理器获取筛选后的商品数据
	local filteredItems = self.dataManager:getFilteredItems()

	-- 添加商品到列表
	for _, itemData in ipairs(filteredItems) do
		self.itemList:addItem(itemData.displayName, itemData)
	end

	-- 恢复选择（商品未在结果中时保持未选中）
	self.itemList.selected = 0
	if previousType then
		for index, entry in ipairs(self.itemList.items) do
			if entry.item and entry.item.itemType == previousType then
				self.itemList.selected = index
				break
			end
		end
	end

	self:updateCountLabel(#filteredItems)
end

-- 商品数量标签（位置在 render 里按玩家名宽度对齐）
function ISSimpleShop:updateCountLabel(count)
	if not self.countLabel then return end
	self.countLabel.name = getText("UI_SimpleShop_ItemCount") .. ": " .. tostring(count or 0)
end

function ISSimpleShop:new(x, y, width, height, player, settings)
	local o = {};
	o = ISCollapsableWindow:new(x, y, width, height);
	setmetatable(o, self);
    self.__index = self;
	o.char = getSpecificPlayer(player);
	o.playerId = player;
	o.settings = settings;
	o.title = getText("UI_SimpleShop_WindowTitle");
	o.resizable = false;
	o:setResizable(false);
	return o;
end