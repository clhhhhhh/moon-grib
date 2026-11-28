# MoonGRIB 项目申报书

## 基本信息

- 项目名称：MoonGRIB，基于 MoonBit 的 GRIB2 格点数据读取与窗口查询库
- 参赛者：clhhhhhh
- GitHub 仓库：[clhhhhhh/moon-grib](https://github.com/clhhhhhh/moon-grib)
- Mooncakes 包：[clhhhhhh/moon-grib@0.1.1](https://mooncakes.io/docs/clhhhhhh/moon-grib)
- 项目方向：气象与地理数据处理，以 MoonBit 独立实现，参考 WMO GRIB2 标准

## 项目简介

气象应用经常只需要预报文件中的一个变量、一个时次和一小块区域。MoonGRIB 先为 GRIB2 消息建立索引，再把经纬度窗口换算成格点区间。例如，区域天气看板可以提取指定时次的近地面温度，直接获得经纬度、数值和缺测标记。

## 当前实现

- 按变量、层次和参考时间筛选字段，支持规则经纬网格、规则高斯网格和缺测位图。
- 在内存中解码简单打包、复杂打包、空间差分、IEEE 浮点和代表值游程打包。简单打包与 IEEE 打包还支持定位读取所需字节。
- 通过扫描顺序和打包偏移合并读取区间，支持跨日期变更线的窗口。为整字节对齐的常见行优先布局提供连续行段读取。
- 提供点位插值、区域统计、时间序列与重采样，支持 CSV 和栅格导出，以及规则经纬网格的简单打包、IEEE64 和 8 位代表值游程编码。

## 最终目标与验收

最终交付目标是完整符合 WMO-No. 306 FM 92 GRIB Edition 2，覆盖选定 WMO 主表版本的全部有效标准模板、代码表和组合约束。上面的已实现范围是首个里程碑。接下来按消息与位图规则、网格和产品定义、数据表示与编解码的顺序补齐。
预期交付 MoonBit 编解码库、窗口查询 CLI、Mooncakes 包、逐模板合规矩阵和可复现测试。验收逐项检查合法输入的解码和编码、异常输入诊断，以及与 ecCodes 的双向互操作。缺少对照实现的模板用按规范独立核验的向量验证。[合规计划](https://github.com/clhhhhhh/moon-grib/blob/main/GRIB2-CONFORMANCE.md)
复审案例使用同一份 2 米气温场，分别生成简单打包（5.0）、复杂打包（5.2）、空间差分（5.3）和 IEEE（5.4）文件。四种输入各核对 576 个格点（含 83 个缺测），MoonGRIB 的 CSV 逐字节一致，每个格点的坐标、数值和缺测状态均与 ecCodes 一致。案例已接入 CI。[复现脚本](https://github.com/clhhhhhh/moon-grib/blob/main/examples/verify_eccodes.py)

## 参考规范与许可

项目按 Apache-2.0 许可发布。[WMO GRIB2 模板参考](https://codes.ecmwf.int/grib/) · [ECMWF ecCodes 文档](https://sites.ecmwf.int/docs/eccodes/)
