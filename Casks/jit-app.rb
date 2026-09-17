# The temporary jit-app cask, retired: `jitpass` now installs the app with
# the jit CLI inside it. Kept so `brew upgrade` tells existing users where
# to go instead of failing on a missing cask.
cask "jit-app" do
  version "0.8.1"
  sha256 "29510d1dd6f3ef62645e67f1ef5cf4a4b9a6288528cf74a629cdf0364165964a"

  url "https://github.com/jitpass/jit-app/releases/download/v#{version}/JitPass-#{version}-arm64.zip"
  name "JitPass"
  desc "Menu bar app for jit, the just-in-time secrets tool"
  homepage "https://github.com/jitpass/jit-app"

  deprecate! date: "2026-09-17", because: "the jitpass cask now installs the app together with the jit CLI",
             replacement_cask: "jitpass"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "JitPass.app"
end
