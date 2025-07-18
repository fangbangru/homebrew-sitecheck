class Sitecheck < Formula
  desc "Shell-based site performance checker (ping, HTTP code, timing, httping)"
  homepage "https://github.com/fangbangru/check-site"
  url "https://github.com/fangbangru/homebrew-sitecheck/archive/refs/tags/v0.1.9.tar.gz"
  sha256 "0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5"
  license "MIT"

  depends_on "bash"
  depends_on "curl"
  depends_on "bc"
  depends_on "awk"
  option "with-httping", "Enable HTTPS latency test via httping"
  depends_on "httping" => :optional

  def install
    # 确保脚本具有可执行权限
    chmod 0755, "check_site.sh"
    # 安装并重命名为 sitecheck
    bin.install "check_site.sh" => "sitecheck"
  end

  test do
    # 执行不带参数时应退出并输出 Usage
    output = shell_output("#{bin}/sitecheck", 1)
    assert_match "Usage: sitecheck", output
  end
end
