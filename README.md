<p align="center">
  <img src="Sources/GlanceMDApp/Resources/AppIcon.iconset/icon_256x256.png" alt="Glance.md logo" width="128">
</p>

# Glance.md

> Preview selected Markdown from any app in a lightweight floating popover.
>
> A minimalist local menu bar app. No internet required.

<p align="center">
  <video src="https://github.com/user-attachments/assets/fe119ca5-bbbe-40b5-8919-e085cceb5d97" width="400"></video>
</p>


## Install

```sh
brew tap Liooo/tap
brew install --cask glance-md
```

If macOS blocks the app as an unidentified developer, remove quarantine after install:

```sh
xattr -dr com.apple.quarantine /Applications/GlanceMD.app
```

## Motivation

- For a quick preview, it's been overkill to copy the text, switch to a preview app or browser, paste it, then switch back to the original app.
- Wanted one handy reliable place to preview Markdown from anywhere on the machine
- Wanted to be freed from waiting for another app to support Markdown rendering.

## Key Features

- keyword searching
- best-effort parsing for tables wrapped in narrow windows
- Mermaid.js rendering
- light/dark mode

## Limitation

Some apps do not expose the current text selection through the macOS Accessibility API. As a workaround, copy the text and use clipboard preview hotkey.
