<!-- 文件说明：MusicBar 软件介绍、界面预览和开源协议入口 -->

<div align="center">
  <img src=".github/image/app-icon.png" width="128" height="128" alt="MusicBar" />
  <h1>MusicBar</h1>
  <p>让网易云音乐桌面歌词背景和文字样式更顺眼的 <b>macOS 桌面工具</b></p>
  <p><sub>Swift · Objective-C Runtime · AppKit · macOS</sub></p>
  <p>
    <img src="https://img.shields.io/badge/platform-macOS-000000?style=for-the-badge&logo=apple&logoColor=white" alt="platform" />
    <img src="https://img.shields.io/badge/Swift-FA7343?style=for-the-badge&logo=swift&logoColor=white" alt="Swift" />
    <img src="https://img.shields.io/badge/AppKit-147EFB?style=for-the-badge&logo=apple&logoColor=white" alt="AppKit" />
    <img src="https://img.shields.io/badge/license-MIT-2ea44f?style=for-the-badge" alt="license" />
  </p>
</div>

## 简介

MusicBar 是一个面向网易云音乐 macOS 客户端的桌面美化工具，主要用于调整桌面歌词区域的背景和文字效果。它把常用的样式配置收敛到一个原生窗口里，不需要手动修改配置文件，也不需要反复执行命令。

- **背景样式** — 支持透明、纯色和渐变背景，适合不同壁纸和桌面主题
- **歌词样式** — 支持歌词颜色、字号、字体和歌词渐变，让桌面歌词更清晰
- **实时预览** — 在应用前先查看当前样式效果，减少反复试错
- **备份恢复** — 应用修改前保留备份，后续可以恢复到原始状态
- **原生体验** — 使用 macOS 原生界面，窗口、控件和系统体验保持一致

## 界面预览

<p align="center">
  <img src=".github/image/new.png" width="880" alt="修改后的桌面歌词效果" />
  <br /><sub>桌面歌词效果 · 背景与文字样式调整后</sub>
</p>

<table>
  <tr>
    <td width="50%"><img src=".github/image/old.png" alt="原始桌面歌词效果" /></td>
    <td width="50%"><img src=".github/image/new.png" alt="修改后的桌面歌词效果" /></td>
  </tr>
  <tr>
    <td align="center"><sub>原始效果</sub></td>
    <td align="center"><sub>修改效果</sub></td>
  </tr>
</table>

<table>
  <tr>
    <td width="33%"><img src=".github/image/1.png" alt="样式配置界面" /></td>
    <td width="33%"><img src=".github/image/2.png" alt="样式预览界面" /></td>
    <td width="33%"><img src=".github/image/3.png" alt="应用后的界面效果" /></td>
  </tr>
  <tr>
    <td align="center"><sub>透明模式</sub></td>
    <td align="center"><sub>纯色模式</sub></td>
    <td align="center"><sub>渐变模式</sub></td>
  </tr>
</table>

## 开发

需要本机已安装 Xcode Command Line Tools。

```bash
make build
```

## 打包

```bash
make dmg
```

打包完成后会生成 `dist/MusicBar.dmg`。

## 友情链接

- [LINUX DO](https://linux.do) —— 新的理想型社区

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。
