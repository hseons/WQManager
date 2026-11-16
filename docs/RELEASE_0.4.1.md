# 0.4.1 发布验证

日期：2026-11-16（Asia/Shanghai）。版本 0.4.1，构建号 13。

## 修复范围

- 共享备份头文件补全空值契约，保留可空返回值、可选回调和输出指针。
- 进程服务查询沿用已有的带类型函数指针，移除 `performSelector:` 调用。
- 空间透镜的缺失路径传入明确的测量状态；删除菜单直接持有 `UIAction`。
- 历史记录补齐删除文件类型的图标。
- 空间透镜使用外观 trait 注册；文件夹图片沿用渲染器默认比例，移除 `mainScreen`。

## 已执行

- `bash tests/run_tests.sh`：19 个可移植测试程序全部通过。
- Xcode 27.2（27B52）、iOS 27.2 SDK、部署目标 iOS 26.0：
  Debug / generic iOS Simulator 构建通过，编译日志无警告。
- Release / generic iOS / arm64 / `CODE_SIGNING_ALLOWED=NO` 构建通过，
  编译日志无警告；主应用和分享扩展均包含在构建中。
- `xcodebuild analyze` 完成。仍有两条原有分析提示：
  `WQAccess.m:361` 的 NSNumber 指针隐式转布尔值、
  `WQMSpaceLensViewController.m:1278` 的菜单可能加入空对象。
  在临时目录导出修改前的 `5bfcdc8`，以相同参数分析，复现相同两条提示。
- `git diff --check`、`bash -n tests/run_tests.sh`、plist / entitlements /
  本地化文件 `plutil -lint` 通过；共享头文件以
  `-Werror=nullability-completeness -Werror=nonnull` 进行语法检查通过。
- iPhone 17 Pro / iOS 26.0 模拟器：使用已有 fixture 数据打开空间透镜，
  在页面存活期间切换浅色和深色；气泡边框、文字及文件夹图片正常显示。

本项目没有 npm package；分发渠道是 GitHub 源码、版本标签与 Release 的未签名 IPA。
本轮检查实际 IPA 包，不执行 npm 发布或 `npm pack --dry-run`。

## 产物

- 文件：`WQManager-0.4.1-unsigned.ipa`。
- 主应用与分享扩展均为 arm64，版本 0.4.1、构建号 13。
- Bundle ID：`mumu.pduola.WQManager` / `mumu.pduola.WQManager.Share`。
- ZIP 完整性、主应用与扩展路径检查通过，没有嵌入 provisioning profile 或代码签名。
- SHA-256：`ab0c53abc37ea73998851e72b8291985ececd50df1291f6eed3b147b645058cb`。

本轮未执行真机安装。安装前需按原有流程签名并保留 App Group；
模拟器验证不代表真机容器权限或进程服务可用性验证。
