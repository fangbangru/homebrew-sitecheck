class Sitecheck < Formula
  desc "Shell-based site performance checker (ping, HTTP code, timing, httping)"
  homepage "https://github.com/fangbangru/check-site"
  url "https://codeload.github.com/fangbangru/homebrew-sitecheck/tar.gz/refs/tags/v0.1.2"
  sha256 "8e7b5423c0379e74f86e3a9d99379b21352e33cd185aba75596dfe815a824d9e"
  license "MIT"

  depends_on "bash"
  depends_on "curl"
  depends_on "bc"
  depends_on "awk"
  # 建议用户按需安装 httping
  option "with-httping", "Enable HTTPS latency test via httping"
  depends_on "httping" => :optional

  def install
    bin.install "check_site.sh" => "sitecheck"
  end

  test do
    assert_match "Usage: sitecheck", shell_output("#{bin}/sitecheck", 1)
  end
end
