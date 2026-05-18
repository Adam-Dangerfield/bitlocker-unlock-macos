class BitlockerMacos < Formula
  desc "macOS native BitLocker volume mount tool"
  homepage "https://github.com/your-org/bitlocker-macos"
  url "https://github.com/your-org/bitlocker-macos/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  license "MIT"

  depends_on "cmake" => :build
  depends_on "openssl@3"
  depends_on "macfuse"
  depends_on "ntfs-3g"

  def install
    args = std_cmake_args + ["-DCMAKE_PREFIX_PATH=#{Formula["openssl@3"].opt_prefix}"]
    system "cmake", "-S", ".", "-B", "build", *args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"
  end

  test do
    assert_match "Usage", shell_output("#{bin}/bitlocker-info --help", 1)
  end
end
