class Sitecheck < Formula
  desc "Shell-based site performance checker (ping, HTTP code, timing, httping)"
  homepage "https://github.com/fangbangru/homebrew-sitecheck"
  url "https://github.com/fangbangru/homebrew-sitecheck.git",
      branch: "main"
  version "0.2.0"
  license "MIT"

  depends_on "bash"
  depends_on "curl"
  depends_on "bc"
  depends_on "awk"
  option "with-httping", "Enable HTTPS latency test via httping"
  depends_on "httping" => :optional

  def install
    # Ensure script has executable permissions
    chmod 0755, "check_site.sh"
    # Install and rename to sitecheck
    bin.install "check_site.sh" => "sitecheck"
  end

  test do
    # Should exit with usage message when run without arguments
    output = shell_output("#{bin}/sitecheck", 1)
    assert_match "Usage: sitecheck", output
  end
end
