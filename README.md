# battery-macos-27 · battctl v0.2.1

[English](docs/README.en.md) · [下载](https://github.com/geoochi/battery-macos-27/releases) · [技术说明](docs/macos-27-battery.md)

**设置目标电量 → 按提示正常重启 → 由 macOS 自行充电或放电到目标附近并保持。**

只提供原生限充功能，不安装电池控制守护进程，不反复切换适配器、不主动进行区间充放电。
接着电源时，达到目标后由系统管理适配器供电与充电；电量仍可能有正常的小幅波动。

> 实验性预发布。配置范围20–99%，当前写入仅支持 **MacBookPro18,1 / macOS 27.0 build 26A428**。
> 原生50%已完成开盖、合盖及睡眠唤醒验收；70%有充电到目标及保持的实测记录，其他值仍需逐一验证。
> 使用系统私有接口与偏好，系统更新可能改变行为。不要关闭SIP或绕过系统保护。

## 使用

```sh
sudo battctl hold 50
# 如果提示尚未生效：保存工作，手动正常重启 Mac
battctl verify
```

`hold` 会保留原上限备份、保存请求的目标，并检查实际生效策略。
**保存成功不代表立即生效：重启前仍执行旧上限，可能继续充电到旧目标。** 程序不会自动重启。

接着电源正常使用即可；不需要让 CLI 持续运行，也不需要用压力测试耗电。
更改目标再次执行 `sudo battctl hold 70` 并按提示重启；若保存值、请求值和实际策略已一致，无需重复重启。
日常合盖、睡眠与唤醒无需重新设置。拔掉电源后，电池会正常消耗。

## 命令

| 命令 | 用途 |
| --- | --- |
| `sudo battctl hold TARGET` | 保存20–99的整数目标，检查是否需要重启 |
| `battctl status [--json]` | 查看电量、电流、功率、接电与盖子状态 |
| `battctl verify [TARGET] [--json]` | 核验原生策略；默认读取已保存目标，未核验通过时返回非零 |
| `battctl monitor [TARGET] [--json]` | 每30秒重复核验；Ctrl-C退出不影响原生策略 |
| `battctl doctor [--json]` | 查看原生选择值、有效策略、支持值及控制程序冲突 |
| `sudo battctl restore` | 恢复首次备份的原上限并核验；失败时保留备份供重试 |
| `battctl --help` / `battctl --version` | 帮助 / 版本 |

`policy=active` 表示原生选择值与有效手动限充策略符合目标。
`near_target` 只表示一次读数接近目标，不能证明长时间保持。
临时需要充满电，请使用 macOS「电池」设置；本程序不提供第二套充满或充放电控制接口。

## 安装

### 从源码构建

需要 Apple Command Line Tools；尚未安装时先运行 `xcode-select --install`。

```sh
git clone https://github.com/geoochi/battery-macos-27.git
cd battery-macos-27
make test
sudo ./scripts/install.sh
battctl --version
```

也可以直接使用 `sudo ./build/battctl hold 50`。

### 下载预编译版本

在 [Releases](https://github.com/geoochi/battery-macos-27/releases) 下载
`battctl-v0.2.1-macos-arm64.tar.gz` 与 `SHA256SUMS`，放在同一目录：

```sh
shasum -a 256 -c SHA256SUMS
tar -xzf battctl-v0.2.1-macos-arm64.tar.gz
cd battctl-v0.2.1-macos-arm64
sudo ./scripts/install.sh
```

安装到 `/Library/Application Support/battctl/battctl`，入口为 `/usr/local/bin/battctl`。
未使用 Developer ID 签名或 Apple 公证；若系统阻止执行，请从源码构建，不要求关闭 Gatekeeper。

### 首次设置与升级

- 第一次使用：停用其他电池控制软件，在系统设置中启用原生「充电上限」，先选择80%，结束临时「充满电」覆盖，再执行 `hold`。
- 从 v0.2.0 升级：重新构建/下载并运行安装脚本，已有目标与原始备份保留。
- 从曾安装的区间控制开发版升级：安装脚本先调用旧版自身的恢复功能，确认控制器及看护进程退出，再移除其服务、配置、可执行文件与日志。恢复适配器后，旧原生上限可能恢复充电；原生目标与备份保持不变。
- 新版统一使用 `hold` / `verify`。旧 `hold-native` / `verify-native` 会提示新名称；`watch`、`native-limit`、`run`、`reset` 和区间控制命令已删除。
- 无论从哪个版本升级，安装后运行 `battctl doctor` 检查状态。安装本身不改原生目标，也不要求为升级而重启。

## 恢复与卸载

```sh
sudo battctl restore
./scripts/record-test.sh stop    # 如果启用过可选记录器
sudo ./scripts/uninstall.sh
```

原始上限备份保存在 `/Library/Application Support/battctl-reboot-test/previous-limit`。
请求目标保存在 `/Library/Preferences/com.geoochi.battctl.plist`。不要手动删除备份。
卸载会先恢复原上限；恢复失败则保留程序与备份，并提示后续操作。
未曾创建目标记录的旧安装默认核验50%，不会把系统当前值自动当作用户目标。

## 可选：只读记录

```sh
./scripts/record-test.sh start
./scripts/record-test.sh status
./scripts/record-test.sh stop
```

登录后的用户任务每分钟采样一次，日志在 `~/Library/Logs/battctl/`。
它不控制电池、不阻止睡眠；停止记录不影响限充。升级后再次运行 `start` 更新记录器。
日志只保存在本机，不联网、不上传遥测。分享前移除时间、个人路径等隐私。

## 验证范围

参见[脱敏硬件验证摘要](docs/validation.md)。系统校准、适配器功率不足、临时充满覆盖、
系统升级以及其他电池工具都可能影响保持效果，不能承诺百分比永久精确不变。
首次设置新目标时应实际观察到达目标、合盖及睡眠唤醒后的表现。

## 开发与许可

```sh
make test
```

测试不改电池设置；覆盖目标解析、配置事务与回滚、原生接口失败处理、有效策略判断和 CLI 参数。
GPL-2.0，参见 [LICENSE](LICENSE) 与 [THIRD_PARTY.md](THIRD_PARTY.md)。
