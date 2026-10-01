# AccessibilityLazyVStackPoC

[English](#english) | [中文](#中文)

One Accessibility hit test on an element inside a SwiftUI `LazyVStack` hangs the app's main thread on the next scroll.

## English

### Symptom

The right pane is a 320-point `ScrollView` holding one `LazyVStack`:

```swift
ScrollView {
    LazyVStack(spacing: 16) {
        Text("Header")
        Color.gray
            .frame(height: 2000)
            .overlay {
                VStack(spacing: 0) {
                    ForEach(1...50, id: \.self) { index in
                        Text("Row \(index)")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(index.isMultiple(of: 2) ? Color.black.opacity(0.08) : Color.clear)
                    }
                }
                .accessibilityHidden(true)
            }
        Button("Footer") {}
    }
}
```

A child process calls `AXUIElementCopyElementAtPosition` once on a point inside this stack. The call returns successfully. The next scroll pins the main thread at about 100% CPU and the UI stops responding.

### Call stack

The main thread stays inside the `LazyVStack` layout path:

```
GraphHost.flushTransactions()
  LazySubviewPlacements.updateValue()
    LazySubviewPlacements.placeSubviews()
      LazyStack<>.place(subviews:context:cache:in:)
        StackPlacement.place(subviews:from:position:stopping:style:)
```

A 5-second `sample` capture at 10-millisecond intervals recorded 450 main-thread samples. 445 of them fall under `GraphHost.flushTransactions()`.

### Environment

| | |
| --- | --- |
| Operating system | macOS 26.6.2 (25G83) |
| Machine | Apple M4 Pro |
| Xcode / SDK | 26.6 (17F113) / macosx26.5 |
| Deployment target | macOS 14.2 |
| Build | universal (arm64 + x86_64), ad-hoc signed |

### Reproduce

1. Download `AccessibilityLazyVStackPoC.app.zip` from the [latest release](https://github.com/journey-ad/AccessibilityLazyVStackPoC/releases/latest) and unzip it.
   Run `xattr -dr com.apple.quarantine AccessibilityLazyVStackPoC.app` first.
2. Launch the app and scroll the right pane up and down a few times.
3. Click **Read Accessibility**.
4. If macOS asks for permission, enable the app under System Settings → Privacy & Security → Accessibility, then click the button again.
5. The status line shows `Read succeeded. Scroll the right panel again — the app will stop responding.` Scroll the right pane again. The app hangs.
6. Relaunch the app before each run.

### Build

```bash
xcodebuild -project AccessibilityLazyVStackPoC.xcodeproj \
           -scheme AccessibilityLazyVStackPoC \
           -configuration Release -derivedDataPath build \
           ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
```

[`.github/workflows/build.yml`](.github/workflows/build.yml) runs this on `macos-26` for every push and pull request. On pushes to `main` it also refreshes the `latest` release.

### Notes

- The hit point must land on a subview that the `LazyVStack` lays out. An element hidden with `.accessibilityHidden(true)` does not reproduce the hang.
- One hit test triggers the hang. The hang occurs on a later scroll event.
- These results apply to this machine, this SDK version and this window size.

---

## 中文

对 SwiftUI `LazyVStack` 内的元素做一次 Accessibility 命中测试，下一次滚动会导致应用主线程卡死。

### 现象

窗口右侧是一个宽度 320 pt 的 `ScrollView`，内含一个 `LazyVStack`（代码见上）。

应用启动后，子进程对 `LazyVStack` 内的一点调用一次 `AXUIElementCopyElementAtPosition`，调用返回成功。之后再次滚动右侧面板，主线程占满单核，CPU 使用率约 100%，界面无响应。

### 调用栈

主线程停留在 `LazyVStack` 的布局路径内（栈见上）。5 秒采样（间隔 10 毫秒）共记录主线程 450 个样本，其中 445 个落在 `GraphHost.flushTransactions()` 之下。

### 环境

| | |
| --- | --- |
| 操作系统 | macOS 26.6.2 (25G83) |
| 机器 | Apple M4 Pro |
| Xcode / SDK | 26.6 (17F113) / macosx26.5 |
| 部署目标 | macOS 14.2 |
| 构建 | 通用二进制（arm64 + x86_64），ad-hoc 签名 |

### 复现

1. 从 [latest release](https://github.com/journey-ad/AccessibilityLazyVStackPoC/releases/latest) 下载 `AccessibilityLazyVStackPoC.app.zip` 并解压，先执行 `xattr -dr com.apple.quarantine AccessibilityLazyVStackPoC.app`。
2. 打开应用，在右侧面板上下滚动几次。
3. 点击 **Read Accessibility**。
4. 若系统请求权限，在「系统设置 → 隐私与安全性 → 辅助功能」中打开本应用，然后再次点击按钮。
5. 状态栏显示 `Read succeeded. Scroll the right panel again — the app will stop responding.` 后，再次滚动右侧面板，应用卡死。
6. 每次复现前重新启动应用。

### 构建

构建命令同上。[`.github/workflows/build.yml`](.github/workflows/build.yml) 在 `macos-26` 上为每次 push 与 pull request 执行构建，并在推送到 `main` 时更新 `latest` Release。

### 说明

- 命中点必须落在 `LazyVStack` 参与布局的子视图上。被 `.accessibilityHidden(true)` 隐藏的元素无法复现卡死。
- 一次命中测试即可触发卡死。卡死发生在随后的滚动事件上。
- 以上结论适用于本机、该 SDK 版本与该窗口尺寸。

---

## See also

- [Application Hangs with Nested LazyVStack When Accessibility Inspector is Active](https://developer.apple.com/forums/thread/814208) — Apple Developer Forums
- [pendo-io/SwiftUI_Hang_Reproduction](https://github.com/pendo-io/SwiftUI_Hang_Reproduction) — nested `LazyVStack` hang reproduction project, iOS, Accessibility Inspector and VoiceOver
