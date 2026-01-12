# iOS-JPD-Dylib-Build
# ForceWKWebViewSelect (iOS Dylib)

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/yourname/ForceWKWebViewSelect/actions)
[![Platform](https://img.shields.io/badge/Platform-iOS%20(Non--Jailbreak)-blue)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/license-MIT-green)](./LICENSE)

一个专为 **非越狱 (Non-Jailbreak)** 环境设计的 iOS 动态库 (.dylib)。
通过注入目标 IPA，强制解除 App 内 WKWebView 的文本选择与复制限制。

## ✨ 特性 (Features)

* **🛡 非越狱支持**：纯 Objective-C Runtime 实现，不依赖 CydiaSubstrate/Substitute，完美支持 Sideloadly、ESign 等工具注入。
* **💉 双重 Hook**：同时支持代码创建 (`initWithFrame:`) 和 Storyboard 创建 (`initWithCoder:`) 的 WebView。
* **⚔️ 强力对抗 CSS**：
    * 针对常见的 `html { -webkit-user-select: none; }` 屏蔽手段进行覆盖。
    * 使用 `AtDocumentEnd` 时机注入，确保覆盖原网页样式。
    * 内置 `setInterval` 定时器守护，防止网页通过 JS 动态重置屏蔽属性。
* **🚀 轻量级**：编译后体积极小，不影响 App 启动速度。

## 🛠 原理 (How it works)

很多 App 通过在本地资源包 (如 `custom.css`) 中添加以下 CSS 来禁止复制：
```css
html, body {
    -webkit-user-select: none; /* 禁止选择 */
    user-select: none;
}
