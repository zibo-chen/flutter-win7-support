# Flutter 3.44.1 / Win7 实验分支使用说明

本分支以官方 Flutter 3.44.1 为基线，同时维护匹配的 Dart 补丁。
当前验收状态以 [README](README.md) 和 evidence 中的具体记录为准。
目标为 Windows 7 SP1 x64 上运行 Release 应用；开发和构建使用较新的 Windows。

## 构建和取用

源码分支为 `medivh/win7-3.44.1`，固定版本见 `build-config.json`。
GitHub Actions 的 Windows engine workflow 从源码编译引擎、Dart SDK 和 AOT 编译器，
产出 `engine-acceptance-windows-x64`。其中 `local-engine/host_release` 是匹配的一套 SDK。

将仓库放在短路径（例如 `C:\f`），将上述目录恢复到
`C:\f\engine\src\out\host_release`。执行：

```powershell
.\win7\build-smoke.ps1 `
  -EngineOut C:\f\engine\src\out\host_release `
  -OutputDirectory C:\win7-smoke-output
```

该脚本会核验版本、运行匹配的 Dart 探针、补齐已验证来源的着色器头文件，
并在 SDK 目录外生成测试项目。旧归档缺少着色器头文件时，只有整个头文件目录
与归档记录的源码提交一致才允许恢复。

`Package existing Windows engine` workflow 可复用已经编译的 SDK，避免反复编译引擎。
修改 `package-request.json` 中的来源 run、完整提交和 request_id 即可请求打包；
不要将其他版本的 DLL、Dart、平台 SDK 或 gen_snapshot 混入这套产物。

## 接入业务应用

业务项目应位于 Flutter SDK 目录外。先在较新的 Windows 上执行依赖解析，再使用：

```powershell
C:\f\bin\flutter.bat `
  --local-engine-src-path C:\f\engine\src `
  --local-engine host_release `
  --local-engine-host host_release `
  build windows --release
```

测试启动程序使用静态 C++ 运行库，避免依赖目标机安装的 VCRUNTIME。
业务项目需要明确选择静态链接或分发兼容运行库；原生插件、识别 SDK、相机和打印库
仍需各自核对 Win7 API 与运行库依赖。最小测试应用通过不能代替这些业务验收。

## 实机复验

将完整应用目录复制到 Win7，保持 data 等子目录完整。对本仓库测试应用可执行：

```powershell
.\win7\test-app.ps1 `
  -BundleRoot C:\win7-smoke-output `
  -ReportDirectory C:\win7-results
```

脚本使用已登录用户的交互会话，结束后删除临时计划任务，保存运行 JSON 和应用窗口截图。
必须同时检查运行报告、实际截图及交互结果；仅有编译成功或 DLL 加载成功不足以验收。
中文输入法、业务外设、长时间稳定性和其他系统版本需要单独验证。

## 后续升级

每次升级选择一个明确的官方 Flutter 基线，更新匹配的 Dart 固定提交，再重放最小补丁。
先完成 Windows CI 编译和探针，再在 Win7 和较新 Windows 上复验，最后接入业务应用。
默认分支保留上游参考，兼容补丁集中在维护分支，避免直接修改官方版本标签。
