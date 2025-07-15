class Sitecheck < Formula
  desc "Shell-based site performance checker (ping, HTTP code, timing, httping)"
  homepage "https://github.com/fangbangru/check-site"
  url "https://codeload.github.com/fangbangru/homebrew-sitecheck/tar.gz/refs/tags/v0.1.4"
  sha256 "1226ddbbafbd5801a6492c22e2e83d2ac34f2d0ab94529eab7b74a2cf35a5bed"
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
