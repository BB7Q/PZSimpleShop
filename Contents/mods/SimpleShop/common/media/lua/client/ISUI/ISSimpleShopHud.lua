-- SimpleShop 悬浮余额面板
--   左侧购物图标 + 右侧当前金钱，点击打开/关闭商店，按住可拖拽
--   默认出现在画面右侧中间，位置由 SimpleShop.lua 负责计算与持久化

require "ISUI/ISPanel"
require "SimpleShop"

ISSimpleShopHud = ISPanel:derive("ISSimpleShopHud");

local ICON_TEXTURE_PATH = "media/ui/menu_icon.png";
local PANEL_HEIGHT = 34;
local PANEL_PADDING = 8;
local ICON_SIZE = 20;
local ICON_GAP = 8;
-- 面板最小宽度：余额很少（比如 0）时不缩成一条，保持和常规余额一样的观感
local MIN_WIDTH = 104;
-- 按下后移动超过这个像素数才算拖拽，否则视为点击
local DRAG_THRESHOLD = 4;

local function measureText(text)
	local width = getTextManager():MeasureStringX(UIFont.Small, text);
	return width or 0;
end

-- 面板宽度由余额文字宽度决定，数字再长也不会溢出；余额很少时不小于 MIN_WIDTH
local function computeWidth(textWidth)
	return math.max(MIN_WIDTH, math.ceil(PANEL_PADDING * 2 + ICON_SIZE + ICON_GAP + textWidth));
end

function ISSimpleShopHud:initialise()
	ISPanel.initialise(self);
end

-- **************************************************************************************
-- 按当前余额重算显示文字与面板宽度（每帧调用，只有位数变化时才真的改宽度）
--   贴在右边缘时宽度变大由 clampToScreen 往左顶，右边缘位置保持不变
-- **************************************************************************************
function ISSimpleShopHud:refreshLayout()
	local moneyText = SimpleShop.formatMoney(SimpleShop.GetPlayerMoney(self.playerNum) or 0);
	self.moneyText = moneyText;
	self.moneyTextWidth = measureText(moneyText);

	local width = computeWidth(self.moneyTextWidth);
	if width ~= self.width then
		self:setWidth(width);
		self:clampToScreen();
	end
end

-- **************************************************************************************
-- 背景与边框：悬停/拖拽时高亮，左侧留一条绿色装饰条呼应购物图标
-- **************************************************************************************
function ISSimpleShopHud:prerender()
	self:checkScreenSize();
	self:refreshLayout();

	local hovered = self.dragging or self:isMouseOver();
	local bgAlpha = hovered and 0.85 or 0.65;
	self:drawRect(0, 0, self.width, self.height, bgAlpha, 0.05, 0.05, 0.05);

	-- drawRectBorder 的第 5 个参数是透明度（线宽固定 1px）
	local line = hovered and 0.9 or 0.45;
	self:drawRectBorder(0, 0, self.width, self.height, 1, line, line, line);
	self:drawRect(0, 0, 2, self.height, hovered and 1 or 0.7, 0.22, 0.72, 0.36);
end

-- **************************************************************************************
-- 图标 + 余额（余额右对齐，金额变化时不会左右抖动）
-- **************************************************************************************
function ISSimpleShopHud:render()
	local iconY = math.floor((self.height - ICON_SIZE) / 2);
	if not self.iconTexture then
		self.iconTexture = getTexture(ICON_TEXTURE_PATH);
	end
	if self.iconTexture then
		self:drawTextureScaled(self.iconTexture, PANEL_PADDING, iconY, ICON_SIZE, ICON_SIZE, 1);
	end

	-- refreshLayout 在 prerender 里已经算好，这里只兜底
	if not self.moneyText then
		self:refreshLayout();
	end

	local textX = self.width - PANEL_PADDING - (self.moneyTextWidth or 0);
	local textY = math.floor((self.height - getTextManager():getFontHeight(UIFont.Small)) / 2);
	self:drawText(self.moneyText, textX, textY, 1, 0.85, 0.35, 1, UIFont.Small);
end

-- **************************************************************************************
-- 每帧检查：角色死亡后隐藏面板（复活时由 SimpleShop.initHud 重新创建）
-- **************************************************************************************
function ISSimpleShopHud:update()
	local player = getSpecificPlayer(self.playerNum);
	if not player or not player:isAlive() then
		self:setVisible(false);
	end
end

-- **************************************************************************************
-- 鼠标事件：左键按下开始拖拽，松手时没移动过就算点击（打开商店）
-- **************************************************************************************
function ISSimpleShopHud:onMouseDown(x, y)
	if not self:getIsVisible() then return false end
	self.dragging = true;
	self.dragDistance = 0;
	self:bringToTop();
	return true;
end

function ISSimpleShopHud:onMouseMove(dx, dy)
	if not self.dragging then return end
	self:applyDrag(dx, dy);
end

-- 拖到面板外也要继续跟随鼠标（与 ISPanel 的 moveWithMouse 同一套机制）
function ISSimpleShopHud:onMouseMoveOutside(dx, dy)
	if not self.dragging then return end
	self:applyDrag(dx, dy);
end

function ISSimpleShopHud:onMouseUp(x, y)
	self:finishDrag(true);
end

function ISSimpleShopHud:onMouseUpOutside(x, y)
	self:finishDrag(false);
end

function ISSimpleShopHud:applyDrag(dx, dy)
	self.dragDistance = self.dragDistance + math.abs(dx) + math.abs(dy);
	self:setX(self.x + dx);
	self:setY(self.y + dy);
	self:clampToScreen();
end

function ISSimpleShopHud:finishDrag(inside)
	if not self.dragging then return end
	self.dragging = false;

	local clicked = inside and self.dragDistance < DRAG_THRESHOLD;
	-- 拖拽结束后保存位置（点击也会存一次，值不变，无副作用）
	self:savePosition();

	if clicked then
		SimpleShop.toggleShopWindow(self.playerNum);
	end
end

-- **************************************************************************************
-- 位置相关：限制在画面内 / 分辨率变化时自动收回 / 拖拽后写入玩家 ModData
--   （分屏时每个玩家的画面有自己的左上角偏移，这里一并算上）
-- **************************************************************************************
local function getPlayerScreenRect(playerNum)
	local left = 0;
	local top = 0;
	if getPlayerScreenLeft then left = getPlayerScreenLeft(playerNum) or 0 end
	if getPlayerScreenTop then top = getPlayerScreenTop(playerNum) or 0 end

	local screenWidth = getPlayerScreenWidth(playerNum);
	local screenHeight = getPlayerScreenHeight(playerNum);
	if not screenWidth or not screenHeight or screenWidth <= 0 or screenHeight <= 0 then
		return nil;
	end
	return left, top, screenWidth, screenHeight;
end

function ISSimpleShopHud:clampToScreen()
	local left, top, screenWidth, screenHeight = getPlayerScreenRect(self.playerNum);
	if not left then return end

	local maxX = left + math.max(0, screenWidth - self.width);
	local maxY = top + math.max(0, screenHeight - self.height);
	if self.x < left then
		self:setX(left);
	elseif self.x > maxX then
		self:setX(maxX);
	end
	if self.y < top then
		self:setY(top);
	elseif self.y > maxY then
		self:setY(maxY);
	end
end

function ISSimpleShopHud:checkScreenSize()
	local left, top, screenWidth, screenHeight = getPlayerScreenRect(self.playerNum);
	if not left then return end
	if self.screenLeft == left and self.screenTop == top
		and self.screenWidth == screenWidth and self.screenHeight == screenHeight then
		return;
	end

	self.screenLeft = left;
	self.screenTop = top;
	self.screenWidth = screenWidth;
	self.screenHeight = screenHeight;
	self:clampToScreen();
end

function ISSimpleShopHud:savePosition()
	local player = getSpecificPlayer(self.playerNum);
	if not player then return end

	local modData = player:getModData();
	modData.SimpleShopHudX = math.floor(self.x);
	modData.SimpleShopHudY = math.floor(self.y);
end

function ISSimpleShopHud:new(playerNum, x, y)
	local o = ISPanel:new(x or 0, y or 0, 0, PANEL_HEIGHT);
	setmetatable(o, self);
	self.__index = self;

	o.playerNum = playerNum or 0;
	-- 背景与边框自己画（prerender），不交给 ISPanel；拖拽也自己处理
	o.background = false;
	o.moveWithMouse = false;
	o.dragging = false;
	o.dragDistance = 0;
	o.screenWidth = 0;
	o.screenHeight = 0;
	o.iconTexture = getTexture(ICON_TEXTURE_PATH);

	-- 首帧宽度按当前余额算好，避免创建瞬间闪一下窄面板
	o.moneyText = SimpleShop.formatMoney(SimpleShop.GetPlayerMoney(o.playerNum) or 0);
	o.moneyTextWidth = measureText(o.moneyText);
	o.width = computeWidth(o.moneyTextWidth);
	return o;
end
