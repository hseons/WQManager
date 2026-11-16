# 0.4（构建 16）记录页徽标与空态发布验证

日期：2026-11-16（Asia/Shanghai）。主 App 与分享扩展显示版本 0.4，构建号 16；
内部发布修订与 Git 标签为 0.4.4 / v0.4.4。

## 本次完成

1. 修复记录页状态徽标被压缩截断：徽标 label 与内容列的水平压缩阻力原本同为 750，
   空间不足时缺口被平分，徽标被压到约 12pt 后被圆角裁掉只剩一个字。现在徽标使用
   required 压缩阻力与 required hugging，内容列降到 `UILayoutPriorityDefaultLow`，
   空间不足时先让副标题换行/省略。副标题同时限制为两行并尾部省略。
2. 应用页索引失败态改用危险色，并在状态后追加「下拉可重试」，失败不再与普通说明同色。
3. 清理页没有可清理对象时收起「已选择 N 个 App」与三个快捷筛选项；
   空状态卡片副标题改为「点按此卡片可重新扫描」，点按即重新扫描。
4. 备份行时间改为今天/昨天/日期 + 时间，同年省略年份，跨年保留年份，
   同一 App 的多份备份更容易横向比较。
5. 记录页与备份页的日期格式化器按语言缓存复用，不再逐行创建 `NSDateFormatter`。

## 已执行验证

- `python3 tests/check_project.py`：通过。检查 diff 空白、shell/Ruby/Python 语法、
  plist/entitlements、中英文本地化键一致性、重复键、使用键与格式占位符。
- `bash tests/run_tests.sh`：22 个测试程序全部通过。
- Debug / iOS Simulator 与 Release / generic iOS arm64 构建均成功，编译警告 0 条。
- iPhone 17 Pro / iOS 26.0 模拟器：5 条 XCUITest 全部通过，合计约 64 秒。
- 截图复核：记录页「已回滚 / 成功」徽标完整；应用页失败态为危险色并带重试提示；
  清理页空态无重复文案且无全灰筛选项；备份行显示「昨天 19:12 · 6.44 GB」。
- 最大辅助字号（extra-extra-extra-large）下重跑记录页，徽标仍完整，文字列自行换行。
- 约束冲突日志检查：`Unable to simultaneously satisfy` 无命中。

## 边界与后续验收

- 本轮未安装到真机。真实容器、签名/App Group、受限文件、后台中断和容器变更矩阵仍待验收。
- 备份时间与状态徽标的取值为展示层改动，不改变任何备份、恢复或清理的判定逻辑。

## 分发产物

- `WQManager-0.4-build16-unsigned.ipa`，891285 字节；主 App 和分享扩展均为 arm64。
- ZIP 完整性、Payload 路径、版本与构建号已验证；不含描述文件和代码签名。
- SHA-256：`eb1ffeab68b9c9df4801ede2e0d673049bc60a3a7349b430e4398b40d0470894`。
- 分发渠道：GitHub 源码、`v0.4.4` 标签、Release 中的未签名 IPA 和 SHA-256 文件；项目没有 npm 包。
- 远端自动化执行结果以对应提交的 GitHub Actions `Checks` 为准；本机验证不替代 hosted runner 结果。
