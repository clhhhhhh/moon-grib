# MoonGRIB

MoonGRIB 是用 MoonBit 编写的 GRIB2 读取库和命令行工具。它按变量、层次与时次查看文件内容，并从规则经纬网格中提取指定区域的格点。结果包含行列号、坐标和数值，缺测值保留为空。

## 快速开始

需要 MoonBit 工具链。JavaScript 命令行入口需要 Node.js。示例里的字段编号、行号和列号均从 0 开始。

```sh
moon test --deny-warn
moon test --target js --deny-warn
moon run cmd/main --target js -- inventory sample.grib2
moon run cmd/main --target js -- verify sample.grib2
moon run cmd/main --target js -- point sample.grib2 0 25 60
moon run cmd/main --target js -- window sample.grib2 0 119.5 29.7 120.6 30.7
moon run cmd/main --target js -- stats sample.grib2 0 119.5 29.7 120.6 30.7
```

窗口参数依次为西、南、东、北，端点包含在内。西界大于东界表示窗口跨越日期变更线。输出经度规范化到 `[-180, 180)`。`inventory` 和 `verify` 输出 JSON Lines，`point` 和 `stats` 输出 JSON，`window` 输出 CSV。

库入口为 `open_archive`。通过 `Archive::select` 按变量代码、层次、时次等条件筛选，通过 `Archive::decode` 打开格点字段。随后用 `DecodedField::at` 查询单点，用 `window` 收集区域数据，或用 `visit_window` 逐格处理。

## 格式范围

- GRIB 版次 2，支持顺序拼接消息、同一消息包含多个字段、可选本地段和位图引用。
- 规则经纬网格模板 3.0，支持正反方向、行列优先、交替扫描和缺测位图。
- 简单打包 5.0、通用组拆分的复杂打包 5.2、带一阶或二阶空间差分的复杂打包 5.3。位宽、差分描述符和预处理规模受实现限制。
- 读取参考时间、来源中心、变量代码和常见产品模板的预报步长、固定面。未知模板通过代码编号保留在清单中。

窗口先用二分定位相关经纬度范围。简单打包直接定位所需值。复杂打包通过分组偏移定位，空间差分需要一次预处理，随后从检查点恢复局部值。库接收内存中的文件字节，CLI 加载整个本地文件，默认接受不超过 512 MiB 的普通文件。上述优化减少解码工作量。

## 独立验证

安装 Python 的 `eccodes` 和 `numpy` 后运行：

```sh
moon build --target js
python examples/verify_eccodes.py
```

脚本用 ECMWF ecCodes 生成样本，并独立核对窗口的行列号、坐标、数值和缺测标记。已运行的四组结果见 [验证数据](examples/verification.json)。脚本中的耗时是单次 CLI 墙钟时间，包含 Node.js 启动与文件读取。

格式说明见 [ECMWF GRIB2 模板](https://codes.ecmwf.int/grib/) 与 [ecCodes 文档](https://sites.ecmwf.int/docs/eccodes/)。许可证为 Apache-2.0。
