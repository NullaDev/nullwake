# NULLWAKE / 零界苏醒

基于 `design.md` 实现的 Godot 2D 深空终端经营游戏。工程目标版本为 Godot 4.6，主场景为 `scenes/main.tscn`。

## 运行

用 Godot 打开 `project.godot` 后运行项目。首次启动会进入固定教学谜题：先输入 `100`，再根据反馈输入 `001`。工程包含名为 `Web` 的导出预设，可在安装 Godot Web 导出模板后直接生成浏览器版本。

## 已实现系统

- 支持重复数字的精准/错位匹配算法，以及标准、无重复、镜像协议
- 永久、一次性、有限次数和受保护唯一节点
- 购买、库存、接入、启动锁定、失败/放弃消耗与折价回收
- 多条独立解译通道、暂停和确定性算力调度
- 序列探针、逻辑筛选器与熵减核心三档 AI
- 终端兼容升级、算力扩容、科技研究与风险熔断
- 配置驱动的奖励、战利品掉落、重复品分解和系列收藏
- 剧情记忆、统计、自动存档及存档码导入/导出
- 无贴图的 DOS/科幻终端式响应界面

平衡数据集中在 `config/game_data.json`。谜题、AI、状态、存档和界面逻辑分别位于 `scripts/` 下。

## 验证

```powershell
godot --headless --path . --script tests/test_runner.gd
godot --headless --path . --script tests/integration_runner.gd
```
