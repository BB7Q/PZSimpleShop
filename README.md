# SimpleShop - Project Zomboid Mod

一个简单的商店模组，让玩家可以在游戏中购买物品。

## 项目简介

SimpleShop 是一个简单的购物mod，为玩家提供了商店界面用于购买游戏中的各种物品。本mod只能用来购买物品，不包含其他功能。本mod参考了CoxisShop，并进行了功能简化和重新设计，使其更加轻量化和易于使用。设计简洁，方便扩展和集成到其他mod中。

## 功能特性

- 🛒 **商店界面** - 滚动列表显示物品，支持分类筛选和搜索功能
- 💰 **货币系统** - 通过击杀僵尸获得金钱
- 🔄 **死亡继承** - 玩家死亡后保留全部金钱
- 🖱️ **右键菜单** - 在世界界面或物品栏中右键点击，选择"打开商店"
- 🌍 **多语言支持** - 内置中英文界面
- ⚙️ **可配置** - 支持自定义初始金钱和物品价格

## 安装方法

### Steam 创意工坊安装
1. 订阅 [SimpleShop 模组](https://steamcommunity.com/sharedfiles/filedetails/?id=3619356125)
2. 在游戏启动器中选择模组
3. 启动游戏

## 使用方法

### 打开商店
- **右键菜单**: 在世界界面或物品栏中右键点击，选择"打开商店"

### 购买物品
1. 打开商店界面
2. 点击要购买的物品
3. 点击"购买"按钮
4. 物品将直接添加到你的物品栏

### 物品筛选
- **搜索功能**: 使用搜索框快速查找所需物品
- **分类筛选**: 使用下拉菜单按类别浏览物品

### 获得金钱
- 击杀僵尸：每杀死一个僵尸获得金钱奖励
- 初始金钱：新角色开始时有100初始资金

## 配置选项

模组支持以下配置（位于 `SimpleShopSettings.lua`）：

```lua
SimpleShopBasic = {
    ["initialMoney"] = 100, -- 初始金钱
    ["zombieKillAmount"] = 10, -- 每击杀一个僵尸获得的金钱
}

SimpleShopItems = {
    -- 基础生存物资
    ["Base.Bread"] = 75,               -- 面包
    ["Base.Apple"] = 25,               -- 苹果
    ["Base.Milk"] = 60,                -- 牛奶
    -- 医疗用品
    ["Base.Bandage"] = 150,            -- 绷带
    ["Base.PillsBeta"] = 200,          -- 药片
    ["Base.Disinfectant"] = 180,       -- 消毒剂
    -- 工具
    ["Base.Hammer"] = 300,             -- 锤子
    ["Base.Axe"] = 500,                -- 斧头
    ["Base.Saw"] = 400,                -- 锯子
    ["Base.Screwdriver"] = 200,        -- 螺丝刀
    -- 武器
    ["Base.BaseballBat"] = 400,        -- 棒球棒
    -- 建筑材料
    ["Base.Nails"] = 50,               -- 钉子
    -- 弹药
    ["Base.Bullets9mmBox"] = 100,      -- 9mm子弹盒
    ["Base.Bullets38Box"] = 175,       -- .38子弹盒
    ["Base.Bullets44Box"] = 190,       -- .44子弹盒
    ["Base.223Box"] = 300,             -- .223子弹盒
    ["Base.308Box"] = 300,             -- .308子弹盒
    ["Base.ShotgunShellsBox"] = 450,   -- 霰弹枪子弹盒
    ["Base.Bullets45Box"] = 500,       -- .45子弹盒
    ["Base.556Box"] = 600,             -- 5.56子弹盒
}
```

## 文件结构

```
SimpleShop/
├── Contents/
│   └── mods/
│       └── SimpleShop/
│           ├── common/
│           │   ├── mod.info              -- 模组信息文件
│           │   ├── poster.png            -- 模组海报
│           │   └── media/
│           │       └── lua/
│           │           ├── client/
│           │           │   ├── SimpleShop.lua          -- 主逻辑文件
│           │           │   └── ISUI/
│           │           │       └── ISSimpleShop.lua    -- UI界面
│           │           └── shared/
│           │               ├── SimpleShopBasic.lua     -- 基础设置
│           │               ├── SimpleShopItems.lua     -- 物品配置
│           │               └── Translate/
│           │                   ├── CN/UI_CN.txt        -- 中文翻译
│           │                   └── EN/UI_EN.txt        -- 英文翻译
├── icon.svg                              -- 模组图标
├── preview.png                           -- 预览图片
└── README.md                            -- 项目说明
```

## 开发信息

### 技术栈
- **编程语言**: Lua
- **游戏引擎**: Project Zomboid
- **UI框架**: ISUI (游戏内置UI系统)

### 主要功能模块

1. **商店系统** (`SimpleShop.lua`)
   - 货币管理
   - 事件处理
   - 玩家数据持久化

2. **用户界面** (`ISSimpleShop.lua`)
   - 滚动列表显示
   - 物品分类和搜索功能
   - 物品选择交互
   - 购买逻辑

3. **配置系统** (`SimpleShopBasic.lua`和`SimpleShopItems.lua`)
   - 基础设置
   - 物品价格配置

## API接口

SimpleShop提供了以下API，供其他mod调用以修改玩家金钱：

### 获取玩家当前金额
```lua
SimpleShop.GetPlayerMoney(playerIndex)
```
获取指定玩家的当前金额，不指定playerIndex则获取当前玩家金额。

### 增加玩家金额
```lua
SimpleShop.AddPlayerMoney(amount, playerIndex)
```
为指定玩家增加金额，amount必须为正数。

### 减少玩家金额
```lua
SimpleShop.RemovePlayerMoney(amount, playerIndex)
```
从指定玩家扣除金额，amount必须为正数且玩家余额必须足够。

### 检查玩家是否有足够金额
```lua
SimpleShop.HasEnoughMoney(amount, playerIndex)
```
检查指定玩家是否有足够金额。

这些方法可用于实现任务奖励、自定义商店等需要修改玩家金钱的功能。
