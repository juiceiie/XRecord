#!/bin/bash

# 生成并导入一张自签名代码签名证书（无需 Apple 开发者账号）。
# 用途：让每次构建使用稳定签名身份，避免钥匙串在 App 更新后被反复弹窗。
#
# 证书与私钥输出到：~/Library/Application Support/XRecord/signing
# 请务必备份该目录（尤其是 XRecord.p12），换机或重装后可重新导入。

set -euo pipefail

IDENTITY_NAME="XRecord Self-Signed"
P12_PASSWORD="xrecord"
SIGN_DIR="$HOME/Library/Application Support/XRecord/signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY_NAME"; then
    echo "已存在签名身份「$IDENTITY_NAME」，跳过创建。"
    exit 0
fi

mkdir -p "$SIGN_DIR"
cd "$SIGN_DIR"

openssl req -x509 -newkey rsa:2048 \
    -keyout XRecord.key.pem -out XRecord.cert.pem \
    -days 3650 -nodes -sha256 \
    -subj "/CN=$IDENTITY_NAME/O=XRecord" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" \
    -addext "basicConstraints=critical,CA:false"

# 用旧式算法导出 p12，保证 macOS security import 能识别
openssl pkcs12 -export -legacy \
    -inkey XRecord.key.pem -in XRecord.cert.pem \
    -out XRecord.p12 -name "$IDENTITY_NAME" \
    -passout "pass:$P12_PASSWORD"

security import XRecord.p12 \
    -k "$KEYCHAIN" \
    -P "$P12_PASSWORD" \
    -A -T /usr/bin/codesign -T /usr/bin/security

echo "已创建签名身份「$IDENTITY_NAME」。"
echo "备份目录：$SIGN_DIR"
security find-identity -p codesigning "$KEYCHAIN" | grep "$IDENTITY_NAME" || true
