# 第三方项目与致谢

WQManager 自身代码以 GNU GPL v3 或更高版本发布，完整 GPL v3 文本随应用提供于 `LICENSE`，不提供任何形式的保证。

## 包含或改编的 GPL 代码

### WQFiles

- 项目：Worse Query Files
- 作者：kolbicz
- 来源：https://github.com/kolbicz/WQFiles
- 许可证：GPL-3.0-or-later
- 包含或改编：容器访问、容器枚举、Launch Services 显示名称查询、文件系统安全检查及相关支持代码，涉及 `WQAccess`、`WQLaunchServices`、`WQAppsSupport` 和 `WQCacheSafety`。
- 原项目在源文件中保留的版权与许可声明继续保留。

### worse_query

- 项目：worse_query
- 作者/发布者：Taj C（forcequit / forcequitOS）
- 来源：https://github.com/forcequitOS/worse_query
- 许可证：以上游源文件声明为准，GPL-3.0-or-later
- 使用方式：WQFiles 使用的沙盒扩展技术，并由此适配到 WQManager 的容器访问层。

## 设计与流程参考

### KAMUI

- 项目：KAMUI
- 作者：murk-sus
- 来源：https://github.com/murk-sus/kamui-escape
- 使用方式：使用 `fsgetpath` 枚举容器的实现参考。
- 状态：WQManager 未单独包含 KAMUI 源码包。

### GestaltX

- 项目：GestaltX
- 作者：huamidev
- 来源：https://github.com/huamidev/GestaltX
- 许可证：GPL-3.0
- 使用方式：关于页面、许可证展示、双语文档和安全说明组织方式的参考。
- 状态：WQManager 未包含 GestaltX 的源代码或资源。

上述项目各自保留版权与许可证。列出项目名称不代表其为本项目背书，也不代表双方存在隶属关系。

## Apple 框架

WQManager 仅链接 Apple 平台框架。Apple SDK、二进制文件和文档不随本仓库分发。

Apple、iOS 及相关名称是 Apple Inc. 的商标。WQManager 与 Apple 及被管理的 App 开发者均无关联。

