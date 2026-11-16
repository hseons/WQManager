# 0.4（构建 14）访问能力诊断发布验证

日期：2026-11-16（Asia/Shanghai）。显示版本 0.4，构建号 14；
发布修订与 Git 标签为 0.4.2 / v0.4.2。

## 用户价值

- 签名问题：展示当前进程实际的 App Group 权限与共享目录可用性，提示保留权限重新签名。
- 访问问题：区分查询无结果、缺 token、token 消费失败、目录打开失败、目录读取失败与文件读取样本失败。
- 索引问题：当前 device/inode 或容器 Bundle ID 与缓存不匹配时停止子目录读取，提示刷新索引。
- 反馈质量：主动导出包含系统 build、设备、签名证据、阶段和错误码的 JSON，便于复现兼容性问题。

入口：设置 →「访问能力」→ 选择已有索引中的 App → 开始检查。
可中途停止，并与现有备份／恢复／清理操作互斥。

## 范围

- 每个目录最多检查 64 个直接条目，不递归扫描。
- Documents、Library、tmp 各尝试读取一个普通文件的最多 1 字节。
- 空目录／无普通文件样本明确标记未验证；通过抽样不代表整个容器可读。
- 不写入目标 App。获取访问沿用 WQ 原有工具 App Group 缓存交换流程。
- 共享 App Groups、扩展、系统容器与写入能力未验证。
- 报告不包含 App 名、Bundle ID、文件名、路径、token、原始日志或文件内容。
- 模拟器读取 iOS 运行时的 build，避免把主机内核 build 写成 iOS build；合成目标单独标记。
- 界面固定显示 0.4（14），更新检测使用最终 Info.plist 中的 WQMReleaseVersion=0.4.2。

## 已执行

- `bash tests/run_tests.sh`：20 个可移植测试程序全部通过。
- 新增诊断测试覆盖：正常读取、真实 EACCES 文件、空目录、缺失目录、11 种 grant 失败码、
  容器身份过期、错误／缺失归属、链接与路径越界、标签查询时容器替换、取消、64 条目上限、
  报告脱敏与合成目标标记、目标内容／大小／mtime 保持。
- Xcode 27.2：Debug / generic iOS Simulator 和 Release / generic iOS arm64，
  `CODE_SIGNING_ALLOWED=NO`，均构建成功，编译日志无警告。
- 全新 DerivedData 的 `xcodebuild analyze` 成功；仅见 0.4.1 已记录的两条原有提示：
  `WQAccess.m:375` 的 NSNumber 指针转 BOOL，以及 `WQMSpaceLensViewController.m:1278`
  的菜单可能加入空对象。新增诊断文件没有分析提示。
- iPhone 17 Pro / iOS 26.0（23A343）模拟器：中文浅色和英文深色页面正常，
  选择 fixture App → 检查 → 结果 → JSON 分享面板流程通过。
- 实际分享报告核对：系统 build=23A343、Simulator=true、SyntheticTarget=true，
  无 fixture App 名、Bundle ID、路径、文件名或内容。
- `git diff --check`、`bash -n tests/run_tests.sh`、plist / entitlements / 本地化文件
  `plutil -lint` 通过；新增中英文文案键完整、无重复。
- 最终模拟器与设备产物 Info.plist 均含内部修订 0.4.2；主 App 与分享扩展的显示版本及构建号一致。

## 产物

- `WQManager-0.4-build14-unsigned.ipa`，主 App 与分享扩展均为 arm64。
- ZIP 完整性和 bundle 路径检查通过，没有描述文件或代码签名。
- SHA-256：`2072acd37e752b6740d295980c1ecbdd98f46dd135e46d1d5495d04c4e16a291`。
- 本项目没有 npm package；现有分发渠道是 GitHub 源码、标签与 Release 未签名 IPA。

本轮没有安装到真机。App Group 缺失／正常、token 拒绝、受限文件和容器变化的真机矩阵
仍需签名安装后验证。模拟器与本地测试不代表 WQ 真机访问兼容性已验证。
