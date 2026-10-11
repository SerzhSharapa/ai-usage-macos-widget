<div align="center">

# ai-usage-macos-widget

**在 macOS 通知中心查看 AI 订阅额度 —— 无论你用哪个编程智能体都能看到。**

[README in English](README.md) · [Русский README](README.ru-RU.md)

状态：**早期开发** · 许可证：MIT

</div>

## 这是什么

一个小巧的 macOS 原生应用（SwiftUI + WidgetKit），以小组件的形式显示在
通知中心和菜单栏中，展示 AI 订阅额度的使用情况 —— 风格类似 DSH 插件
`@linxin666/dsh-usage` 的 LIMITS 卡片。

与依赖特定 harness 的插件不同，它独立于编程客户端：数据直接从
提供商获取，无论你使用 Kilo、DSH 还是其他工具，只要账号相同，
看到的数字都一样。

计划支持的提供商（2026-10-11 对照参考插件核实）：

| 提供商 | 显示内容 |
|---|---|
| OpenAI (Codex / ChatGPT) | 套餐用量窗口 |
| Z.ai (GLM Coding Plan) | 5 小时和每周窗口 |
| Kimi Code | 5 小时和每月窗口 |
| OpenRouter | 按量付费余额 |

## 工作原理

```
┌────────────────────────┐        ┌─────────────────────────────┐
│  伴生应用               │        │  提供商 (HTTPS)              │
│  • 菜单栏视图           │◄──────►│  OpenAI · Z.ai · Kimi · OR  │
│  • 拉取 + 缓存          │        └─────────────────────────────┘
│  • 密钥存于 Keychain    │
└──────────┬─────────────┘
           │ WidgetKit 时间线
           ▼
┌────────────────────────┐
│  通知中心小组件          │
│  (SwiftUI)             │
└────────────────────────┘
```

- API 密钥存储在 macOS **Keychain** 中 —— 绝不进入 git、日志或小组件本身。
- 小组件按系统 WidgetKit 预算刷新（约 15–60 分钟一次）；菜单栏视图支持手动刷新。

## 状态

项目处于早期开发阶段；架构通过 GSD 流程规划。路线图见 [.planning/](.planning/)。

## 致谢

端点研究参考了 DeepSeek Harness 的优秀插件
[`@linxin666/dsh-usage`](https://www.npmjs.com/package/@linxin666/dsh-usage)。

## 许可证

[MIT](LICENSE)
