require "ISUI/ISCollapsableWindow"
require "SimpleShop"
require "SimpleShopDataManager"

ISSimpleShop = ISCollapsableWindow:derive("ISSimpleShop");

function ISSimpleShop:initialise()
	ISCollapsableWindow.initialise(self);
	self:create();
end

function ISSimpleShop:render()
	-- 更新显示信息
	if self.playerLabel then
		self.playerLabel.name = self.char:getDescriptor():getForename().." "..self.char:getDescriptor():getSurname();
	end
	-- 使用新的API获取玩家金钱
	if self.moneyLabel then
		local playerMoney = SimpleShop.GetPlayerMoney() or 0;
		self.moneyLabel.name = getText("UI_SimpleShop_Money") .. ": " .. playerMoney;
	end

	-- 绘制窗口边框
	local borderWidth = 2
	self:drawRectBorder(0, 0, self.width, self.height, borderWidth, 0.7, 0.7, 0.7, 1)

	-- 调用父类的render方法
	ISCollapsableWindow.render(self);
end

function ISSimpleShop:create()
	-- 创建内部面板以放置内容，增加标题栏高度
	local titleHeight = self:titleBarHeight();
	local panelHeight = self.height - titleHeight;
	self.panel = ISPanel:new(0, titleHeight, self.width, panelHeight);
	self.panel:initialise();
	self.panel:instantiate();
	self:addChild(self.panel);

	local y = 10;

	-- 使用统一的边距变量
	local margin = 20;

	-- 第一行：玩家信息和金钱（左侧）
	self.playerLabel = ISLabel:new(margin, y, 20, "", 1, 1, 1, 1, UIFont.Medium);
	self.playerLabel:initialise();
	self.playerLabel:instantiate();
	self.panel:addChild(self.playerLabel);

	-- 金钱显示在玩家信息右侧
	self.moneyLabel = ISLabel:new(self.width - margin - 150, y, 16, "", 1, 1, 0, 1, UIFont.Small);
	self.moneyLabel:initialise();
	self.moneyLabel:instantiate();
	self.panel:addChild(self.moneyLabel);

	y = y + 30;

	-- 第二行：分类选择器和搜索框并排显示
	-- 分类选择器在左侧，占据50%宽度
	local comboWidth = (self.width - margin * 3) * 0.5; -- 50%宽度，留出间距
	self.categoryCombo = ISComboBox:new(margin, y - 2, comboWidth, 25);
	self.categoryCombo:initialise();
	self.categoryCombo:instantiate();
	self.categoryCombo.font = UIFont.Small;
	-- 创建一个闭包函数来处理选择变化事件
	self.categoryCombo.onChange = function(target)
		local searchText = self.searchBox:getInternalText()
		self:applyFiltersAndUpdateView()
	end
	self.panel:addChild(self.categoryCombo);
	
	-- 搜索框在右侧，占据50%宽度
	local searchWidth = (self.width - margin * 3) * 0.5; -- 50%宽度
	local searchX = margin + comboWidth + margin; -- 分类框宽度+间距
	self.searchBox = ISTextEntryBox:new("", searchX, y - 2, searchWidth, 25);
	self.searchBox:initialise();
	self.searchBox:instantiate();
	self.searchBox.font = UIFont.Small;
	-- 创建一个闭包函数来处理文本变化事件
	self.searchBox.onTextChange = function(target)
		local searchText = target:getInternalText()
		self:applyFiltersAndUpdateView()
	end
	self.panel:addChild(self.searchBox);

	y = y + 30;

	-- 在底部添加按钮区域，居中显示
	local buttonWidth = 90; -- 增加按钮宽度
	local buttonHeight = 30; -- 增加按钮高度
	local buttonSpacing = 15; -- 增加按钮间距
	local totalButtonWidth = buttonWidth * 2 + buttonSpacing;
	local buttonStartX = (self.width - totalButtonWidth) / 2; -- 居中显示
	local buttonY = self.height - margin - buttonHeight - 10; -- 离底部与按钮高度相匹配的边距
	
	-- 创建购买按钮
	self.buyButton = ISButton:new(buttonStartX, buttonY, buttonWidth, buttonHeight, getText("UI_SimpleShop_Buy"), self, self.onBuyMouseDown);
	self.buyButton:initialise();
	self.buyButton.internal = "buy";
	self.buyButton.borderColor = {r=0.7, g=0.7, b=0.7, a=1};
	self.buyButton:setFont(UIFont.Small);
	self.buyButton:ignoreWidthChange();
	self.buyButton:ignoreHeightChange();
	-- 添加到主面板，确保它在滚动面板之后添加，层级更高
	self.panel:addChild(self.buyButton);

	-- 创建关闭按钮，与购买按钮在同一行
	self.closeButton = ISButton:new(buttonStartX + buttonWidth + buttonSpacing, buttonY, buttonWidth, buttonHeight, getText("UI_SimpleShop_Close"), self, self.onCloseMouseDown);
	self.closeButton:initialise();
	self.closeButton.internal = "close";
	self.closeButton.borderColor = {r=0.7, g=0.7, b=0.7, a=1};
	self.closeButton:setFont(UIFont.Small);
	self.closeButton:ignoreWidthChange();
	self.closeButton:ignoreHeightChange();
	-- 添加到主面板，确保它在滚动面板之后添加，层级更高
	self.panel:addChild(self.closeButton);

	-- 计算可用空间，预留边距和按钮空间
	local margin = 20; -- 统一边距
	local listWidth = self.width - (margin * 2); -- 左右对称边距
	local listHeight = buttonY - y - 10; -- 精确计算列表高度，从当前y位置到按钮上方的距离

	-- 创建标准滚动列表框
	self.itemList = ISScrollingListBox:new(margin, y, listWidth, listHeight)
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
			self:drawTexture(item.item.icon, 10, iconY, 1, 30, 30, 1, 1, 1, 1)
		end
		
		-- 绘制物品名称
		self:drawText(item.item.itemName, 60, textY, 1, 1, 1, 1, UIFont.Small)
		
		-- 绘制价格
		self:drawText("$" .. tostring(item.item.cost), self:getWidth() - 60, textY, 1, 1, 0, 1, UIFont.Small)
		
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

function ISSimpleShop:onBuyMouseDown(button, x, y)
	if button.internal == "buy" and self.itemList.selected >= 0 then
		local selectedItem = self.itemList.items[self.itemList.selected]
		if selectedItem and selectedItem.item then
			-- 使用新的API检查是否有足够金钱
			if SimpleShop.HasEnoughMoney(selectedItem.item.cost) then
				-- 使用新的API扣除金钱
				if SimpleShop.RemovePlayerMoney(selectedItem.item.cost) then
					-- 添加物品到玩家背包
					self.char:getInventory():AddItem(selectedItem.item.itemType);
					-- 使用新的API获取更新后的金钱并更新显示
					local newMoney = SimpleShop.GetPlayerMoney();
					if self.moneyLabel and newMoney ~= nil then
						self.moneyLabel.name = getText("UI_SimpleShop_Money") .. ": " .. newMoney;
					end
				end
			end
		end
	end
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
	
	-- 初始显示所有商品
	self:applyFiltersAndUpdateView()
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
	
	-- 应用筛选条件到数据管理器
	self.dataManager:applyFilters(category, searchText)
	
	-- 更新视图
	self:updateItemListView()
end

-- **********************************************************************************
-- 更新物品列表视图
-- **********************************************************************************
function ISSimpleShop:updateItemListView()
	-- 清空当前列表
	self.itemList:clear()
	
	-- 从数据管理器获取筛选后的商品数据
	local filteredItems = self.dataManager:getFilteredItems()
	
	-- 添加商品到列表
	for _, itemData in ipairs(filteredItems) do
		self.itemList:addItem(itemData.displayName, itemData)
	end
	
	-- 重置选择
	self.itemList.selected = 0
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