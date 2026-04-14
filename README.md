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

### 🔒 安全隐私
- **AES-256 加密** — 数据文件加密存储，防止内容泄露
- **跨设备同步** — 复制数据文件到其他设备即可使用
- **密码显示/隐藏** — 一键切换，保护隐私
- **快速复制** — 复制按钮一键复制账号密码

### 🎨 界面设计
- **原生体验** — 完美适配 macOS 视觉风格
- **同色点缀** — 卡片自动继承分组颜色
- **拖拽排序** — 自由调整卡片顺序
- **搜索功能** — 快速定位需要的记录
- **首次欢迎页** — 新用户友好的引导界面

### ⚡ 轻量高效
- **Menu Bar 入口** — 菜单栏快速访问
- **秒级启动** — 纯原生实现，无需 Electron
- **离线可用** — 无需网络，本地运行

## 安装使用

### 方法一：下载 Release（推荐）
1. 进入 [Releases](https://github.com/juiceiie/XRecord/releases) 页面
2. 下载最新版本的 `.dmg` 文件
3. 解压后拖入应用程序文件夹

### 方法二：从源码编译
```bash
git clone https://github.com/juiceiie/XRecord.git
cd XRecord
open XRecord.xcodeproj
```

## 数据加密

数据采用 **AES-256-GCM** 加密算法：
- 文件内容不可直接阅读
- 复制文件到其他设备可正常解密
- 无需额外密码

## 更新日志

### v1.0.1 (2026-04-14)
- 🔐 数据文件 AES-256-GCM 加密存储
- 🔧 修复添加条目时的加密 bug
- 📝 添加日志服务
- ✨ 首次启动显示欢迎界面
- 🎨 优化点击区域

### v1.0.0 (2026-04-14)
- 🎉 首个正式版本发布

## 开源协议

[MIT License](LICENSE)
