---
name: project-demo-recording
description: 演示录制（进行中）：三块屏原画并排的真实使用演示，正式素材和粗剪已就绪；素材、清单、脚本全在 footage/（绝不进 git）；剪辑交给 kineto，主人说交接时才交
metadata:
  node_type: memory
  type: project
  originSessionId: f97709de-705a-489b-bb7a-7353b1fba51c
  modified: 2026-11-16T03:45:00.000Z
---

**用途**（11-15 主人提）：小红书上很多人追更，录一段三块屏同框的真实使用演示（Mac、外接显示器、手机屏），手机上操作的同时让人看到屏幕怎么变，比宣传片真实（主人原话「三块在一个视频中演示效果最炸裂」）。也要用来换掉 README 里 2.2 的旧演示动图（[[project-domestic-mirror]]）。

**方案**：全在这台 Mac 上用 OBS 采三块屏原画并排（7944×2160，30 帧，硬件 HEVC；60 帧时 90% 的帧被丢掉）。手机上看到的就是 Snug 手机屏，直接采原画比在手机上录清楚；三路在同一个软件里采，不用后期对齐。触摸点靠手机屏那一路「显示光标」（UU 每次点击先把鼠标移过去）。演示动作挑 Mac 实体屏上看得出变化的：把窗口放上手机、点「还原」飞回原处、在手机上退出 App 或关窗口。否掉了第二部设备俯拍、iPhone 自带录屏、数据线接 QuickTime。

**现状**：正式素材 `footage/raw/2026-11-15_08-37-10.mp4`（7 条动作齐全），粗剪 `footage/cuts/rough-v2.mp4`（138 秒，FFmpeg 剪掉了等待），交接说明 `footage/handoff-kineto.md` 已指向这两个文件。早先的彩排二和 rough-v1 已被取代。

**分工与红线**：
- 剪辑交给 kineto 那边的会话（项目隔离）。这边负责录制、素材清单、对好 Snug 日志的时间、写内容生产说明。**主人说交接时才交**，在那之前不联系 kineto，也不在 kineto 仓库里动手
- 所有东西都放在仓库里的 `footage/`（`.gitignore` 里有 `/footage/`），**绝不能提交、推送**（主人原话「千万不能传到 Git 上」）。入口 `footage/README.md`（含录制规格和 OBS 的坑），清单 `catalog.md`，待定事项 `production.md`

**How to apply:** 主人说回来做演示录制或交接时，读这里和 `footage/README.md`、`production.md`，照着推进，不再从头讨论。进展写进 footage，不写进 git 跟踪的文件。宣传片的方向见 [[feedback-promo-video]]
