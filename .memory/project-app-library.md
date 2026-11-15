---
name: project-app-library
description: 进行中的大需求「手机屏 App 资源库」（手机上直接打开、退出、搜索 Mac 上的 App，Mac 端设置等界面一起按苹果规范重做）：设计记录在 feature/app-library 分支的 docs/design/app-library.md，动工前以它为准
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-15T04:45:17.993Z
---

2026-11-14 主人提出：手机屏首页从「窗口列表」改成以 App 为单位的增删改查（查得全、直接打开或新建窗口、退出 App、默认字典序加搜索）。动机之一：在手机上直接开 Ghostty 新窗口，从一开始就是手机宽度，终端不重排。

**已定**：新窗口用「点了才问、问到就停」的 0.1 秒轮询捕获（主人认可，否掉了 AXObserver 订阅）。取证、接口、形态、待拍板、待实测全部写在分支文档 `docs/design/app-library.md`，**不在这里重复**。

**进度（2026-11-14 晚）**：主人手机实测后提的「窗口也要能单独关」「当前窗口和下面卡片重复」已做完，审查（5+1）的发现已修，真机预览自测通过，都在分支上提交（到 4f4c9f1，文档第十七节）。剩下：请主人再用手机试一次（关窗口、当前 App 卡片）、发版前重截 README 图；合并主干、推远端要先问主人。

**How to apply:** 接着做这件事时先读那份文档；实现中有变化同步改文档。主人已允许在本机随意操作（别伤电脑），真机自测用 `scripts/snug app` 打签名版、先 SIGTERM 正在跑的 Snug、带 `--preview-phone` 启动，测完重新打开 /Applications/Snug.app（手动打开会弹设置窗口，测前没有就关掉）。主人可能正在用这台 Mac：测试别抢焦点、别切主屏的桌面空间（比如别把窗口设成全屏），要写字用辅助功能设值或 postToPid。原型含本机 App 列表，不进仓库。相关：[[project-product]]、[[feedback-ui-style]]、[[feedback-workflow-scale]]。
