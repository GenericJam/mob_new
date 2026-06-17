defmodule MobNew.MixProject do
  use Mix.Project

  def project do
    [
      app: :mob_new,
      version: "0.4.7",
      elixir: "~> 1.19",
      deps: deps(),
      aliases: aliases(),
      description: "Project generator for the Mob mobile framework",
      source_url: "https://github.com/genericjam/mob_new",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger, :eex]]
  end

  defp aliases do
    # `mix setup` after cloning installs deps and activates the shared git
    # hooks (.githooks): format / Credo --strict / compile run on every push
    # and the full suite when mix.exs changes — the same gate CI enforces.
    [setup: ["deps.get", "cmd git config core.hooksPath .githooks"]]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # ex_slop — Credo check that catches AI-generated Elixir patterns
      # (blanket rescue, narrator docs, etc). Wired in via .credo.exs.
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      # mix_audit — CVE scan over mix.lock. Invocation note: `mix
      # deps.audit` alone fails with `YamlElixir.read_from_file/1 is
      # undefined` because mix_audit doesn't ensure_all_started its
      # yaml_elixir transitive dep; CI uses `mix do app.start +
      # deps.audit` which starts the host app and pulls yaml_elixir in.
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "Mix.Tasks.Mob.New",
      source_url: "https://github.com/genericjam/mob_new",
      source_url_pattern: "https://github.com/genericjam/mob_new/blob/master/%{path}#L%{line}",
      extras: [
        "README.md": [title: "mob_new"],
        "CHANGELOG.md": [title: "Changelog"]
      ]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/genericjam/mob_new"}
    ]
  end
end
