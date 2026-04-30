# mochi

桌面像素宠物。从一颗蛋开始,**吃你扔进 macOS 垃圾桶的东西**,根据食性进化出不同形态。

零侵入:不拦截删除、不调用 `rm`、不读文件内容。只是 FSEvents 旁观 `~/.Trash/`。

## 为什么存在

数字断舍离 + 桌面陪伴 + 随机进化。三个钩子叠在一起的小玩具,纯私人乐趣,顺便变成开源传播品。

## 怎么用

```bash
./build.sh
open ~/Applications/Mochi.app
# 想看日志(meal events 走 NSLog):
log stream --predicate 'process == "Mochi"' --style compact
```

**第一次跑必须授权**:macOS 从 Mojave 起把 `~/.Trash` 列入 TCC 保护。Mochi 第一次访问时系统会弹"Mochi 想要访问 Trash"。如果错过弹窗 / 没弹:

```
System Settings → Privacy & Security → Files and Folders → Mochi
→ 勾选 "Removable Volumes"(包含 Trash 项)
```

或者一步到位:把 Mochi 加进 **Full Disk Access**(更省事但权限更大)。日志里出现 `cannot read ~/.Trash — grant Files & Folders access` 就是没授权。

`LSUIElement = true` — 没有 Dock 图标,只有一只飘在桌面上的小蛋。**右键** Mochi 弹菜单(reset position / quit)。**左键拖动**换位置(自动持久化到 `UserDefaults`)。**单击不拖**会让它说一句话。

## 文件布局

```
mochi/
├── Mochi.swift          # @main + AppDelegate + PetPanel + PetView + DragHost + 占位 EggSprite
├── TrashWatcher.swift   # FSEvents 监听 ~/.Trash + 扩展名 → category 分类
├── Info.plist           # LSUIElement, com.jieye.mochi
├── build.sh             # 单二进制 swiftc + ad-hoc 签名 + 装到 ~/Applications
├── assets/              # PixelLab 生成的 sprite 落这里(目前空)
└── CLAUDE.md
```

## 技术决策

### 悬浮窗 — `NSPanel` 而不是 `NSWindow`

桌面宠物的标准答案。组合配方在 `PetPanel`:

```
styleMask:           [.borderless, .nonactivatingPanel]
isOpaque:            false
backgroundColor:     .clear
hasShadow:           false
level:               .floating
collectionBehavior:  [.canJoinAllSpaces, .stationary,
                      .fullScreenAuxiliary, .ignoresCycle]
canBecomeKey:        false        ← 永远不偷焦点(关键)
hidesOnDeactivate:   false
```

- `nonactivatingPanel` + `canBecomeKey=false` → 点宠物不会把别的 app 失焦
- `.canJoinAllSpaces` → 切 Space 它跟着走
- `.fullScreenAuxiliary` → 全屏看视频它也在
- `NSApp.setActivationPolicy(.accessory)` → 没 Dock 图标、没菜单栏菜单

### 拖动 — `DragHost` 自己接 mouseDown/Dragged/Up

不用 `isMovableByWindowBackground`,因为我们要区分"拖动"和"单击"(单击触发 poke)。`mouseDragged` 里手动 `setFrameOrigin`,`mouseUp` 时距离 < 2pt 视为点击,否则持久化坐标。

### 占位精灵 — Canvas 手画 16×16 像素蛋

PixelLab 生成正式 sprite 之前先有视觉,不阻塞窗口/事件链路联调。`EggSprite` 整个删掉换成 `Image(...)` 序列就是 v0.2。

### Trash 监听 — FSEvents + diff,不是 inotify-style 单文件回调

FSEvents 通知"这个目录变了",不告诉你具体哪个文件。所以 `TrashWatcher` 维护一个 `seen: Set<String>`,事件触发时用 `contentsOfDirectory` 重新拿一遍,做差集找新增。这种 poll-on-event 的混合策略对 `~/.Trash` 这种小目录开销可忽略。

启动时把当前 Trash 内容当作 baseline 全部 `seed` 进 `seen`,**不会把已经在垃圾桶里的旧文件当成新进食**。

### 隐私边界

- 只读:文件名、扩展名、文件大小。**绝不**读内容、不算 hash、不记录完整路径以外的东西
- 本地 only,无网络代码
- 后续要加 SQLite 持久化喂食日志时,只存 `(timestamp, ext, size, category)`,不存文件名

## 进化设计(待实现)

蛋阶段消化前 ~100 次进食,根据食性主导分支孵化。`TrashMeal.Category` 已经在 `TrashWatcher.swift` 里:`code / image / video / audio / doc / archive / app / junk / other`。

| 主食 | 进化方向 |
|---|---|
| code | Coder 系(眼镜、bug 形态) |
| image | Artist 系(颜料污迹) |
| doc | Scholar 系(小帽子) |
| junk | Junk 系(臃肿、慵懒、最丑) |
| video/audio | Media 系(屏幕脸) |

行为风味突变(trait,叠在主分支上):
- 深夜删多 → 夜行性(大眼睛)
- 删后立刻 restore(`removed` 集合非空时下一秒同名 `added`)→ "优柔寡断" 半透明幽灵
- N 天没吃 → 饿瘦
- 删 `.git/` 整个目录 → "开发者觉醒" 剧情线

## PixelLab 资产生成(沿用 encore 项目方案)

参考 `/Users/jieye/Desktop/focus/tools/encore/scripts/pixellab/PIXELLAB.md`。统一参数:

```
size: 48 (蛋)/ 96 (孵化后,Pro 接口要正方形)
proportions: chibi
outline: single color black outline
shading: medium shading
detail: medium detail
view: low top-down
```

资产规划(蛋阶段先做):
- `egg_idle_*.png`(8 帧,微微呼吸)
- `egg_eat_*.png`(6 帧,吞咽气泡)
- `egg_crack_*.png`(裂蛋孵化序列)

之后每个分支:
- `<form>_idle / walk / eat / sleep / poke`(各 6-8 帧)

落到 `assets/<form>/<animation>/frame_NN.png`,Mochi.swift 加 `SpriteSheet` 类替换 `EggSprite`。

## 已知问题 / TODO

- [ ] 透明区域不能点穿(矩形 hit test);v0.2 做 alpha-aware hit test
- [ ] 外接盘 `/Volumes/*/.Trashes/$(uid)` 没监听
- [ ] 没有持久化食谱日志(SQLite)
- [ ] 没有进化状态机
- [ ] 还是占位 EggSprite

## 风险笔记

**绝对不能**变成"拖到 Mochi 窗口里来删除"那种交互 — 用户会指望它真删,代码就要碰 `rm` 或 `FileManager.removeItem`,一旦写错就是数据灾难。当前架构(只读旁观)是唯一安全形态。
