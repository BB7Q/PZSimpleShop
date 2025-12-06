require "ISUI/ISCollapsableWindow"
require "SimpleShop"

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
	if self.moneyLabel then
		self.moneyLabel.name = getText("UI_SimpleShop_Money") .. ": " .. self.char:getModData().playerMoney;
	end

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

	-- 玩家信息显示
	self.playerLabel = ISLabel:new(margin, y, 20, "", 1, 1, 1, 1, UIFont.Medium);
	self.playerLabel:initialise();
	self.playerLabel:instantiate();
	self.panel:addChild(self.playerLabel);

	y = y + 25;

	-- 金钱显示
	self.moneyLabel = ISLabel:new(margin, y, 16, "", 1, 1, 1, 1, UIFont.Small);
	self.moneyLabel:initialise();
	self.moneyLabel:instantiate();
	self.panel:addChild(self.moneyLabel);

	y = y + 25;

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
	local listHeight = self.height - y - 70; -- 预留按钮和底部边距空间，增加顶部空隙

	-- 创建自定义滚动面板，以便显示图标
	self.scrollPanel = ISPanel:new(margin, y, listWidth, listHeight)
	self.scrollPanel:initialise()
	self.scrollPanel:instantiate()
	self.scrollPanel:setScrollChildren(true)
	self.scrollPanel.backgroundColor = {r=0.05, g=0.05, b=0.05, a=0.8}
	self.scrollPanel.borderColor = {r=0.4, g=0.4, b=0.4, a=1}
	
	-- 添加裁剪功能，防止内容溢出
	function self.scrollPanel:prerender()
		ISPanel.prerender(self)
		self:setStencilRect(0, 0, self.width, self.height)
	end
	function self.scrollPanel:postrender()
		self:clearStencilRect()
		ISPanel.postrender(self)
	end
	
	self.panel:addChild(self.scrollPanel)

	-- 创建用于存储物品元素的数组
	self.itemElements = {}
	
	-- 栅格布局参数 - 动态计算单元格大小以均分容器
	local items = self.settings["ITEMS"]
	local itemCount = 0
	for _ in pairs(items) do itemCount = itemCount + 1 end
	
	-- 计算最优的列数和单元格大小
	local minCellWidth = 100
	local maxCols = math.floor(listWidth / minCellWidth)
	local targetCols = math.min(4, maxCols) -- 最多4列
	if targetCols < 1 then targetCols = 1 end
	
	-- 计算单元格宽度，确保均分容器宽度，考虑左右两边都留出边距
	local cellSpacing = 5
	-- 确保两侧都有边距，总宽度减去所有边距和间隔
	local availableWidth = listWidth - cellSpacing * (targetCols + 1)
	local cellWidth = math.floor(availableWidth / targetCols)
	local cellHeight = 110  -- 固定高度以容纳图标和文字
	
	-- 添加可购买的物品
	local itemIndex = 0
	for itemType,cost in pairs(items) do
		local item = instanceItem(itemType)
		if item then
			itemIndex = itemIndex + 1
			
			-- 计算在栅格中的位置，确保左右两边都有相同的边距
			local row = math.floor((itemIndex - 1) / targetCols)
			local col = (itemIndex - 1) % targetCols
			local x = cellSpacing + col * (cellWidth + cellSpacing)
			local y = cellSpacing + row * (cellHeight + cellSpacing)
			
			-- 创建物品单元格面板
			local itemPanel = ISPanel:new(x, y, cellWidth, cellHeight)
			itemPanel.backgroundColor = {r=0.1, g=0.1, b=0.1, a=0.6}
			itemPanel.borderColor = {r=0.3, g=0.3, b=0.3, a=0.6}
			itemPanel:initialise()
			itemPanel.itemType = itemType
			itemPanel.cost = cost
			itemPanel.itemName = item:getDisplayName()
			
			-- 保存对主窗口的引用，以便在事件处理中使用
			itemPanel.shopWindow = self
			-- 立即设置索引，确保在事件处理中可用
			itemPanel.index = itemIndex
			
			-- 鼠标悬停效果
			function itemPanel:onMouseMove(dx, dy)
				self.backgroundColor = {r=0.2, g=0.2, b=0.2, a=0.8}
			end
			function itemPanel:onMouseMoveOutside(dx, dy)
				self.backgroundColor = {r=0.1, g=0.1, b=0.1, a=0.6}
			end
			
			-- 增加鼠标点击区域和灵敏度
			function itemPanel:onMouseUp(x, y)
				if self.shopWindow and self.shopWindow.itemList then
					self.shopWindow.itemList.selected = self.index
					-- 更新所有项的选中状态
					if self.shopWindow.itemElements then
						for _, elem in ipairs(self.shopWindow.itemElements) do
							if elem.panel ~= self then
								elem.panel.borderColor = {r=0.3, g=0.3, b=0.3, a=0.6}
							else
								elem.panel.borderColor = {r=0.7, g=0.7, b=0.3, a=1}
							end
						end
					end
				end
				return true
			end
			
			-- 同时保留onMouseDown事件作为备用
			function itemPanel:onMouseDown(x, y)
				if self.shopWindow and self.shopWindow.itemList then
					self.shopWindow.itemList.selected = self.index
				end
				return true
			end
			
			self.scrollPanel:addChild(itemPanel)
			
			-- 创建物品图标 - 居中显示
			local iconTexture = item:getTexture()
			local iconSize = 48  -- 图标尺寸
			local itemIcon = ISImage:new((cellWidth - iconSize) / 2, 10, iconSize, iconSize, iconTexture)
			itemIcon:initialise()
			-- 设置图标不处理鼠标事件，让父面板接收点击
			itemIcon.onMouseUp = function() return false end
			itemIcon.onMouseDown = function() return false end
			itemPanel:addChild(itemIcon)
			
			-- 创建物品名称标签 - 居中显示
			local displayName = item:getDisplayName()
			if #displayName > 12 then
				displayName = displayName:sub(1, 9) .. "..."
			end
			
			-- 创建物品名称标签 - 直接添加到itemPanel并留出边框空间
			local nameLabel = ISLabel:new(0, 10 + iconSize + 5, 20, displayName, 1, 1, 1, 1, UIFont.Small)
			nameLabel:initialise()
			nameLabel:setAnchorLeft(false)
			nameLabel:setAnchorRight(false)
			nameLabel:setAnchorTop(false)
			nameLabel:setAnchorBottom(false)
			-- 设置标签不处理鼠标事件，让父面板接收点击
			nameLabel.onMouseUp = function() return false end
			nameLabel.onMouseDown = function() return false end
			itemPanel:addChild(nameLabel)
			
			-- 创建价格标签 - 直接添加到itemPanel并留出边框空间
			local priceLabel = ISLabel:new(0, cellHeight - 25, 20, "$" .. tostring(cost), 1, 1, 0, 1, UIFont.Small)
			priceLabel:initialise()
			priceLabel:setAnchorLeft(false)
			priceLabel:setAnchorRight(false)
			priceLabel:setAnchorTop(false)
			priceLabel:setAnchorBottom(false)
			-- 设置标签不处理鼠标事件，让父面板接收点击
			priceLabel.onMouseUp = function() return false end
			priceLabel.onMouseDown = function() return false end
			itemPanel:addChild(priceLabel)
			
			-- 后续在面板渲染时计算和设置文本居中
			function itemPanel:render()
				ISPanel.render(self)
				-- 计算名称标签的居中位置，留出边框空间
				if nameLabel and nameLabel.name then
					local textWidth = getTextManager():MeasureStringX(UIFont.Small, nameLabel.name)
					nameLabel:setX((self.width - textWidth) / 2)
				end
				
				-- 计算价格标签的居中位置，留出边框空间
				if priceLabel and priceLabel.name then
					local textWidth = getTextManager():MeasureStringX(UIFont.Small, priceLabel.name)
					priceLabel:setX((self.width - textWidth) / 2)
				end
			end
			
			-- 存储元素引用
			table.insert(self.itemElements, {
				panel = itemPanel,
				icon = itemIcon,
				nameLabel = nameLabel,
				priceLabel = priceLabel,
				itemType = itemType,
				cost = cost,
				index = itemIndex
			})
		end
	end
	
	-- 计算总高度
	local totalRows = math.ceil(itemIndex / targetCols)
	local totalHeight = totalRows * (cellHeight + cellSpacing) + cellSpacing
	
	-- 设置滚动高度
	self.scrollPanel:setScrollHeight(totalHeight)
	
	-- 添加滚动条并启用鼠标滚轮支持
	self.scrollPanel:addScrollBars()
	
	-- 添加鼠标滚轮支持
	self.scrollPanel.onMouseWheel = function(self, del)
		if self:getScrollHeight() > self:getHeight() then
			self:setYScroll(self:getYScroll() - (del * 20))
			return true
		end
		return false
	end
	
	-- 创建一个虚拟的itemList用于兼容现有代码
	self.itemList = {
		selected = 0,
		items = self.itemElements
	}
end

function ISSimpleShop:onBuyMouseDown(button, x, y)
	if button.internal == "buy" and self.itemList.selected > 0 then
		local itemElement = self.itemList.items[self.itemList.selected]
		if itemElement and self.char:getModData().playerMoney >= itemElement.cost then
			self.char:getModData().playerMoney = luautils.round(self.char:getModData().playerMoney - itemElement.cost, 0);
			self.char:getInventory():AddItem(itemElement.itemType);
			-- 更新显示的金钱
			if self.moneyLabel then
				self.moneyLabel.name = getText("UI_SimpleShop_Money") .. ": " .. self.char:getModData().playerMoney;
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