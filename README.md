# 酸奶悬浮宠物

一只会陪 Codex 工作的 macOS 原生悬浮桌宠。酸奶会根据 Codex 的工作状态、授权请求和周用量切换动作，也支持拖动、点击互动和大小调节。

## 功能

- 原生 AppKit/SwiftUI 透明置顶窗口
- 显示 Codex 7 天窗口的剩余用量
- 工作、玩手机、喝可口可乐等随机工作动画
- 授权请求提醒与任务完成气泡
- 根据剩余用量切换梳毛、睡觉和疲惫待机状态
- 三种点击互动动画与拖动反馈
- 75%–150% 宠物尺寸调节，并自动记忆设置

## 环境要求

- Apple Silicon Mac
- macOS 14 或更高版本
- 已安装 Codex macOS 应用
- Xcode Command Line Tools

## 构建与运行

```bash
chmod +x build-app.sh
./build-app.sh
open "build/酸奶悬浮宠物.app"
```

构建完成的应用位于 `build/酸奶悬浮宠物.app`。脚本使用系统 `swiftc` 直接编译，不会修改系统开发环境。

## 权限与数据

酸奶通过本机 Codex app-server 获取任务状态和周用量，不会把数据上传到第三方服务。

## 许可证

Swift 源码与构建脚本采用 [MIT License](LICENSE)。猫咪形象、动画帧、图标及其他视觉素材不包含在 MIT 授权范围内，详见 [ASSETS-LICENSE.md](ASSETS-LICENSE.md)。

下一阶段会继续接入完成、失败等生命周期动画，并增加 Codex 生命周期 Hooks。
