defmodule MobNew.Templates.IosPluginObjcClangTest do
  use ExUnit.Case, async: true

  @ios Path.expand("../../../priv/templates/mob.new/ios", __DIR__)
  @ios_templates [
    Path.join(@ios, "build.zig.eex"),
    Path.join(@ios, "build_device.zig.eex")
  ]

  # Drift guard. iOS plugin objc NIFs (manifest `lang: :objc`, e.g. mob_camera)
  # MUST be compiled by Apple's clang via addObjcObject (xcrun cc), NOT zig's
  # bundled clang via addCObject. zig clang fails to build the UIKit/Accelerate
  # framework *modules* against current Xcode SDKs ("umbrella header for module
  # 'Accelerate.vecLib' does not include 'lapack.h'", UIKit missing
  # 'UIUtilities/UIDefines.h'), so a plugin objc NIF importing those (vImage,
  # UIImagePickerController) aborts the iOS build. If this regresses, every
  # generated app activating such a plugin breaks the moment it's compiled.
  test "iOS build templates route plugin objc NIFs through addObjcObject (Apple clang)" do
    for tmpl <- @ios_templates do
      src = File.read!(tmpl)
      base = Path.basename(tmpl)

      # After `if (is_objc) {`, the objc branch must reach an addObjcObject CALL
      # before any addCObject CALL (the negative lookahead rules out the buggy
      # objc->addCObject routing; the legitimate `.c` branch's addCObject comes
      # only AFTER this block's `continue;`).
      assert src =~ ~r/if \(is_objc\) \{(?:(?!addCObject\(b, \.\{).)*?addObjcObject\(b, \.\{/s,
             "#{base}: plugin objc (.m) NIFs must compile via addObjcObject (Apple " <>
               "clang via xcrun), not addCObject (zig's bundled clang) — zig clang " <>
               "can't build UIKit/Accelerate framework modules against current Xcode SDKs."
    end
  end
end
