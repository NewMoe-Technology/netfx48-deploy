# netfx48-deploy — .NET Framework 4.8 一键部署包

把真正的微软 .NET Framework 4.8（x86 + x64，含 GAC）快速部署到任意 Wine / Proton 前缀，
替代 Wine Mono，解决需要完整 .NET Framework 的程序/插件（如 ACT部分Plugin）无法运行的问题。

## 内容

- `deploy.sh`         部署脚本
- `files/`            框架文件（约 450MB）：Microsoft.NET 目录树 + mscoree.dll / mscoreei.dll / *_clr0400.dll
- `registry/netfx.reg`   NDP / .NETFramework 注册表键

## 用法（一条命令）

```bash
./deploy.sh ~/.proton_pfx/pfx

# 部署到 Steam 游戏的 compatdata 前缀
./deploy.sh ~/.local/share/Steam/steamapps/compatdata/39210/pfx -y

# 可选：指定 wine / mono 版本
./deploy.sh ~/Games/pfx --wine /usr/bin/wine --mono-version 9.4.0
```

## 脚本做了什么

1. 停止该前缀的 wineserver
2. 备份 `system.reg` / `user.reg`（*.netfx48bak）
3. 把旧的 `Microsoft.NET`（Wine Mono 残留）改名备份
4. 复制框架文件 + 系统 DLL
5. 合并注册表：删掉旧的 .NET 键（包括 Proton 伪造的"4.8 已安装"键），写入打包的键
6. 设置 `mscoree=native` + `Wine\Mono` 版本标记（防覆盖）

幂等：重复执行安全。

## 验证

```bash
WINEPREFIX=<前缀> wine 'C:\windows\Microsoft.NET\Framework\v4.0.30319\csc.exe' /help
# 打印出 "Microsoft (R) Visual C# Compiler version 4.8.3761.0" 即成功
```

## 撤销

- 注册表：把 `system.reg.netfx48bak` / `user.reg.netfx48bak` 覆盖回去
- 文件：删掉 `drive_c/windows/Microsoft.NET`，把 `Microsoft.NET.mono-bak-*` 改回 `Microsoft.NET`

## 说明

- 装的是 .NET Framework **4.8.0**（4.8.1 的补丁包在 wine 上装不了，绝大多数程序够用）
- 适用于任意 wine/Proton 前缀；脚本自动检测前缀所用的 wine（软链占比最高者）及其 wine-mono 版本
- 包里已剔除：`SetupCache`（MSI 修复缓存 ~460MB）、旧版 .NET 目录（v1.1/v2.0/v3.0/v3.5，
  这些只包含指向本机的 wine 内置 shim 软链，wine 会自己重建，运行 4.8 程序用不到）
- 部署前请确保目标前缀没有被占用（脚本会自动停 wineserver）
