# 基线（第 0 轮）

基点 commit：`0b9798d6b74da3eca2999dba49161d42fe82103a`  
分支：`mem-opt-50`  
worktree：`/Users/jerry/Desktop/开发/Deck/Deck-memopt-50`  
对比用的原始中位数文件：`tmp/memopt/baseline-median.json`

## 环境

- macOS，Release 构建（`-O`），关闭 code coverage（否则 Release 保护脚本会因 `__LLVM_COV` 失败）
- 产物：`.memopt-dd/Build/Products/Release/Deck.app`
- 隔离：`tmp/memopt/active.json` 把数据库指到 worktree 内的临时目录，不写用户偏好，不打开用户的 `~/Library/Application Support/Deck`
- 夹具：1500 条确定性文本（含约 40 条 48KB 文本、英文/中文语义种子），嵌入全部就绪后 `VACUUM`。逻辑持久化 SHA-256：`36301bff10fef989ca1c30d47dfdfeae5f259bd274c4788534a400357b9b3d4e`
- 每个场景 3 个新进程，取中位数。延迟是去掉 1 次预热后的热路径中位数（加载场景无预热，3 次全计）
- 内存：`task_vm_info.phys_footprint`（物理足迹）与 `mach_task_basic_info.resident_size`（RSS）。SQLite `sqlite3_status64(MEMORY_USED)` 在此构建上恒为 0，不作为判据
- 正确性：每个场景把结果顺序和字段（id、uniqueId、timestamp、类型、应用名、标题、contentLength、searchText SHA-256）哈希。三次运行哈希一致

## 复现

```bash
cd /Users/jerry/Desktop/开发/Deck/Deck-memopt-50
# 首次会编译 Release 并生成 tmp/memopt/fixture
tmp/memopt/run_bench.sh
# 已有夹具、只重测：
tmp/memopt/run_bench.sh test-only
```

夹具大约 26MB，不入库。删除 `tmp/memopt/fixture/marker.json` 会重建。

## 中位数

| 场景 | 物理足迹之后 | 峰值物理足迹 | RSS 之后 | RSS 峰值 | 延迟中位数 | 条数 | 三次物理足迹极差 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| load | 18.39 MiB | 18.39 MiB | 81.97 MiB | 81.97 MiB | 253.48 ms | 624 | 0.34 MiB |
| exact | 18.44 MiB | 18.44 MiB | 87.42 MiB | 87.42 MiB | 4.95 ms | 30 | 0.33 MiB |
| fuzzy | 30.39 MiB | 30.39 MiB | 99.73 MiB | 99.73 MiB | 64.96 ms | 1447 | 0.77 MiB |
| mixed | 30.58 MiB | 30.58 MiB | 100.17 MiB | 100.17 MiB | 0.48 ms | 30 | 0.75 MiB |
| mixed_fuzzy | 30.58 MiB | 30.59 MiB | 100.17 MiB | 100.17 MiB | 78.99 ms | 1447 | 0.77 MiB |
| regex | 30.74 MiB | 30.75 MiB | 100.38 MiB | 100.38 MiB | 14.73 ms | 30 | 0.75 MiB |
| semantic_en | 32.06 MiB | 32.11 MiB | 124.14 MiB | 124.16 MiB | 18.40 ms | 800 | 4.67 MiB |
| semantic_zh | 32.17 MiB | 32.22 MiB | 109.72 MiB | 109.73 MiB | 2.99 ms | 25 | 4.67 MiB |
| extreme | 32.36 MiB | 32.36 MiB | 126.81 MiB | 126.81 MiB | 114.85 ms | 1447 | 4.80 MiB |
| maintain | 35.56 MiB | 90.86 MiB | 142.66 MiB | 177.67 MiB | 131.91 ms | 0 | 4.84 MiB |

语义与维护场景的极差约 4.7 MiB，主要来自第一次进程加载 NLEmbedding。中位数取三次的中间值。

## 保留判据

相对**当前已保留基线**（一开始就是上表）：

- 正确性哈希与持久化哈希必须相同
- 延迟：只有同时超过 +3% 且超过该场景三次极差，才算回退
- 内存：目标场景的物理足迹（之后或峰值）中位数下降幅度要大于该场景基线极差，并且不小于基线的 1%；三次新运行都低于旧中位数
- 其它场景的物理足迹中位数不得上升超过自己的基线极差
