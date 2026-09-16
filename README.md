# battery-macos-27 · battctl

[English](docs/README.en.md) · [下载 / Releases](https://github.com/geoochi/battery-macos-27/releases) · [技术说明](docs/macos-27-battery.md)

设置 **20–99% 的整数目标**（例如50或70），让 macOS 在接通电源时执行充电上限。
当前只有50%完成硬件验收；其它目标可配置，但实际效果仍需验证。
原生 Objective-C/C CLI，无第三方运行时，无需常驻限充进程。

> **实验性预发布，支持范围有限。** 目前只在 **M1 Pro、MacBookPro18,1、macOS 27.0 build 26A428** 上验证50%完整流程。
> 其他机型/构建会拒绝新的目标配置写入；没有强制绕过选项。
> 使用系统私有接口和非公开偏好，系统更新可能改变行为。不是Apple官方支持的50%功能。

## 已验证什么

| 场景 | 结果 |
| --- | --- |
| 正常重启后加载50%上限 | 通过 |
| 插电、开盖自然放电至50% | 通过 |
| 达到50%后电池净电流归零 | 通过 |
| 开盖、合盖运行、重新开盖保持 | 通过 |
| 开盖睡眠后唤醒保持 | 通过 |
| 合盖睡眠后唤醒保持 | 通过 |
| 多日/过夜保持、补电阈值、系统校准充电 | 尚未完成验证 |

结果来自一台设备，不能外推到所有macOS 27电脑。[脱敏验证摘要](docs/validation.md)。
“保持”允许电量估计和实际电流的小幅波动；没有外部电源时无法锁住电量。

## 下载与安装

### 方式一：从源码构建（推荐）

需要Apple Command Line Tools；如尚未安装，先运行 `xcode-select --install` 并完成安装。

```sh
git clone https://github.com/geoochi/battery-macos-27.git
cd battery-macos-27
make test
./build/battctl --version
sudo ./scripts/install.sh
```

### 方式二：下载预编译版本

从 [Releases](https://github.com/geoochi/battery-macos-27/releases) 下载
`battctl-v0.2.0-macos-arm64.tar.gz` 和 `SHA256SUMS`，放在同一目录：

```sh
shasum -a 256 -c SHA256SUMS
tar -xzf battctl-v0.2.0-macos-arm64.tar.gz
cd battctl-v0.2.0-macos-arm64
./build/battctl --version
sudo ./scripts/install.sh
```

二进制仅供Apple silicon/macOS 27使用，未使用Developer ID签名或Apple公证。
若macOS阻止运行，优先使用源码构建；项目不要求关闭Gatekeeper或SIP。

两种安装方式都把程序放入 `/Library/Application Support/battctl/battctl`，并链接到
`/usr/local/bin/battctl`。若PATH不含此目录，使用 `/usr/local/bin/battctl`。
安装本身不会设置电池上限，也不会安装限充守护程序。升级时重新运行安装脚本。

## 首次启用（以已实测的50%为例）

1. 停用其它电池控制软件，在系统设置中启用原生“充电上限”，先选80%；结束“充满电”等临时覆盖。
2. 接好充电线，检查型号、系统构建和当前值：

   ```sh
   sysctl -n hw.model
   sw_vers -buildVersion
   battctl native-limit
   ```

3. 保存实验配置：

   ```sh
   sudo battctl hold 50
   ```

   程序备份原上限、保存50，并提示是否需要重启。已生效时不会重复写入。
4. 保存工作后，**手动正常重启Mac**。程序不会自动重启，也不会强行重启受保护的系统服务。
5. 重启后运行：

   ```sh
   battctl verify
   battctl monitor
   ```

`policy=active` 表示PowerUI与实际系统限充策略都符合检查目标，不只是偏好文件写入成功。
正常使用电脑即可自然放电；到目标后观察电池电流与电量。无需压力测试耗电。
`monitor` 每30秒打印一次，Ctrl-C退出不影响限充。

## 修改目标，例如70%

```sh
sudo battctl hold 70
# 保存工作，按提示手动正常重启，然后：
battctl verify          # 默认读取本程序保存的目标70
battctl verify 70        # 显式检查70，避免将其它有效上限误认为目标已生效
battctl monitor         # 持续跟随本程序保存的目标
```

支持20–99的整数；`hold 100` 会拒绝，允许充满请用 `native-limit 100`。
`hold`始终使用sudo，以便连同保存的系统偏好一起核对，避免漏掉待重启配置。
目标变化通常需要正常重启；若保存值、请求值、实际策略均相同，则无需写入或重启。
**已保存70、实际仍是50时，verify会返回未生效和非零退出码。**
修改目标保留首次原上限备份；重启前也可再次修改或用 `sudo battctl hold 50` 取消70请求。
70及其他非50目标尚未完成硬件验收，不保证升高目标后立即充电到精确目标值。

请求的目标保存在 `/Library/Preferences/com.geoochi.battctl.plist`，由root写入、普通用户只读。
旧版本未创建此配置时，默认检查50%，不会自动把系统当前值当成你的期望值。
`restore`成功后清除此请求配置；可用 `native-limit` 查看恢复后的系统值。
已有可选记录器升级后，重新运行 `./scripts/record-test.sh start` 更新它使用的程序。

## 常用命令

| 命令 | 用途 |
| --- | --- |
| `battctl status [--json]` | 当前电量、电流、功率、适配器和盖子状态 |
| `battctl watch [--json]` | 每5秒打印电池状态 |
| `battctl verify [TARGET] [--json]` | 检查保存的目标或显式目标；不可验证时返回非零 |
| `battctl monitor [TARGET] [--json]` | 每30秒检查目标策略和电池状态 |
| `battctl doctor` | 诊断；目标原生策略有效时无需SMC控制权限 |
| `battctl native-limit` | 查看PowerUI选择值、启用状态和可设置值 |
| `battctl native-limit 80` | 设置系统支持值；当前接口提供80/85/90/95/100 |
| `sudo battctl hold TARGET` | 备份并准备20–99%目标配置；未生效时提示手动重启 |
| `sudo battctl restore` | 恢复首次备份的原上限并核验生效情况 |

`native-limit 50` 会被拒绝，低于80的自定义目标使用 `hold TARGET`。`near_target` 只描述单次读数接近目标，
不等于已经证明长期保持。项目中的 `run` / `reset` 是旧SMC实验后端，当前固件不可用，
不属于本版推荐工作流程。

## 恢复与卸载

```sh
sudo battctl restore
# 在下载/克隆的项目目录中：
./scripts/record-test.sh stop    # 如果启用过可选记录器
sudo ./scripts/uninstall.sh
```

原上限备份在 `/Library/Application Support/battctl-reboot-test/previous-limit`，不要手动删除。
卸载时如存在备份，先恢复再删除程序；未曾启用时可直接卸载。
若恢复未通过核验，程序和备份会保留，请根据错误提示正常重启后复查。
也可以在系统设置中选回支持的充电上限以退出实验配置。

## 注意事项

- **持续插电**才可能保持。电源功率不足、断开电源、电量估计变化可能影响读数。
- 系统设置中的“充满电”、修改原生上限、系统更新或其它控制程序可能覆盖目标上限；之后运行 `verify`；本程序保存的期望目标不会随外部改动自动改变。
- 不修改SIP、系统二进制或睡眠设置；程序不要求屏幕常亮。
- 原生策略可能在合盖时继续放电到目标，不承诺“只在开盖时放电”。
- 当前不承诺固定48%–50%补电区间或永远不发生系统校准充电；实际补电阈值尚待验证。
- 首次测试请自行观察到达目标及睡眠唤醒后的状态，不能仅凭 `hold` 返回成功验收。

## 可选：本地记录

```sh
./scripts/record-test.sh start
./scripts/record-test.sh status
./scripts/record-test.sh stop
```

用户LaunchAgent每分钟按本程序保存的目标只读采样一次，登录后加载。深度睡眠暂停，后台唤醒时可能采样；
它不控制电池、不防止睡眠。日志在 `~/Library/Logs/battctl/`，停止记录不影响限充。
记录会持续追加，测试结束后可停止并自行清理。程序不联网、不上传遥测。
分享日志前请移除时间、个人路径、进程信息等隐私；不要上传完整IORegistry或系统日志。

## 开发与许可

```sh
make test
```

测试覆盖电流解码、有效策略判断、原生接口失败/回滚与旧放电策略；不写真实电池设置。
CI编译通过不代表对应runner硬件已支持50%。

[贡献说明](CONTRIBUTING.md) · [第三方来源](THIRD_PARTY.md) · [GPL-2.0许可](LICENSE)
