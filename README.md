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
- 🏷️ **游戏内定价** - 管理员可在游戏内从全部物品脚本（含其他模组物品）中选择物品并设定售价，价格随存档持久化

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

### 商品定价（管理员）
1. 以管理员身份进入游戏（单人存档默认即为管理员）
2. 打开商店窗口，点击底部 **定价** 按钮；或在世界/物品栏右键菜单中选择 **管理商品**
3. 在弹出的「商品定价」窗口中：
   - 顶部工具栏：搜索框（按物品名称或物品 ID 如 `Base.Axe` 过滤）、**已上架商品 / 全部物品** 视图切换
   - 默认视图为 **已上架商品**：每行带绿色 **已上架** 徽标与当前价格，选中即可直接改价或下架
   - 第二行是两级筛选：先选 **来源模组**（原版 / 各模组），再从 **物品类型** 里选具体类别，第二个下拉只列出所选模组的类型
   - 切到 **全部物品** 可浏览全部物品脚本（**包含其他模组添加的物品**），同样支持两级筛选与分页
   - 列表只收录真实可用的物品脚本：`Hidden` / `Obsolete` 物品，以及模组内部使用的 `xxx_Hidden` 变体（同一件衣服的内部样式副本，显示名与本体完全相同）不会出现在列表里
   - 列表支持分页（每页条数按窗口高度自动计算），底部显示 `页码 X / Y` 与当前过滤结果总数
   - 选中物品 → 输入价格（0 ~ 999999 的整数）→ 点击 **上架/改价**；**下架** 移出商店；**恢复默认** 重置为 `SimpleShopItems.lua` 的初始清单
4. 定价结果立即生效，已打开的商店窗口会自动刷新

**持久化说明**：价格表保存在世界级全局 ModData（键名 `SimpleShopPrices`）中，随存档保存，重启游戏/换角色都不会丢失；购买金额按该价格表结算。

### 获得金钱
- 击杀僵尸：每杀死一个僵尸获得金钱奖励
- 初始金钱：新角色开始时有100初始资金

## 配置选项

模组支持以下配置（位于 `common/media/lua/shared/`）：

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

> 说明：游戏内定价过的价格会写入存档中的价格表（全局 ModData `SimpleShopPrices`），优先级高于 `SimpleShopItems.lua`。修改 `SimpleShopItems.lua` 只影响"首次加载"和"恢复默认"时的初始清单。

## 文件结构

```
SimpleShop/
├── Contents/
│   └── mods/
│       └── SimpleShop/
│           ├── 42/                        -- B42 版本信息
│           │   ├── mod.info
│           │   └── shop.png
│           └── common/
│               ├── mod.info              -- 模组信息文件
│               ├── shop.png              -- 模组海报
│               └── media/
│                   ├── ui/menu_icon.png  -- 菜单图标
│                   └── lua/
│                       ├── client/
│                       │   ├── SimpleShop.lua            -- 主逻辑 / 右键菜单入口
│                       │   ├── SimpleShopClientCommands.lua -- 客户端事件 -> 服务端请求
│                       │   └── ISUI/
│                       │       ├── ISSimpleShop.lua      -- 商店界面
│                       │       └── ISSimpleShopAdmin.lua -- 商品定价界面
│                       ├── server/
│                       │   └── SimpleShopServer.lua      -- 服务端权威逻辑（购买/定价）
│                       └── shared/
│                           ├── SimpleShopBasic.lua       -- 基础设置
│                           ├── SimpleShopItems.lua       -- 默认物品清单
│                           ├── SimpleShopDataManager.lua -- 商品数据/筛选
│                           ├── SimpleShopItemStore.lua   -- 价格表持久化（全局 ModData）
│                           └── Translate/
│                               ├── CN/UI.json            -- 中文界面翻译
│                               ├── CN/Mod.json           -- 中文名称/描述
│                               ├── EN/UI.json            -- 英文界面翻译（其他语言回退）
│                               └── EN/Mod.json           -- 英文名称/描述
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
   - 右键菜单 / 管理员入口

2. **用户界面** (`ISSimpleShop.lua` / `ISSimpleShopAdmin.lua`)
   - 滚动列表显示
   - 物品分类和搜索功能
   - 物品选择交互
   - 购买逻辑
   - 商品定价（已上架视图带徽标/价格、全量物品搜索 + 模组/类型两级筛选 + 分页、改价/下架/恢复默认）

3. **价格持久化** (`SimpleShopItemStore.lua`)
   - 世界级全局 ModData（`SimpleShopPrices`）存储价格表
   - 主控端写入价格表，其余端只发请求
   - 价格变化监听器（界面自动刷新）

4. **结算与同步** (`SimpleShopServer.lua` / `SimpleShopClientCommands.lua`)
   - 购买金额按价格表重算，拒绝客户端伪造金额
   - 定价操作的权限校验（仅管理员可改价）

5. **配置系统** (`SimpleShopBasic.lua` / `SimpleShopItems.lua`)
   - 基础设置
   - 默认物品清单（仅在首次创建价格表或"恢复默认"时使用）

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
