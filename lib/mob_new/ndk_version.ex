defmodule MobNew.NdkVersion do
  @moduledoc """
  Mirror of `MobDev.NdkVersion`'s `@recommended` constant.

  `mob_new` ships as a Mix archive and cannot depend on `mob_dev` at
  project-generation time, so the recommended NDK version has to be
  duplicated here to feed into the generated `android/app/build.gradle`
  template.

  A drift test (`test/mob_new/ndk_version_test.exs`) asserts this stays
  in lockstep with `MobDev.NdkVersion.recommended/0` by reading the
  source file at `../mob_dev/lib/mob_dev/ndk_version.ex`. When you bump
  the NDK there, bump it here too — CI will catch it if you forget.

  See `~/code/mob_dev/lib/mob_dev/ndk_version.ex` for the rationale
  (libc++ inline-namespace ABI mismatch between NDK 25 and 27).
  """

  @recommended "27.2.12479018"

  @doc "The NDK version Mob's bundled OTP tarballs were cross-compiled with."
  @spec recommended() :: String.t()
  def recommended, do: @recommended
end
