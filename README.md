<p align="center"><img src="docs/icon.png" width="128" alt="SnipText icon"></p>

# SnipText

App menu bar cho macOS (15+): bấm phím tắt, kéo chọn vùng màn hình, chữ được copy vào clipboard.
OCR chạy offline bằng Apple Vision, tự nhận diện ngôn ngữ (tiếng Việt, English, …), đọc được cả QR/barcode.
Chụp code: chọn **Xuống dòng → Giữ thụt lề (cho code)** trong Cài đặt. App sẽ dựng lại thụt lề và không tự sửa chính tả.

## Cài đặt

### Homebrew (khuyên dùng)

```bash
brew install --cask khduy/tap/sniptext
```

Cask tự gỡ cờ quarantine, nên không cần chạy `xattr`. Mở SnipText và làm theo màn hướng dẫn để cấp quyền. Cập nhật bằng `brew upgrade --cask sniptext`.
Gỡ sạch (cả lịch sử và cài đặt) bằng `brew uninstall --zap --cask sniptext`.

### Tải thủ công

1. Tải `SnipText-x.y.z.zip` ở trang [Releases](../../releases), giải nén, kéo **SnipText.app** vào **Applications**.
2. App chưa được Apple notarize nên cần gỡ cờ quarantine **một lần**:
   ```bash
   xattr -dr com.apple.quarantine /Applications/SnipText.app
   ```
3. Mở SnipText. Màn hướng dẫn sẽ dẫn bạn cấp quyền Screen & System Audio Recording; app tự phát hiện khi
   quyền đã bật và tự khởi động lại.

### Đã bật quyền mà app vẫn báo chưa có?

| Nguyên nhân | Cách xử lý |
|---|---|
| Chưa khởi động lại app sau khi bật quyền | Menu SnipText → **Cấp quyền ghi màn hình…**, app nhận ra quyền đã bật và hiện nút **Khởi động lại** |
| Mục quyền thuộc về bản cài cũ (công tắc vẫn bật nhưng không có tác dụng) | Menu SnipText → **Cấp quyền ghi màn hình…** → **Đặt lại quyền**, rồi bật lại |
| App chạy từ Downloads, chưa gỡ quarantine (macOS chạy bản tạm) | Kéo vào Applications và chạy lệnh `xattr` ở trên. App sẽ tự cảnh báo trường hợp này |
| Chạy file thực thi trực tiếp từ Terminal/Xcode (quyền bị tính cho Terminal/Xcode) | Mở bằng `open SnipText.app` hoặc từ Finder |

Mọi bản phát hành đều được ký bằng cùng một chứng chỉ, nên cập nhật app không làm mất quyền.

## Phát triển

```bash
scripts/setup-signing.sh      # một lần: tạo chứng chỉ "SnipText Dev" trong .signing/
scripts/build-app.sh          # → build/SnipText.app
open build/SnipText.app
swift test                    # nếu xcode-select trỏ vào CLT: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

`.signing/` không đưa lên git. Thư mục này chứa `SnipTextDev.p12` (chứng chỉ + khoá riêng) và mật khẩu của nó.
**Hãy sao lưu hai file này.** Nếu mất, các bản sau sẽ ký bằng chứng chỉ khác và mọi người dùng phải cấp lại quyền.
Trên máy mới, chép hai file vào `.signing/` trước khi chạy `setup-signing.sh`.

### Tự kiểm tra

```bash
open build/SnipText.app --args --self-test
cat ~/Library/Caches/SnipText/self-test.txt
```

App tự chụp màn hình chính bằng ScreenCaptureKit, OCR dải menu bar, ghi kết quả ra file rồi thoát.

Để xem ảnh mà OCR nhận được, bật lưu ảnh vùng chọn gần nhất (mặc định tắt, vì ảnh có thể chứa bất cứ gì trên màn
hình; "Xoá lịch sử" cũng xoá ảnh này):

```bash
defaults write io.github.khduy.sniptext saveLastCapture -bool true
open ~/Library/Caches/SnipText/last-capture.png
```

Xuất ảnh giao diện khung chọn, Cài đặt và onboarding (dùng nội dung giả, không cần quyền) để xem nhanh:

```bash
open build/SnipText.app --args --render-previews /tmp/sniptext-previews
```

## Phát hành

Một lần, thêm chứng chỉ vào GitHub Secrets của repo:

```bash
gh secret set SIGNING_CERT_P12 < <(base64 -i .signing/SnipTextDev.p12)
gh secret set SIGNING_CERT_PASSWORD < .signing/p12-password.txt
```

Để workflow tự cập nhật cask trong [khduy/homebrew-tap](https://github.com/khduy/homebrew-tap), tạo một
fine-grained token chỉ có quyền **Contents: Read and write** trên repo `homebrew-tap`, rồi:

```bash
gh secret set HOMEBREW_TAP_TOKEN
```

Không có token thì cập nhật tay sau khi release xong: `scripts/update-tap.sh 0.1.0`.

Mỗi lần phát hành, push một tag. Workflow [release.yml](.github/workflows/release.yml) sẽ build universal
(arm64 + x86_64), ký, đóng gói zip, tạo GitHub Release và cập nhật cask:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

Muốn đóng gói trên máy thì chạy `scripts/package-release.sh 0.1.0`, kết quả ở `build/SnipText-0.1.0.zip`.

Logo được vẽ bằng code trong `scripts/make-icon.swift`. Sửa xong chạy `scripts/make-icon.sh` để tạo lại
`Resources/AppIcon.icns`.

## Cấu trúc

- `Sources/SnipTextKit`: phần lõi, có test. Gồm chụp màn hình (ScreenCaptureKit), OCR + barcode (Vision),
  xử lý xuống dòng (`TextFormatter`) và lịch sử (JSON trong `~/Library/Application Support/SnipText`).
- `Sources/SnipText`: UI gồm MenuBarExtra, khung chọn vùng (`SelectionOverlay`), onboarding, HUD, Settings,
  xử lý quyền (`Permissions`) và phím tắt (KeyboardShortcuts, mặc định ⌘⇧2).

## Ghi công

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT): ghi và đăng ký phím tắt toàn cục.
- [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow) (MIT): mở trang quyền trong System Settings
  kèm khung nổi để kéo SnipText vào danh sách.
- Bố cục và luồng onboarding tham khảo [Gõ Nhanh](https://github.com/khaphanspace/gonhanh.org) (BSD-3-Clause).
