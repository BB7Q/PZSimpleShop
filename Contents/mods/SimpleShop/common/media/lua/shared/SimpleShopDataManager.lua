-- SimpleShop数据管理器
-- 负责管理所有商品数据、筛选与排序逻辑，与UI视图分离
SimpleShopDataManager = {}

-- 排序模式：界面下拉框按此顺序展示
--   custom = 管理员在定价窗口里调整的陈列顺序（默认，未调整过的商品按名称兜底）
--   name_asc 同时是缓存表的自然顺序，无需重排
SimpleShopDataManager.SORT_MODES = { "custom", "name_asc", "name_desc", "price_asc", "price_desc" }
SimpleShopDataManager.DEFAULT_SORT = "custom"

-- 排序模式的界面文案键（Translate/XX/UI.json）
SimpleShopDataManager.SORT_LABEL_KEYS = {
    custom = "UI_SimpleShop_SortCustom",
    name_asc = "UI_SimpleShop_SortNameAsc",
    name_desc = "UI_SimpleShop_SortNameDesc",
    price_asc = "UI_SimpleShop_SortPriceAsc",
    price_desc = "UI_SimpleShop_SortPriceDesc",
}

-- 排序模式是否合法（界面传入的下标可能越界）
function SimpleShopDataManager.isValidSortMode(mode)
    for _, value in ipairs(SimpleShopDataManager.SORT_MODES) do
        if value == mode then return true end
    end
    return false
end

-- 排序模式显示名：缺翻译时回退为模式名，避免下拉框出现空选项
function SimpleShopDataManager.getSortLabel(mode)
    local key = SimpleShopDataManager.SORT_LABEL_KEYS[mode]
    if not key then return tostring(mode) end
    local text = getText(key)
    if not text or text == "" or text == key then return tostring(mode) end
    return text
end

-- 空表判断：PZ 的 Lua 环境没有 next()，不能用 next(t) == nil
local function isEmptyTable(t)
    if type(t) ~= "table" then return true end
    for _ in pairs(t) do
        return false
    end
    return true
end

-- 管理员设定的陈列顺序下标表（未指定时返回 nil）
function SimpleShopDataManager.getOrderRanks()
    if SimpleShopItemStore and SimpleShopItemStore.getOrderIndexMap then
        return SimpleShopItemStore.getOrderIndexMap()
    end
    return nil
end

-- 比较函数：名称升序时与缓存表顺序完全一致；同键值再按 itemType 稳定排序
-- ranks 仅在 custom 模式下使用：有顺序的按位置排前，未指定的按名称追加
local function compareItems(mode, a, b, ranks)
    local aType, bType = a.itemType or "", b.itemType or ""

    if mode == "custom" and ranks then
        local aRank, bRank = ranks[aType], ranks[bType]
        if aRank ~= bRank then
            if aRank == nil then return false end
            if bRank == nil then return true end
            return aRank < bRank
        end
    end

    if mode == "price_asc" or mode == "price_desc" then
        local aCost, bCost = a.cost or 0, b.cost or 0
        if aCost ~= bCost then
            if mode == "price_asc" then return aCost < bCost end
            return aCost > bCost
        end
    end

    local aName, bName = a.sortName or "", b.sortName or ""
    if aName ~= bName then
        if mode == "name_desc" then return aName > bName end
        return aName < bName
    end
    return aType < bType
end

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
    o.sortMode = SimpleShopDataManager.DEFAULT_SORT  -- 当前排序模式
    
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
            
            -- 创建商品数据对象（sortName 是小写检索/排序键，避免每次排序反复 string.lower）
            local itemName = item:getDisplayName()
            local itemData = {
                itemType = itemType,
                cost = cost,
                itemName = itemName,
                icon = item:getTexture(),
                category = category,
                displayName = itemName,
                sortName = string.lower(itemName or itemType)
            }
            
            -- 添加到所有商品列表
            table.insert(self.allItems, itemData)
        end
    end

    -- 按名称排序，保证列表顺序稳定（同时作为 name_asc 的基准顺序）
    table.sort(self.allItems, function(a, b)
        return compareItems("name_asc", a, b)
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

-- 应用筛选与排序条件
function SimpleShopDataManager:applyFilters(category, searchText, sortMode)
    self.currentCategory = category or self.currentCategory
    self.currentSearch = searchText or self.currentSearch
    if SimpleShopDataManager.isValidSortMode(sortMode) then
        self.sortMode = sortMode
    end
    
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
    
    -- 排序：name_asc 直接复用已排好的缓存表；其他模式复制一份再排序，避免打乱 allItems/categories
    local mode = self.sortMode or SimpleShopDataManager.DEFAULT_SORT
    local ranks = nil
    if mode == "custom" then
        ranks = SimpleShopDataManager.getOrderRanks()
        -- 从未调整过顺序（或顺序全指向已下架商品）时等价于按名称排列，无需重排
        if not ranks or isEmptyTable(ranks) then
            mode = "name_asc"
        end
    end
    if mode ~= "name_asc" and #itemsToShow > 1 then
        local sorted = {}
        for index = 1, #itemsToShow do
            sorted[index] = itemsToShow[index]
        end
        table.sort(sorted, function(a, b) return compareItems(mode, a, b, ranks) end)
        itemsToShow = sorted
    end
    
    self.filteredItems = itemsToShow
end

-- 切换排序模式（不重新扫描物品，只重排当前结果）
function SimpleShopDataManager:setSortMode(mode)
    if not SimpleShopDataManager.isValidSortMode(mode) then return false end
    self.sortMode = mode
    self:applyFilters()
    return true
end

function SimpleShopDataManager:getSortMode()
    return self.sortMode or SimpleShopDataManager.DEFAULT_SORT
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
        searchText = self.currentSearch,
        sortMode = self.sortMode
    }
end