# Third-Party Notices

WQManager application code is licensed under GNU GPL version 3 or later. The
complete GPL v3 text is included in `LICENSE`. No warranty is provided.

## Included or adapted GPL code

### WQFiles

- Project: Worse Query Files
- Repository: https://github.com/kolbicz/WQFiles
- Author: kolbicz
- License: GPL-3.0-or-later
- Included/adapted: container access, container enumeration, Launch Services
  display-name lookup, filesystem safety helpers, and related support code
  derived from `WQAccess`, `WQLaunchServices`, `WQAppsSupport`, and
  `WQCacheSafety`.
- Upstream copyright notices in the source files are preserved.

### worse_query

- Project: worse_query
- Repository: https://github.com/forcequitOS/worse_query
- Author: Taj C (forcequit / forcequitOS)
- License: GPL-3.0-or-later as stated in the upstream source notices.
- Role: sandbox-extension technique used by WQFiles and adapted by WQManager's
  container-access layer.

## Design and workflow references

### KAMUI

- Project: KAMUI
- Repository: https://github.com/murk-sus/kamui-escape
- Author: murk-sus
- Role: reference for container enumeration using `fsgetpath`.
- Status: no independent KAMUI source bundle is included.

### GestaltX

- Project: GestaltX
- Repository: https://github.com/huamidev/GestaltX
- Author: huamidev
- License: GPL-3.0
- Role: reference for the about, license, bilingual documentation, and safety
  presentation patterns.
- Status: no GestaltX source files or assets are included in WQManager.

Each upstream project retains its own copyright and license. A reference to an
upstream project does not imply endorsement or affiliation.

## Apple frameworks

WQManager links Apple platform frameworks. Apple SDK headers, binaries, and
documentation are not redistributed by this repository.

Apple, iOS, and related names are trademarks of Apple Inc. WQManager is not
affiliated with Apple or with the developers of managed apps.

