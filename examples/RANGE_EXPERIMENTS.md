# 范围读取实验

实验在同一台机器用两版 JavaScript CLI 查询同一组 GRIB2 文件，基准版为 Git 提交 `a7e4954`。每个用例交替执行两版，各运行五次并取墙钟时间中位数。耗时包含 Node.js 启动、文件读取、解码及 CSV 输出。脚本逐点核对 ecCodes 给出的格点坐标、数值和缺测，对两版的 CSV 做逐字节比较。

| 用例 | 校验格点 | 基准版 | 行段优化版 |
| --- | ---: | ---: | ---: |
| 小窗口，简单打包 | 20 | 120.42 ms | 111.67 ms |
| 大窗口，简单打包 | 11011 | 141.88 ms | 146.61 ms |
| 跨日期变更线 | 121 | 109.80 ms | 108.57 ms |
| 缺测位图与非整字节打包 | 848 | 115.10 ms | 120.09 ms |
| 列优先扫描 | 848 | 112.96 ms | 115.06 ms |
| 大窗口，IEEE 打包 | 11011 | 144.59 ms | 132.56 ms |

IEEE 大窗口在本次测试中快约 8%。简单打包大窗口耗时增加约 3%。六组用例共核对 23859 个格点，其中 121 个缺测点。行段读取适用于无位图、行优先、无交替扫描且打包值按整字节对齐的字段，其余布局沿用通用读取路径。

原始结果保留各用例的源文件大小、读取次数和字节数。[range_version_results.json](range_version_results.json)

## 复现

```sh
moon build --target js
python -B examples/compare_range_versions.py
python -B examples/compare_range_versions.py --baseline /path/to/baseline/main.js
```

可在 Git 提交 `a7e4954` 的独立检出中运行 `moon build --target js` 生成基准版本。Python 环境需安装 ecCodes 和 NumPy。
