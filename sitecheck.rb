class Sitecheck < Formula
  desc "Shell-based site performance checker (ping, HTTP code, timing, httping)"
  homepage "https://github.com/fangbangru/check-site"
  url "https://github.com/fangbangru/homebrew-sitecheck/archive/v0.1.1.tar.gz"
  sha256 "b0e258f556e556a952aee616f150442f80da8afa0b592307de898900c37b6d14"
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
