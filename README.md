# XRecord

> 🍎 一款简洁优雅的 macOS 原生账号密码管理工具

![Platform](https://img.shields.io/badge/Platform-macOS%2013+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![SwiftUI](https://img.shields.io/badge/SwiftUI-green)
![License](https://img.shields.io/badge/License-MIT-lightgrey)

## 截图

![XRecord 截图](screenshots/screenshot.png)

## 功能特点

### 📁 数据管理
- **分组管理** — 创建、编辑、删除分组，自定义分组颜色
- **卡片条目** — 支持名称、网址、账号、密码、备注
- **本地存储** — 数据存储在本地文件，完全可控
- **文件绑定** — 可绑定任意位置的数据文件

### 🔒 安全便捷
- **密码显示/隐藏** — 一键切换，保护隐私
- **快速复制** — 复制按钮一键复制账号密码
- **链接直达** — 点击网址直接用浏览器打开

### 🎨 界面设计
- **原生体验** — 完美适配 macOS 视觉风格
- **同色点缀** — 卡片自动继承分组颜色
- **拖拽排序** — 自由调整卡片顺序
- **搜索功能** — 快速定位需要的记录

### ⚡ 轻量高效
- **Menu Bar 入口** — 菜单栏快速访问
- **秒级启动** — 纯原生实现，无需 Electron
- **离线可用** — 无需网络，本地运行

## 安装使用

### 方法一：下载 Release（推荐）
1. 进入 [Releases](https://github.com/juiceiie/XRecord/releases) 页面
2. 下载最新版本的 `.zip` 文件
3. 解压后拖入应用程序文件夹

### 方法二：从源码编译
```bash
# 克隆仓库
git clone https://github.com/juiceiie/XRecord.git
cd XRecord

# 打开 Xcode 项目
open XRecord.xcodeproj

# 在 Xcode 中点击运行 (⌘R)
```

## 数据文件

首次运行会提示创建或选择数据文件，默认存储为 `~/Desktop/xrecord/record.txt`（JSON 格式）。

文件格式示例：
```json
{
  "appTitle": "XRecord",
  "groups": [
    {
      "id": "uuid",
      "name": "生产环境",
      "colorHex": "4f6ef7",
      "order": 0
    }
  ],
  "cards": [
    {
      "id": "uuid",
      "groupId": "uuid",
      "name": "GitHub",
      "url": "https://github.com",
      "username": "user@example.com",
      "password": "password123",
      "note": "工作账号",
      "createdAt": "2026-04-14T10:00:00Z"
    }
  ]
}
```

## 系统要求

- macOS 13.0 (Ventura) 或更高版本
- Apple Silicon / Intel Mac

## 技术栈

- **Swift 5.9** — 编程语言
- **SwiftUI** — 声明式 UI 框架
- **AppKit** — 原生系统集成
- **Xcode 15+** — 开发工具

## 参与贡献

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 创建 Pull Request

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。

---

⭐ 如果这个项目对你有帮助，请给我一个 Star！
