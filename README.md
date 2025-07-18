# sitecheck

[![Version](https://img.shields.io/badge/version-0.2.0-blue.svg)](https://github.com/fangbangru/homebrew-sitecheck/releases)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-orange.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)](https://github.com/fangbangru/homebrew-sitecheck)

A comprehensive site performance monitoring tool with detailed explanations (Shell/Bash)

**sitecheck** is a command-line tool for quickly testing website connectivity, HTTP status codes, response time breakdown, and HTTPS handshake latency.

## Features

* **Ping Testing**: Detect packet loss and round-trip time (RTT) with performance evaluation based on average latency
* **HTTP Status Codes**: Output 2xx/3xx/4xx/5xx classification explanations
* **curl Response Statistics**: DNS resolution, TCP+TLS handshake, time to first byte, total time - all in one call
* **HTTPS Latency** (httping, optional): Skip certificate verification to measure HTTPS handshake and first byte latency
* **Site Information Detection**: Detailed information including redirects, IP, host info, server, CMS, SSL certificates
* **Batch Processing**: Support reading multiple URLs from file for batch testing
* **Multiple Output Formats**: Plain, JSON, CSV format output
* **Configuration File Support**: Support ~/.sitecheck configuration file for custom default parameters
* **Parameter Validation**: Strict parameter validation and error handling
* **Command Line Options**:

  * `-h, --help`: Show help information
  * `-v, --version`: Show current version
  * `--no-httping`: Skip HTTPS latency test (when httping is not installed or not desired)
  * `-c, --count <N>`: Number of ping/httping requests (default 3, range 1-100)
  * `-t, --timeout <SEC>`: curl request timeout in seconds (default 10, range 1-300)
  * `--warn-loss <PERCENT>`: Packet loss warning threshold (%, default 100)
  * `--warn-latency <MS>`: Average latency warning threshold (ms, default 1000)
  * `--format <plain|json|csv>`: Output format (plain default)
  * `--config`: Generate example configuration file to ~/.sitecheck
  * `--quiet`: Quiet mode, only output results without progress
  * `--no-color`: Disable colored output

## Installation

### 1. Homebrew (macOS)

```bash
brew tap fangbangru/sitecheck
brew install sitecheck
```

> After installation, the `sitecheck` command will be automatically added to your `$PATH` for direct use.

### 2. Manual Clone and Run

```bash
git clone https://github.com/fangbangru/homebrew-sitecheck.git
cd homebrew-sitecheck
chmod +x check_site.sh
./check_site.sh <URL>
```

### 3. Windows Environment

* **WSL/Ubuntu**: Follow the same Linux environment clone steps above
* **Git Bash**: Same as above. Ensure `curl`, `bc`, `ping`, `awk` are available
* **PowerShell Native**: Commands can be adapted to `Test-Connection` and `Invoke-WebRequest`

## Usage Examples

```bash
# Basic testing
sitecheck example.com

# Show help
sitecheck --help

# Show version
sitecheck --version

# Skip HTTPS latency test
sitecheck --no-httping example.com

# Generate configuration file
sitecheck --config

# Use JSON format output
sitecheck --format json google.com

# Set warning thresholds
sitecheck --warn-loss 10 --warn-latency 200 example.com

# Batch test multiple sites
echo -e "google.com\ngithub.com\nstackoverflow.com" > sites.txt
sitecheck batch sites.txt

# Quiet mode CSV output
sitecheck --quiet --format csv --no-httping example.com

# Site information detection
sitecheck detection example.com
```

After execution, four main modules will be output in sequence:

1. **Ping Test** (packet loss & RTT)
2. **HTTP Status Code** (2xx/3xx/4xx/5xx explanations)
3. **Response Time Statistics** (DNS / Connect / StartTransfer / Total)
4. **httping Latency** (HTTPS handshake and first byte latency explanations)

Each section includes explanatory text about the meaning and performance evaluation of the current values.

## Sample Output

```bash
$ sitecheck google.com
Loading config: /Users/user/.sitecheck
Testing: https://google.com
  Requests: 3 times, curl timeout: 10s

------------------------------------------------------------------------

1) Ping Test
PING google.com (142.251.215.238): 56 data bytes
64 bytes from 142.251.215.238: icmp_seq=0 ttl=111 time=23.879 ms
64 bytes from 142.251.215.238: icmp_seq=1 ttl=111 time=22.761 ms
64 bytes from 142.251.215.238: icmp_seq=2 ttl=111 time=22.936 ms

--- google.com ping statistics ---
3 packets transmitted, 3 packets received, 0.0% packet loss
round-trip min/avg/max/stddev = 22.761/23.192/23.879/0.491 ms
✅ Packet Loss: 0% (threshold: 100%)
✅ Average RTT: 23.192 ms (threshold: 1000 ms)

------------------------------------------------------------------------

2) HTTP Status Code: 301
   • 2xx Success; 3xx Redirect; 4xx/5xx Error

------------------------------------------------------------------------

3) Response Time Statistics:
   • DNS: 0.001795s (normal <0.1s)
   • TCP+TLS Handshake: 0.024578s (normal <0.05s)
   • Time to First Byte (TTFB): 0.090637s (lower is better)
   • Total Time: 0.090869s

------------------------------------------------------------------------

4) HTTPS Latency (httping):
   • Skipped or httping not installed, no HTTPS latency test performed.

------------------------------------------------------------------------
```

## Requirements

- **macOS** or **Linux**
- **bash** 4.0+
- **curl** (for HTTP testing)
- **ping** (for network testing)
- **bc** (for calculations)
- **awk** (for text processing)
- **dig** (for DNS lookups, optional for detection mode)
- **httping** (optional, for HTTPS latency testing)

## Release and Updates

1. Create new tags and release in the main project repository (e.g., `v0.2.0`)
2. Update `sitecheck.rb` in the Homebrew Tap repository, commit and push
3. Users run `brew update && brew upgrade sitecheck` to get the latest version

## Contributing

1. Fork this repository and create a new branch: `git checkout -b feat-my-feature`
2. Commit changes and push PR: `git commit -am 'feat: add new feature' && git push origin feat-my-feature`
3. Wait for code review and merge

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
