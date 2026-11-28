# MoonGRIB

MoonGRIB 是用 MoonBit 编写的 GRIB2 库和命令行工具。它按变量、层次与时次查看文件内容，并从气象网格中提取指定区域，输出坐标、数值和缺测标记。

## 快速开始

需要 MoonBit 工具链。JavaScript 命令行入口需要 Node.js。字段编号、行号和列号从 0 开始。

```sh
moon test --deny-warn
moon test --target js --deny-warn
moon run cmd/main --target js -- range-inventory sample.grib2
moon run cmd/main --target js -- range-window sample.grib2 0 119.5 29.7 120.6 30.7
moon run cmd/main --target js -- estimate sample.grib2 0 30.2 120.1 bilinear
moon run cmd/main --target js -- raster sample.grib2 0 119.5 29.7 120.6 30.7 asc
```

窗口参数依次为西、南、东、北，包含端点。西界大于东界表示跨日期变更线。经度输出范围为 `[-180, 180)`。窗口输出 CSV，`range-window` 另在标准错误流输出读取次数、字节数和解码数。栅格可导出 ASCII Grid 或 PGM，ASCII Grid 需要等间距的方形单元。

## 功能和格式范围

最终交付目标是完整符合 WMO-No. 306 FM 92 GRIB Edition 2。下表记录当前实现；模板覆盖、补齐顺序及验收证据见 [GRIB2 合规计划](GRIB2-CONFORMANCE.md)。

| 能力 | 入口或范围 |
| --- | --- |
| 文件和消息 | `open_archive` 从内存打开，`open_indexed` 按需读取。支持连续消息、消息内多字段、可选本地节和先前位图引用 |
| 网格 | 规则经纬网格 3.0、规则高斯网格 3.40，支持正反方向、行列优先、交替扫描和缺测位图。缩减网格和交错网格超出当前范围 |
| 内存读取 | 简单打包 5.0、通用组拆分 5.2、一阶及二阶空间差分 5.3、单精度或双精度 IEEE 5.4，以及带代表值的游程打包 5.200 |
| 读取文件范围 | `range-window` 按需读取 5.0 和 5.4 的偏移区间，`range-inventory` 仅读取消息结构和元数据 |
| 查询和比较 | `point`、`stats`、`estimate`、`profile`、`compare`。支持最近邻、双线性插值和缺测策略 |
| 时间轴 | 支持瞬时产品的有效时刻、点位和区域时间序列，`interval` 展示模板 4.8 的区间与统计描述 |
| 导出和编码 | 窗口 CSV、JSON Lines、ASCII Grid、PGM。MoonBit API 可编码规则经纬网格的简单整数打包、IEEE64 或 8 位代表值游程 |

库入口 `open_indexed` 接受 `ByteSource` 回调，可以从本地文件或其他支持定位偏移的数据源读取。范围查询合并相邻字节段，位图存在时先构建缺测值索引。空间差分采用预处理与检查点恢复，适用于内存读取路径。CLI 支持的具体命令可直接运行 `moon run cmd/main --target js` 查看。

## 验证与性能

Python 对照脚本使用 ECMWF ecCodes 和 NumPy。

```sh
moon build --target js
python examples/verify_eccodes.py
python examples/verify_eccodes.py --same-field
python examples/verify_level_runs.py
python -B examples/benchmark_window.py
```

[逐点验证结果](examples/verification.json)覆盖四种数据表示和两种网格。 [窗口基准](examples/benchmark_results.json)使用一个由 16 条消息组成的 11,522,864 字节文件。每次对照检查三种命令的 CSV 输出完全一致，墙钟时间采用五次独立 CLI 启动的中位数。

| 窗口 | 格点数 | 整场解码后裁剪 | 内存内窗口解码 | 按范围读取 | 范围读取字节 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 小窗口 | 121 | 191.16 ms | 113.66 ms | 112.43 ms | 1152 |
| 大窗口 | 40401 | 238.30 ms | 182.57 ms | 202.60 ms | 81712 |

范围读取字节包含从文件读取的消息索引、字段元数据和负载，计时包含 Node.js 启动和 CSV 序列化。大窗口在本机上的范围读取耗时高于内存内窗口路径。

格式说明见 [ECMWF GRIB2 模板](https://codes.ecmwf.int/grib/) 与 [ecCodes 文档](https://sites.ecmwf.int/docs/eccodes/)。许可证为 Apache-2.0。

## Reproducible forecast example

```sh
moon build --target js
python -B examples/demo.py ./forecast-demo
python -B examples/verify_encoded.py
```

The demo generates two GRIB2 fields for the same forecast, lists the fields,
extracts a 3-by-2 region and writes a grayscale PGM preview. It checks the
inventory, the missing cell and the image dimensions. The output directory
also includes a CSV file and the input GRIB2. The separate ecCodes
interoperability script checks both encoded messages, including the date
rollover, grid coordinates, packed values and bitmap.
