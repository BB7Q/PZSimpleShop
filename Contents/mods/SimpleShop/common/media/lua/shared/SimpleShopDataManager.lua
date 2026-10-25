-- SimpleShop数据管理器
-- 负责管理所有商品数据、筛选逻辑，与UI视图分离
SimpleShopDataManager = {}

-- 初始化数据管理器
function SimpleShopDataManager:new(settings)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    
    o.settings = settings
    o.allItems = {}  -- 所有商品数据
    o.filteredItems = {}  -- 筛选后的商品数据
    o.categories = {}  -- 分类数据
    o.currentCategory = nil  -- 当前选择的分类
    o.currentSearch = ""  -- 当前搜索文本
    
    o:initializeItems()
    return o
end

-- 获取当前生效的价格表（优先使用持久化的商品清单）
function SimpleShopDataManager:getPriceTable()
    if SimpleShopItemStore then
        local prices = SimpleShopItemStore.getPrices()
        if SimpleShopItemStore.isLoaded and type(prices) == "table" then
            return prices
        end
    end
    return (self.settings and self.settings["ITEMS"]) or {}
end

-- 初始化商品数据
function SimpleShopDataManager:initializeItems()
    self.allItems = {}
    self.categories = {}

    -- 获取商品列表并分类
    local items = self:getPriceTable()
    for itemType, cost in pairs(items) do
        local item = instanceItem(itemType)
        if item then
            -- 获取物品分类
            local category = item:getCategory() or "Other"
            
            -- 创建商品数据对象
            local itemData = {
                itemType = itemType,
                cost = cost,
                itemName = item:getDisplayName(),
                icon = item:getTexture(),
                category = category,
                displayName = item:getDisplayName()
            }
            
            -- 添加到所有商品列表
            table.insert(self.allItems, itemData)
        end
    end

    -- 按名称排序，保证列表顺序稳定
    table.sort(self.allItems, function(a, b)
        local an, bn = string.lower(a.itemName or ""), string.lower(b.itemName or "")
        if an == bn then return a.itemType < b.itemType end
        return an < bn
    end)

    -- 添加到分类映射
    for _, itemData in ipairs(self.allItems) do
        local category = itemData.category
        if not self.categories[category] then
            self.categories[category] = {}
        end
        table.insert(self.categories[category], itemData)
    end

    -- 默认显示所有商品
    self:applyFilters()
end

-- 获取所有分类名称
function SimpleShopDataManager:getCategoryNames()
    local categoryNames = {"all"}  -- 第一个是"所有分类"
    
    -- 获取并排序分类名称
    local sortedCategories = {}
    for categoryName in pairs(self.categories) do
        table.insert(sortedCategories, categoryName)
    end
    table.sort(sortedCategories)
    
    -- 添加分类名称
    for _, categoryName in ipairs(sortedCategories) do
        table.insert(categoryNames, categoryName)
    end
    
    return categoryNames
end

-- 根据分类名称获取显示名称
function SimpleShopDataManager:getCategoryDisplayName(categoryName)
    if categoryName == "all" then
        return getText("UI_SimpleShop_AllCategories")
    else
        local displayName = getText("IGUI_ItemCat_" .. categoryName)
        if displayName == "IGUI_ItemCat_" .. categoryName then
            return categoryName
        end
        return displayName
    end
end

-- 应用筛选条件
function SimpleShopDataManager:applyFilters(category, searchText)
    self.currentCategory = category or self.currentCategory
    self.currentSearch = searchText or self.currentSearch
    
    -- 根据分类筛选
    local itemsToShow
    if not self.currentCategory or self.currentCategory == "all" then
        itemsToShow = self.allItems
    else
        itemsToShow = self.categories[self.currentCategory] or {}
    end
    
    -- 根据搜索文本筛选（同时匹配显示名和物品ID）
    if self.currentSearch and self.currentSearch ~= "" then
        local filtered = {}
        local searchLower = string.lower(self.currentSearch)

        for _, item in ipairs(itemsToShow) do
            local itemName = string.lower(item.itemName or "")
            local itemType = string.lower(item.itemType or "")
            if string.find(itemName, searchLower, 1, true) or string.find(itemType, searchLower, 1, true) then
                table.insert(filtered, item)
            end
        end
        itemsToShow = filtered
    end
    
    self.filteredItems = itemsToShow
end

-- 获取筛选后的商品列表
function SimpleShopDataManager:getFilteredItems()
    return self.filteredItems
end

-- 获取所有商品数据（用于调试或其他用途）
function SimpleShopDataManager:getAllItems()
    return self.allItems
end

-- 根据索引获取商品数据
function SimpleShopDataManager:getItemByIndex(index)
    if index >= 1 and index <= #self.filteredItems then
        return self.filteredItems[index]
    end
    return nil
end

-- 获取商品总数
function SimpleShopDataManager:getItemCount()
    return #self.filteredItems
end

-- 获取当前筛选条件
function SimpleShopDataManager:getCurrentFilters()
    return {
        category = self.currentCategory,
        searchText = self.currentSearch
    }
end