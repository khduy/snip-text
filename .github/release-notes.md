## Cài đặt

```bash
brew install --cask khduy/tap/sniptext
```

Hoặc cài thủ công:

1. Tải `SnipText-*.zip` bên dưới, giải nén, kéo **SnipText.app** vào **Applications**.
2. App chưa được Apple notarize nên cần gỡ cờ quarantine **một lần**:
   ```bash
   xattr -dr com.apple.quarantine /Applications/SnipText.app
   ```
3. Mở SnipText, bấm ⌘⇧2. Bật SnipText trong System Settings → Privacy & Security →
   Screen & System Audio Recording, rồi **khởi động lại app**.

Cập nhật lên bản mới không cần cấp lại quyền, vì mọi bản đều được ký bằng cùng một chứng chỉ.
Nếu đã bật quyền mà app vẫn báo chưa có, vào Cài đặt → "Đặt lại quyền".
