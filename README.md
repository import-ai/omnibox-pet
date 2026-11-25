# 小黑桌宠（Xiaohei Pet）

小黑 OmniBox 的 macOS 键盘桌宠。基于 [KuroCat](https://github.com/chanke17/kurocat)（MIT）改造：把原项目里的黑猫换成只有头部的小黑，保留全局键鼠监听、2.5D 转头、捕猎眼、摸头、打瞌睡等玩法。

![小黑桌宠 12 种状态](docs/xiaohei-states.jpg)

> 状态：**原型 / 草案**。悬浮小爪等适配属于衍生设计，尚未作为小黑的正式形象规范确认。

## 运行

```bash
./build.sh          # 生成 XiaoheiPet.app（arm64 + x86_64，macOS 11+）
open XiaoheiPet.app
```

首次运行后，在「系统设置 → 隐私与安全性 → 输入监控」中勾选「小黑桌宠」，再从菜单栏小黑图标选择「重启小黑桌宠」。没有稳定签名证书时，`build.sh` 使用 ad-hoc 签名，每次重新构建后可能需要重新授权。

右键小黑或点击菜单栏图标打开菜单。「显示悬浮小爪」默认开启，关闭后进入纯头模式。

## 角色来源

- 几何来自 omnibox-art 已选定的正面基准 [front V14](../omnibox-art/assets/ip/xiaohei/front/v14/README.md)：耳朵、头部、眼白、瞳孔四部分路径原样使用。
- `Sources/XiaoheiArt.swift` 由脚本生成，不手改：

  ```bash
  python3 scripts/generate-xiaohei-art.py ../omnibox-art/assets/ip/xiaohei/front/v14/xiaohei-front-v14.svg
  python3 scripts/generate-xiaohei-art.py <同一 SVG> --check   # 校验是否与源 SVG 一致
  ```

- App 图标：`python3 scripts/make-app-icon.py ../omnibox-art/assets/ip/xiaohei/front/v14/xiaohei-front-v14.png`，小黑头部 + 品牌蓝 `#3B82F6` 圆角底。
- 角色色：猫头与瞳孔 `#171717`，眼白 `#FEF6EC`。

## 身份约束与适配

遵守 omnibox-art 的小黑固定身份：只有头部，没有鼻子、嘴巴、胡须、身体、脖子、四肢或尾巴，不加瞳孔高光。原版依赖身体的玩法改为：

| KuroCat 原玩法 | 小黑桌宠 |
| --- | --- |
| 猫身体 + 前爪打字、握鼠标 | 头部悬浮在键盘上方；两只**不连接头部的悬浮小爪**按键、握鼠标（衍生设计，可关闭） |
| 关闭小爪 | 纯头模式：小黑朝按下的键点头 |
| 3 键同时按「用脚按」 | 小黑用头顶第 3 个键，键上出现品牌蓝冲击线 |
| 4 键同时按「用尾巴按」 | 不画尾巴，只在第 4 个键上显示冲击线 |
| 竖瞳 → 捕猎大圆瞳 | 圆瞳放大（基础形象本来就是圆瞳） |
| 摸头眯眼、打瞌睡、打哈欠 | `^ ^` 笑眼、`︶` 闭眼；不画嘴，打哈欠时只闭眼 |
| 打字太快生气 | 「思考中」表情包式的平顶半眯眼，内眼角压低，旁边加 💢 符号 |
| 被拎起 | `> <` 挤眼（参考「加油」「赞」表情包） |
| 头晕 | 螺旋眼 + 星星 |
| 皮肤、瞳色切换 | 已从菜单移除，小黑配色固定 |

悬浮小爪的造型参考「记笔记」「赶工」表情包：黑色圆团，浅色描边，前缘两道趾缝。omnibox-art 规范说明，表情包中的装饰不代表小黑拥有对应器官，所以小爪只用于这个桌宠，**不是**小黑基础设定。小黑轮廓外的浅色描边是贴纸式描边，用来在深色壁纸上保持可读，不属于角色结构。

转头、侧视时眼睛的移动和透视压缩，是基于正面图的最小推导，没有使用侧面转面图。

## 与上游的差异

- Bundle ID 为 `pro.omnibox.xiaohei-pet`，开机自启的 LaunchAgent 同名，和 KuroCat 互不影响。
- 关闭了上游的自动更新检查和应用内自更新（否则会下载 KuroCat 覆盖本应用），移除了皮肤导入的拖放入口。
- 只改了 macOS（`Sources/`）。`windows/`、`linux/` 仍是上游的猫，构建和发布工作流未适配。
- 上游说明保留在 [README.kurocat.md](README.kurocat.md)、[README.kurocat.en.md](README.kurocat.en.md)，许可证见 [LICENSE](LICENSE)。

## 视觉检查

```bash
./XiaoheiPet.app/Contents/MacOS/XiaoheiPet --render-xiaohei-preview out/qa/xiaohei/sheet.png          # 浅色背景
./XiaoheiPet.app/Contents/MacOS/XiaoheiPet --render-xiaohei-preview out/qa/xiaohei/sheet-dark.png --dark
```

不打开窗口，直接输出 12 种状态的总览图。`out/` 已被 Git 忽略。
