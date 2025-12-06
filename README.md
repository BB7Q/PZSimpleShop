# SimpleShop - Project Zomboid Mod

一个简单的商店模组，让玩家可以在游戏中购买物品。

## 项目简介

SimpleShop 是一个为 Project Zomboid 游戏设计的轻量级模组，为玩家提供了一个简单直观的商店界面，用于购买游戏中的各种物品。

## 功能特性

- 🛒 **简洁的商店界面** - 直观的网格布局，显示物品图标和价格
- 💰 **货币系统** - 通过击杀僵尸获得金钱
- 🔄 **死亡继承** - 玩家死亡后保留部分金钱
- ⌨️ **多种打开方式** - 支持快捷键和右键菜单
- 🌍 **多语言支持** - 内置中英文界面
- ⚙️ **可配置** - 支持自定义初始金钱和物品价格

## 安装方法

### Steam 创意工坊安装
1. 订阅 [SimpleShop 模组](steam创意工坊链接)
2. 在游戏启动器中选择模组
3. 启动游戏

### 手动安装
1. 下载最新版本
2. 解压到 `ProjectZomboid/mods/` 目录
3. 在游戏启动器中启用模组

## 使用方法

### 打开商店
- **快捷键**: 默认按键 `O`（可在设置中修改）
- **右键菜单**: 在世界界面或物品栏中右键点击，选择"打开商店"

### 购买物品
1. 打开商店界面
2. 点击要购买的物品
3. 点击"购买"按钮
4. 物品将直接添加到你的物品栏

### 获得金钱
- 击杀僵尸：每杀死一个僵尸获得金钱奖励
- 初始金钱：新角色开始时有一定初始资金

## 配置选项

模组支持以下配置（位于 `SimpleShopSettings.lua`）：

```lua
SimpleShopBasicSettings = {
    initialMoney = 100,      -- 初始金钱
    zombieKillAmount = 5     -- 每杀死一个僵尸获得的金钱
}

SimpleShopItems = {
    ["Base.Axe"] = 50,      -- 斧头价格
    ["Base.Hammer"] = 30,   -- 锤子价格
    -- 更多物品配置...
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
│           │           │   ├── simpleshop_keybinds.lua -- 快捷键绑定
│           │           │   └── ISUI/
│           │           │       └── ISSimpleShop.lua    -- UI界面
│           │           └── shared/
│           │               ├── SimpleShopSettings.lua  -- 配置设置
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
   - 网格布局显示
   - 物品选择交互
   - 购买逻辑

3. **配置系统** (`SimpleShopSettings.lua`)
   - 基础设置
   - 物品价格配置
