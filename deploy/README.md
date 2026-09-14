# Web 发布

`nginx-ruanchuang.conf` 将 Flutter Web 静态资源从 `/opt/ruanchuang/web/current` 提供到 HTTP 80，并把 FastAPI 路由代理到 `127.0.0.1:8000`。SQLite 不在 Web 根目录。

构建生产 Web：

```powershell
flutter build web --release --no-wasm-dry-run --dart-define=API_BASE_URL=http://8.133.250.216
```

服务器安全组需要允许 TCP 80。绑定正式域名后再配置 TLS，当前 IP 访问使用 HTTP。
