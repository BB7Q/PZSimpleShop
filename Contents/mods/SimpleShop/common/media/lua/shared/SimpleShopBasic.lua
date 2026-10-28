-- 基础设置
-- 初始金钱与击杀奖励属于世界级规则，现在由沙箱选项「简易商店」页配置
-- （定义见 common/media/sandbox-options.txt，运行时读 SandboxVars.SimpleShop.*）：
--   SimpleShop.InitialMoney  新角色初始金钱，默认 0
--   SimpleShop.KillReward    每击杀一只僵尸的奖励，默认 10
-- 本文件中的同名字段只作为兜底（沙箱选项缺失时使用，例如未加载选项定义的老版本/异常情况），
-- 正常调参请改沙箱选项，不要改这里。
SimpleShopBasic = {
    ["initialMoney"] = 0, -- 兜底：沙箱选项缺失时的初始金钱
    ["zombieKillAmount"] = 10, -- 兜底：沙箱选项缺失时的击杀奖励
}

-- **************************************************************************************
-- 读取沙箱选项（世界级；单机=当前存档，联机=服务端权威并同步给客户端）
-- @param name 选项名（如 "InitialMoney"）
-- @return 选项值，缺失时返回 nil
-- **************************************************************************************
function SimpleShopBasic.getSandboxOption(name)
    if type(SandboxVars) ~= "table" then return nil end
    local page = SandboxVars["SimpleShop"]
    if type(page) ~= "table" then return nil end
    return page[name]
end

-- **************************************************************************************
-- 新角色初始金钱：沙箱选项 > 本文件旧字段 > 0
-- **************************************************************************************
function SimpleShopBasic.getInitialMoney()
    local value = tonumber(SimpleShopBasic.getSandboxOption("InitialMoney"))
    if value == nil then value = tonumber(SimpleShopBasic.initialMoney) end
    if value == nil then return 0 end
    return math.max(0, math.floor(value))
end

-- **************************************************************************************
-- 每击杀一只僵尸的奖励：沙箱选项 > 本文件旧字段 > 10
-- **************************************************************************************
function SimpleShopBasic.getKillReward()
    local value = tonumber(SimpleShopBasic.getSandboxOption("KillReward"))
    if value == nil then value = tonumber(SimpleShopBasic.zombieKillAmount) end
    if value == nil then return 10 end
    return math.max(0, math.floor(value))
end
