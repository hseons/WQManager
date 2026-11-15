# 0.4.0 发布验证

日期：2026-11-15（Asia/Shanghai）。版本 0.4.0，构建号 12。

## 已执行

- `bash tests/run_tests.sh`：19 个可移植测试程序全部通过。
- 新增测试覆盖历史边界与未知测量、文件筛选与内容对比、队列停止/重试、
  路径规范化与目录范围、格式 3 导入导出、保护状态、保留策略隔离。
- 使用实际 `WQMBackupService` / `WQMRestoreService` 和替代访问桥接，验证嵌套目录恢复、
  未选目录保留、低负载恢复、复制失败回滚、回滚失败后的日志恢复。
- Xcode 27.2（27B52）：Debug / iOS Simulator 构建通过；静态分析通过。
- Release / generic iOS / arm64 / `CODE_SIGNING_ALLOWED=NO` 构建通过。
- `git diff --check`、`bash -n tests/run_tests.sh`、Info.plist 与本地化文件的
  `plutil -lint` 通过；616 个中英文键和格式占位符一致。
- iPhone 17 Pro / iOS 26.0 模拟器，使用 Debug fixture 数据检查文件查找、目录选择、
  批量备份、深色历史趋势和备份对比页面。该项是界面检查，不是容器权限测试。

静态分析仍存在原有访问层 NSNumber 布尔转换与空间透镜菜单可空项告警，
已在修改前 HEAD 的独立源码导出中复现。本轮新增代码的分析告警已处理。

本项目没有 npm package；分发渠道是 GitHub 源码、版本标签与 Release 中的未签名 IPA。
`npm pack --dry-run` 不适用于这个 Objective-C/Xcode 工程；本轮检查实际 IPA 包。

## 产物

- 文件：`WQManager-0.4.0-unsigned.ipa`
- 架构：arm64
- App：`mumu.pduola.WQManager`
- 分享扩展：`mumu.pduola.WQManager.Share`
- App 与扩展的版本、构建号均已核对；ZIP 完整性检查通过。
- 没有嵌入 provisioning profile 或代码签名。安装前需按原有流程自行签名，并保留 App Group。
- SHA-256：`9514534441d813480c4413c72cf69d95e062400244350db06563999db02aec3e`

## 仍需真机回归

1. 在有 App Group 的签名环境下，验证实际 token 获取、失效与容器身份变化。
2. 对带大量文件的 App 验证目录级备份、恢复、导出和回滚。
3. 验证前后台切换、系统终止、受保护数据不可读与低磁盘空间。
4. 验证媒体预览、分享扩展导入以及多 GB 文件的耗时和发热。

目录级自定义备份使用格式 3，旧版本会拒绝导入；快速/完整备份仍为格式 2。
备份保护由 0.4.0 及以上版本执行，旧版本不会识别该保护标记。
批量队列不承诺后台持续执行或退出后的自动续跑。

下一步研究与进入条件见 [NEXT_STEPS_WQ.md](NEXT_STEPS_WQ.md)。
