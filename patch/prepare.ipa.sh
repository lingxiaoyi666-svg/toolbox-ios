#!/bin/bash
# 构建 Iridium 未签名 .ipa（越狱 app，装法：TrollStore / 全能签 / Sideloadly 重签）
# 相比原版 prepare.app.sh：产物是 ipa 而非 deb，并且把 AuxiliaryAgent 与 fouldecrypt 一并塞进 .app
set -e

cd "$(dirname "$0")"
cd ..
WORKING_LOCATION="$(pwd)"
APPLICATION_NAME="iridium"
OUT="$WORKING_LOCATION/build/ipa"
TIMESTAMP="$(date +%s)"
ARCHIVE="$OUT/$APPLICATION_NAME.xcarchive"

rm -rf "$OUT"
mkdir -p "$OUT"

# ---------- 1. 编译 ----------
echo "[*] xcodebuild archive (unsigned) ..."
set -o pipefail
xcodebuild -workspace "$WORKING_LOCATION/App.xcworkspace" \
    -scheme "$APPLICATION_NAME" \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    clean archive \
    ARCHS="arm64" ONLY_ACTIVE_ARCH="NO" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGN_ENTITLEMENTS="" \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    GCC_GENERATE_DEBUGGING_SYMBOLS=YES STRIP_INSTALLED_PRODUCT=NO \
    ENABLE_BITCODE=NO COPY_PHASE_STRIP=NO UNSTRIPPED_PRODUCT=NO \
    > "$OUT/xcodebuild.log" 2>&1 || { echo "[!] build failed"; tail -50 "$OUT/xcodebuild.log"; exit 1; }
echo "[i] build passed"

APP="$(find "$ARCHIVE/Products/Applications" -maxdepth 1 -name '*.app' | head -1)"
[ -n "$APP" ] || { echo "[!] xcarchive 里找不到 .app"; exit 1; }

PAYLOAD="$OUT/Payload"
mkdir -p "$PAYLOAD"
cp -R "$APP" "$PAYLOAD/"
TARGET_APP="$PAYLOAD/$(basename "$APP")"

# ---------- 2. 去签名 + ldid ----------
codesign --remove "$TARGET_APP" 2>/dev/null || true
rm -rf "$TARGET_APP/_CodeSignature"
rm -f "$TARGET_APP/embedded.mobileprovision"

LDID_BIN="$(command -v ldid || true)"
[ -n "$LDID_BIN" ] || { echo "[!] ldid not found (brew install ldid)"; exit 1; }
"$LDID_BIN" -S"$WORKING_LOCATION/Workflow/Entitlements.plist" "$TARGET_APP/$APPLICATION_NAME"
echo "[i] ldid signed with platform-application + no-container"

# ---------- 3. AuxiliaryAgent ----------
echo "[*] building AuxiliaryAgent ..."
"$WORKING_LOCATION/AuxiliaryAgent/build.sh"
cp -f "$WORKING_LOCATION/AuxiliaryAgent/build/AuxiliaryAgent" "$TARGET_APP/AuxiliaryAgent"

# ---------- 4. fouldecrypt ----------
( cd "$TARGET_APP" && unzip -oq "$WORKING_LOCATION/Workflow/fouldecrypt.zip" )
echo "[i] fouldecrypt.{tfp0,krw,kernrw} + libkernrw/libkrw 已入包"

# ---------- 5. 统一 arm64 ----------
echo "[*] normalizing architectures to arm64 ..."
find "$PAYLOAD" -type f -print0 | while IFS= read -r -d '' FILE; do
    case "$(file "$FILE" 2>/dev/null || true)" in
        *Mach-O*)
            INFO="$(lipo -info "$FILE" 2>/dev/null || true)"
            case "$INFO" in
                *arm64e*)
                    case "$INFO" in
                        *"arm64 arm64e"*|*"arm64e arm64"*)
                            lipo -thin arm64 -output "$FILE" "$FILE"
                            echo "    thinned $(basename "$FILE")"
                            ;;
                        *)
                            echo "[!] $(basename "$FILE") 只有 arm64e，删掉它（iOS 13 跑不了）"
                            rm -f "$FILE"
                            ;;
                    esac
                    ;;
            esac
            ;;
    esac
done

chmod -R 0755 "$TARGET_APP"

# ---------- 5.5 给包内**每一个** Mach-O 都签上 platform-application ----------
# 原版只签了主二进制：AuxiliaryAgent / fouldecrypt 没 entitlements 的话，
# 自签安装时 setuid(0) 会失败，agent 的 whoami 拿不到 root，列表就是空的。
echo "[*] re-signing every Mach-O inside the bundle ..."
find "$TARGET_APP" -type f -print0 | while IFS= read -r -d '' FILE; do
    case "$(file "$FILE" 2>/dev/null || true)" in
        *Mach-O*)
            "$LDID_BIN" -S"$WORKING_LOCATION/Workflow/Entitlements.plist" "$FILE" 2>/dev/null \
                && echo "    signed $(basename "$FILE")"
            ;;
    esac
done

# ---------- 6. 打 ipa ----------
echo "[*] packaging ipa ..."
cd "$OUT"
IPA_NAME="iridium.unsigned.$TIMESTAMP.ipa"
# 用 python3 的 zipfile：macOS 自带 zip 不写 UTF-8(EFS) 标志，非 ASCII 文件名会乱码
python3 -c "
import os, zipfile
root = 'Payload'
dirs = []
files = []
for r, d, f in os.walk(root):
    d.sort(); f.sort()
    dirs.append(r)
    files += [os.path.join(r, x) for x in f]
z = zipfile.ZipFile('$IPA_NAME', 'w', zipfile.ZIP_DEFLATED, compresslevel=9)
for d in dirs:
    z.writestr(d.replace(os.sep, '/') + '/', b'')
for p in files:
    z.write(p, p.replace(os.sep, '/'))
z.close()
print('entries:', len(dirs) + len(files))
"

echo "=============================================="
echo "IPA : $OUT/$IPA_NAME"
echo "Size: $(du -h "$IPA_NAME" | cut -f1)"
echo "BID : $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$TARGET_APP/Info.plist")"
echo "Ver : $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET_APP/Info.plist")"
echo "=============================================="
echo "$OUT/$IPA_NAME" > "$OUT/ipa-path.txt"
