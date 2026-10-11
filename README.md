<div align="center">

# ai-usage-macos-widget

**AI subscription limits in the macOS Notification Center — visible no matter which coding agent you use.**

[README in Russian](README.ru-RU.md) · [中文说明](README.zh-CN.md)

Status: **early development** · License: MIT

</div>

## What it is

A small native macOS app (SwiftUI + WidgetKit) that shows how much of your
AI subscription quota you have used — as a Notification Center widget and a
menu bar item, in the style of the LIMITS card of the DSH plugin
`@linxin666/dsh-usage`.

Unlike a harness plugin, it is independent of your coding client: it queries
the providers directly, so the same numbers are visible whether you are
working in Kilo, DSH, or any other tool with the same accounts.

Planned providers (verified against the reference plugin, 2026-10-11):

| Provider | What is shown |
|---|---|
| OpenAI (Codex / ChatGPT) | plan usage windows |
| Z.ai (GLM Coding Plan) | 5h and weekly windows |
| Kimi Code | 5h and monthly windows |
| OpenRouter | pay-as-you-go balance |

## How it works

```
┌────────────────────────┐        ┌─────────────────────────────┐
│  Companion app         │        │  Providers (HTTPS)          │
│  • menu bar view       │◄──────►│  OpenAI · Z.ai · Kimi · OR  │
│  • fetch + cache       │        └─────────────────────────────┘
│  • keys in Keychain    │
└──────────┬─────────────┘
           │ WidgetKit timeline
           ▼
┌────────────────────────┐
│  Notification Center   │
│  widget (SwiftUI)      │
└────────────────────────┘
```

- API keys are stored in the macOS **Keychain** — never in git, logs, or the
  widget itself.
- Widgets refresh on the system WidgetKit budget (roughly every 15–60
  minutes); the menu bar view offers on-demand refresh.

## Status

The project is in early development; the architecture is being planned with
the GSD workflow. See [.planning/](.planning/) for the current roadmap once
it appears.

## Acknowledgments

Endpoint research follows the excellent
[`@linxin666/dsh-usage`](https://www.npmjs.com/package/@linxin666/dsh-usage)
plugin for DeepSeek Harness.

## License

[MIT](LICENSE)
