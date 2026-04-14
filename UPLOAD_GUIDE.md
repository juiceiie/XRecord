# GitHub 上传指南

## 1. 在 GitHub 创建仓库

1. 登录 GitHub：https://github.com
2. 点击右上角 **+** → **New repository**
3. 填写信息：
   - Owner: `juiceiie`
   - Repository name: `XRecord`
   - Description: `🍎 一款简洁优雅的 macOS 原生账号密码管理工具`
   - 选择 **Public**（公开）
   - 不要勾选 "Add a README file"（已有）
   - 选择 MIT License（已有）

## 2. 本地初始化并推送

在终端执行：

```bash
cd /Users/juiceiiecyr/Desktop/xrecord-mac

# 初始化 Git 仓库
git init

# 添加所有文件
git add .

# 提交
git commit -m "✨ Initial commit - XRecord macOS password manager"

# 添加远程仓库
git remote add origin https://github.com/juiceiie/XRecord.git

# 推送
git branch -M main
git push -u origin main
```

## 3. 创建 Release（可选，方便用户下载）

1. 在 GitHub 仓库页面点击 **Releases** → **Draft a new release**
2. 填写版本号（如 `v1.0.0`）
3. 编译发布版本：
   ```bash
   cd /Users/juiceiiecyr/Desktop/xrecord-mac
   xcodebuild -project XRecord.xcodeproj -scheme XRecord -configuration Release build
   ```
4. 找到编译产物 `~/Library/Developer/Xcode/DerivedData/XRecord-xxx/Build/Products/Release/XRecord.app`
5. 打包并上传到 Release

## 4. 添加 Topics（方便搜索）

在仓库页面右侧点击 **About** 旁边的齿轮，设置 Topics：
- `macos`
- `swiftui`
- `password-manager`
- `swift`
- `apple`

---

完成以上步骤后，你的 XRecord 就正式开源了！🎉
