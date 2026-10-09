defmodule MobNew.TemplateAssignsTest do
  # Every template must render against the assigns every generation path
  # builds. A template that reads an assign some path doesn't set fails to
  # compile only on that path (MOB-465: AGENTS.md.eex read `liveview`, which
  # `--local` runs didn't get), so render all of them under every flag
  # combination and fail on any compile error or warning.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias MobNew.ProjectGenerator

  @templates_root Application.app_dir(:mob_new, "priv/templates/mob.new")
  @flags [:local, :blank, :liveview, :python, :deliver]

  setup do
    tmp = Path.join(System.tmp_dir!(), "mob_new_assigns_#{System.unique_integer([:positive])}")

    vars = ~w(MOB_DIR MOB_DEV_DIR MOB_DELIVER_DIR MOB_DELIVER_SERVER_DIR MOB_MISHKA_DIR)
    saved = Map.new(vars, &{&1, System.get_env(&1)})

    for var <- vars do
      dir = Path.join(tmp, String.downcase(var))
      File.mkdir_p!(dir)
      System.put_env(var, dir)
    end

    on_exit(fn ->
      Enum.each(saved, fn
        {var, nil} -> System.delete_env(var)
        {var, val} -> System.put_env(var, val)
      end)

      File.rm_rf!(tmp)
    end)
  end

  test "every template renders without warnings under every flag combination" do
    templates = Path.wildcard(Path.join(@templates_root, "**/*.eex"), match_dot: true)
    assert templates != []

    failures =
      for flags <- combinations(@flags),
          opts = Enum.map(flags, &{&1, true}),
          assigns = ProjectGenerator.assigns("assigns_app", opts),
          template <- templates,
          failure = render(template, assigns),
          do: {flags, Path.relative_to(template, @templates_root), failure}

    assert failures == [], Enum.map_join(failures, "\n", &inspect/1)
  end

  defp render(template, assigns) do
    stderr =
      capture_io(:stderr, fn ->
        try do
          EEx.eval_file(template, Map.to_list(assigns))
          send(self(), :rendered)
        rescue
          e -> send(self(), {:raised, Exception.message(e)})
        end
      end)

    receive do
      :rendered when stderr == "" -> nil
      :rendered -> {:warning, stderr}
      {:raised, message} -> {:raised, message, stderr}
    end
  end

  defp combinations([]), do: [[]]

  defp combinations([flag | rest]) do
    tails = combinations(rest)
    tails ++ Enum.map(tails, &[flag | &1])
  end
end
