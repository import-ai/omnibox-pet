# 桌宠小黑（OmniBox Pet）

小黑 OmniBox 的键盘桌宠，支持 macOS 和 Windows。小黑躲在键盘后探头，跟着你打字、移动鼠标，也会打瞌睡。

![桌宠小黑 12 种状态](docs/xiaohei-states.jpg)

## 下载与安装

### macOS

支持 macOS 11 或更新版本，适用于 Apple 芯片和 Intel 芯片的 Mac。

1. 从 [GitHub Releases](https://github.com/import-ai/omnibox-pet/releases) 下载 `OmniBoxPet-macOS-universal.zip`。如果还没有正式版本，可登录 GitHub，从 [最近一次成功的主分支构建](https://github.com/import-ai/omnibox-pet/actions/workflows/desktop-build.yml?query=branch%3Amain+is%3Asuccess) 下载 `XiaoheiPet-macOS-universal`，再解压其中的应用 ZIP。
2. 解压后，将 `桌宠小黑.app` 拖到「应用程序」，然后打开。
3. 在「系统设置 → 隐私与安全性 → 输入监控」里启用「桌宠小黑」，再从菜单栏小黑图标选择「重启桌宠小黑」。如果更新后小爪对键盘没反应，可以在同一位置重新授权。

### Windows

在 Windows 10 或 11（x64）上，从同一下载页面获取 `XiaoheiPet-Windows-x64.zip`，解压后打开 `XiaoheiPet.exe`。也可从成功的主分支构建下载 `XiaoheiPet-Windows-x64`。右键点击小黑或系统托盘里的小黑图标即可打开菜单。

## 和小黑互动

- 打字和使用鼠标时，悬浮小爪会跟着按键和握鼠标。
- 摸摸小黑的头，它会眯眼。闲置一会儿，它会打瞌睡。
- 右键点击小黑或点击菜单栏图标可打开菜单。关闭「显示悬浮小爪」后，小黑仍会朝按下的键点头。

## 皮肤与更新

- 「皮肤」里会展示小黑的造型。当前可用的是默认造型，衣服、帽子和首饰上线后可在这里换装。
- 应用启动时会检查更新。你也可以从菜单选择「检查更新」。若有新版，应用会提示你前往发布页下载。更新前请先退出当前版本。

## 来源

本项目 Fork 自 [chanke17/KuroCat](https://github.com/chanke17/KuroCat)，采用 [MIT 许可证](LICENSE)。
