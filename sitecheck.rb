class Sitecheck < Formula
  desc "Shell-based site performance checker (ping, HTTP code, timing, httping)"
  homepage "https://github.com/fangbangru/check-site"
  url "https://codeload.github.com/fangbangru/homebrew-sitecheck/tar.gz/refs/tags/v0.1.4"
  sha256 "aee3476b49bba96c8e71875a863874e917cdd8f36c9d7bff70e552d21ed2b4e5"
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
