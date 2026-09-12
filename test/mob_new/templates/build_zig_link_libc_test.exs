defmodule MobNew.Templates.BuildZigLinkLibcTest do
  # mob 0.8's mob_nif.zig calls libc (post-mortem capsule, MOB-180). A Zig
  # module compiled without `link_libc` fails with "dependency on libc must be
  # explicitly specified", which took every fresh Android native build down
  # after mob 0.8.2 shipped (MOB-196). This pins the declaration on the shared
  # Zig-object helper, which compiles both mob_beam.zig and mob_nif.zig.
  use ExUnit.Case, async: true

  @template "priv/templates/mob.new/android/app/src/main/jni/build.zig.eex"

  test "the Android Zig-object helper links libc" do
    [helper] =
      @template
      |> File.read!()
      |> String.split("fn addZigObject(")
      |> Enum.drop(1)

    module_literal = helper |> String.split("b.createModule(.{", parts: 2) |> Enum.at(1)
    [module_fields | _] = String.split(module_literal, "});", parts: 2)

    assert module_fields =~ ".link_libc = true,"
    assert module_fields =~ ".root_source_file = .{ .cwd_relative = opts.source },"
  end
end
