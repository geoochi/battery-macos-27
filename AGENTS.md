# battctl：AI 工作说明

本文替代根目录 README，供后续 AI 维护项目时读取。使用标准文件名
`AGENTS.md`，不要另建不同大小写的重复文件。

## 完成修改后的固定流程

用户已要求：每次完成一批项目修改后，自动检查、commit 并 push，
无需为这些常规操作重复征求确认。

1. 先检查工作区、当前分支与远端差异，保留用户已有改动。
2. 完成与改动相关的验证。代码改动运行 `make test`；纯文档改动检查
   链接、引用与 `git diff --check`，不为纯文档反复运行代码测试。
3. 更新必要的技术说明、验证记录和本文件，区分已完成与待验证事项。
4. 检查提交范围和隐私，只暂存这次工作明确涉及的文件。
5. 每个由 AI 创建的提交必须包含以下 Git trailer：

   ```text
   Co-authored-by: Codex <codex@openai.com>
   ```

6. 使用仓库已配置的作者身份，保持隐私邮箱；提交说明描述最终变更及验证。
7. Push 到当前工作分支对应的远端。当前主分支是 `main`，远端为
   `origin`（`github-geoochi:geoochi/battery-macos-27`）。不要强推、覆盖历史，
   或夹带与本次任务无关的更改。
8. 确认 push 成功，报告 commit 和未完成的硬件验证。遇到认证、冲突或
   检查失败，保留成果并说明阻碍，不把本地 commit 说成已推送。

常规 commit/push 不等于发布 Release：不要因此自动创建 tag、发布二进制、
改写既有 Release，或自动重启用户电脑。

## 产品范围与不可回退的设计决策

- 本项目是 macOS 原生限充 CLI。用户只输入一个目标电量。
- 流程：保存目标 → 必要时用户正常重启 → macOS 自行充放电到目标附近并保持。
- 不重新引入区间循环、适配器反复切换、SMC 控制、后台充电控制器或看护进程。
- 不关闭 SIP、不注入或修改系统进程，不用压力测试主动耗电。
- 保存成功不等于策略生效。重启前旧上限仍可能允许继续充电。
- 不承诺永久精确保持某个百分比。系统校准、供电条件与临时覆盖会影响行为。

## 源码与接口

- `Sources/main.m`：参数、遥测、冲突检测、命令入口。
- `Sources/native.m`：PowerUI 私有接口的查询、原生设置与失败恢复。
- `Sources/persistent.m`：目标保存、兼容性检查、备份、回滚与有效策略核验。
- `Sources/telemetry.h`：只读取必要电池字段，注意无符号形式的负电流。
- `Sources/version.h`：CLI 版本；同步更新 `tests/cli.sh` 的版本断言。
- `tests/`：使用模拟对象测试写入；测试不得改变本机充电设置。

命令契约：

| 命令 | 行为 |
| --- | --- |
| `sudo battctl hold TARGET` | 保存 20–99 的整数目标，核验并提示是否重启 |
| `battctl verify [TARGET] [--json]` | 默认核验已保存目标，不一致时返回非零 |
| `battctl status [--json]` | 读取电量、电流、接电及盖子状态 |
| `battctl doctor [--json]` | 查询原生选择值、有效策略与冲突 |
| `battctl monitor [TARGET] [--json]` | 每 30 秒只读核验，退出不影响限充 |
| `sudo battctl restore` | 恢复首次备份值并核验，失败时保留恢复资料 |

`hold-native` / `verify-native` 已更名；`native-limit`、`watch`、`run`、
`reset` 和 adapter 命令已删除。100% 目前使用系统设置，不接受 `hold 100`。
当前 `hold` 对原生档位也走偏好保存路径，尚未实现按档位即时设置。

## 状态与兼容性规则

- PowerUI 即时接口在既有实测中拒绝 50%；启动读取私有偏好的路径可加载 50%。
- 原生报告的档位为 80/85/90/95/100。不能从 CLI 接受参数推断任意目标已验证。
- v0.2.2 保留 `MacBookPro18,1` 机型范围，取消精确构建号白名单。
- 写入前要求原生接口可读、功能开启、偏好合法、当前选择值与实际手动策略一致，
  且原始恢复值仍受接口支持。异常时拒绝修改，不能为通过检查而伪造成功。
- 检查当前有效值，不能把“当前 80%、待设置 50%”本身误判为不兼容。
- 后续系统更新不能仅因构建号变化而被拒绝；运行时检查也不代表该版本硬件验收完成。
- `policy_active` 要求原生选择值与全部未终止手动限充条目一致。
- `near_target` 仅表示一次读数接近目标，不能证明长期保持或深睡眠期间行为。

系统偏好：root 的 `com.apple.smartcharging.topoffprotection` 中
`mclLimitValue`。目标元数据：`/Library/Preferences/com.geoochi.battctl.plist`。
原始备份：`/Library/Application Support/battctl-reboot-test/previous-limit`。
保留历史路径；原始备份不能被后续目标覆盖。失败应恢复本次修改前的值。
缺少目标元数据的旧安装默认核验 50%，不能把当前系统值自动当作用户意图。
用户在系统设置选新上限会覆盖实际策略；此时 `verify` 非零不等于进程崩溃。

## 验证记录与下一步

- `26A428`：50% 完成开盖、合盖与睡眠唤醒验证；70% 有充到目标及保持记录，
  未完成同等级睡眠验证。详见 `docs/validation.md`。
- `26A434` / macOS 27.0.1：v0.2.2 已通过 `make test`，在本机安装并执行
  `hold 50`；保存值读回为 50，原始 80% 备份保留。
- **待验证**：上述写入后，运行中的策略仍为 80%。尚无重启加载 50%、
  放电至目标和睡眠保持的新构建号验收。用户重启后先运行 `battctl verify 50`，
  然后依据实际结果更新记录，不能把旧构建号结论套用过来。
- v0.2.2 尚未发布 GitHub Release；已发布二进制为 v0.2.1，仍有旧构建号限制。

## 构建、安装与本机记录器

`make test` 构建并运行全部测试及 shell 语法检查。
`sudo ./scripts/install.sh` 安装至 `/Library/Application Support/battctl/battctl`，
入口为 `/usr/local/bin/battctl`；安装本身不改变目标，不创建充电控制守护进程。
卸载脚本先恢复原上限，恢复失败时保留程序与备份。

`scripts/record-test.sh start|stop|status` 管理可选的只读 LaunchAgent
`com.geoochi.battctl.monitor`。登录执行一次、清醒时每分钟运行 `verify --json`。
它与限充无关，目标不一致时会以 1 退出；不要误当成崩溃或必需的控制服务。
停止记录保留日志且不改充电设置。不要未经任务需要重新启用它。

## 隐私与补充资料

- `research/`、构建产物、原始日志、时间序列、系统转储、个人路径和设备标识
  不提交、不上传。继续使用 `.gitignore`，禁止强制加入研究目录。
- 公开验证记录只保留判断兼容性必要的脱敏信息，见 `docs/validation.md`。
- 技术机制与恢复语义见 `docs/macos-27-battery.md`；历史变更见 `CHANGELOG.md`。
- `docs/README.en.md` 保留已有英文操作参考；根目录不再维护面向用户的 README。
- `scripts/package-release.sh` 仅打包已提交的公开文件；不覆盖已有版本的 tag/产物。
- GPL-2.0；保留 `LICENSE` 和 `THIRD_PARTY.md`，不复制第三方私有实现。
