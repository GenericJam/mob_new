defmodule MobNew.ArchiveSelfContainedTest do
  use ExUnit.Case, async: true

  # mob_new ships as a Mix *archive* (.ez), which bundles only mob_new's own
  # beams — NOT its hex deps. So every module `mix mob.new` reaches at runtime
  # must be a mob_new module or Elixir/OTP stdlib (always present in the
  # runtime). A call into a hex dep (Sourceror, Jason, Req, …) compiles and
  # tests green *from the repo* but crashes every installed user with
  # `UndefinedFunctionError`. This pins the self-contained invariant so that
  # regression class can't reappear silently. See issues.md #1.
  test "archive-reachable code references no non-bundled hex-dep modules" do
    build_lib = Mix.Project.build_path() |> Path.join("lib") |> Path.expand()
    mob_new_lib = Path.join(build_lib, "mob_new")

    {:ok, modules} = :application.get_key(:mob_new, :modules)

    # Every external module mob_new's beams call (the BEAM 'ImpT' chunk).
    called =
      for mod <- modules,
          beam = :code.which(mod),
          is_list(beam),
          {:ok, {_, [{:imports, imports}]}} = :beam_lib.chunks(beam, [:imports]),
          {m, _f, _a} <- imports,
          uniq: true,
          do: m

    # An offender is a called module whose beam lives under the build's dep dir
    # (`_build/<env>/lib/<dep>`) and isn't mob_new — i.e. a hex dep. Stdlib/OTP
    # modules resolve to the Elixir/Erlang install, not `_build/`.
    offenders =
      for m <- called,
          path = :code.which(m),
          is_list(path),
          expanded = Path.expand(to_string(path)),
          String.starts_with?(expanded, build_lib),
          not String.starts_with?(expanded, mob_new_lib),
          uniq: true,
          do: m

    assert offenders == [],
           "Archive-reachable mob_new code calls hex-dep modules absent from " <>
             "the installed .ez: #{inspect(offenders)}. Use stdlib or vendor " <>
             "the code instead (see issues.md #1)."
  end
end
