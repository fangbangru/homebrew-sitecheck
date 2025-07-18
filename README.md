# sitecheck

带详细解释的站点性能检测脚本（Shell/Bash）

**sitecheck** 是一个轻量级命令行工具，用于快速检测目标站点的网络连通性、HTTP 状态码、响应时间细分及 HTTPS 握手延迟，并在每个指标下提供详细的文字说明。

## 功能特点

* **Ping 测试**：检测丢包率及往返时延（RTT），并根据平均延迟给出性能评估。
* **HTTP 状态码**：输出 2xx/3xx/4xx/5xx 分类说明。
* **curl 响应统计**：DNS 解析、TCP+TLS 握手、首字节时间、总耗时，一次调用覆盖全流程。
* **HTTPS 延迟**（httping，可选）：跳过证书验证测量 HTTPS 握手及首字节延迟。
* **站点信息探测**：重定向、IP、主机信息、服务器、CMS、SSL 证书等详细信息。
* **批量检测**：支持从文件读取多个 URL 进行批量检测。
* **多种输出格式**：plain、JSON、CSV 格式输出。
* **配置文件支持**：支持 ~/.sitecheck 配置文件自定义默认参数。
* **参数验证**：严格的参数验证和错误处理。
* **命令行选项**：

  * `-h, --help`：显示帮助信息
  * `-v, --version`：显示当前版本号
  * `--no-httping`：跳过 HTTPS 延迟测试（当不安装 httping 或不想执行时）
  * `-c, --count <N>`：ping/httping 请求次数（默认 3，范围 1-100）
  * `-t, --timeout <SEC>`：curl 请求超时时间（秒，默认 10，范围 1-300）
  * `--warn-loss <PERCENT>`：丢包率告警阈值（%，默认 100）
  * `--warn-latency <MS>`：平均延迟告警阈值（ms，默认 1000）
  * `--format <plain|json|csv>`：输出格式（plain 默认）
  * `--config`：生成示例配置文件到 ~/.sitecheck
  * `--quiet`：静默模式，只输出结果不显示进度
  * `--no-color`：禁用彩色输出

## 安装方式

### 1. Homebrew（macOS）

```bash
brew tap fangbangru/sitecheck
brew install sitecheck
```

> 安装完成后，`sitecheck` 命令会自动添加到你的 `$PATH`，直接使用即可。

### 2. 手动克隆并运行

```bash
git clone https://github.com/fangbangru/check-site.git
cd check-site
git checkout v0.1.3  
chmod +x check_site.sh
./check_site.sh <URL>
```

### 3. Windows 环境

* **WSL/Ubuntu**：同 Linux 环境执行上述克隆步骤。
* **Git Bash**：同上。需确保 `curl`、`bc`、`ping`、`awk` 安装可用。
* **PowerShell 原生（示例）**：参考 `sitecheck.ps1`；命令可适配 `Test-Connection` 和 `Invoke-WebRequest`。

## 使用示例

```bash
# 基础检测
sitecheck example.com

# 查看帮助
sitecheck --help

# 查看版本
sitecheck --version

# 跳过 HTTPS 延迟测试
sitecheck --no-httping example.com

# 生成配置文件
sitecheck --config

# 使用 JSON 格式输出
sitecheck --format json google.com

# 设置告警阈值
sitecheck --warn-loss 10 --warn-latency 200 example.com

# 批量检测多个站点
echo -e "google.com\ngithub.com\nstackoverflow.com" > sites.txt
sitecheck batch sites.txt

# 静默模式 CSV 输出
sitecheck --quiet --format csv --no-httping example.com

# 站点信息探测
sitecheck detection example.com
```

执行后，会依次输出四大模块：

1. **ping 测试**（丢包率 & RTT）
2. **HTTP 状态码**（2xx/3xx/4xx/5xx 解释）
3. **响应时间统计**（DNS / Connect / StartTransfer / Total）
4. **httping 延迟**（HTTPS 握手及首字节延迟说明）

每段下方都有中文提示说明当前数值的意义与性能评估。

## 更新与发布

1. 在主项目仓库打新标签并发布 Release（如 `v0.1.3`）。
2. 在 Homebrew Tap 仓库更新 `sitecheck.rb` 的 `url` 和 `sha256`，提交并推送。
3. 用户执行 `brew update && brew upgrade sitecheck` 获取最新版本。

## 贡献指南

1. Fork 本仓库并新建分支：`git checkout -b feat-my-feature`
2. 提交改动并推 PR：`git commit -am 'feat: add new feature' && git push origin feat-my-feature`
3. 等待代码审查与合并。

## 许可证

本项目遵循 MIT 许可证。详情请参见 [LICENSE](LICENSE)。
