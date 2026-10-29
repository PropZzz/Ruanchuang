# Flutter 原生客户端共享资源

此目录不再保存 Web 页面导出。当前 Web 的唯一源码入口是 `web/`，移动页面直接维护在 `web/stitch/mobile/`。

此处保留 `pubspec.yaml` 声明的原生资源路径：

- `assets/images/`：Flutter 资源包图片，包含原生主界面引用的 `a2aaefce0709.png`。
- `assets/fonts/bad5f68b18b9.ttf`：StitchInter，字重 400。
- `assets/fonts/11e1d80f42f9.ttf`：StitchInter，字重 500。
- `assets/fonts/e9191f0db3ed.ttf`：StitchInter，字重 600。
- `assets/fonts/1be3d765b0bd.ttf`：StitchInter，字重 700。

旧 `screens/`、画板清单、导出专用资源和下载脚本在 2026-10-29 清理。恢复位置与范围见 `docs/cleanup-2026-10-29.md`。不要整体删除此目录或将其上传为 Web 站点。
