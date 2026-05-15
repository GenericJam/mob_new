defmodule MobNew.MixProject do
  use Mix.Project

  def project do
    [
      app: :mob_new,
      version: "0.3.1",
      elixir: "~> 1.19",
      deps: deps(),
      description: "Project generator for the Mob mobile framework",
      source_url: "https://github.com/genericjam/mob",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger, :eex]]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      # Sourceror provides AST-aware Elixir source manipulation. Used by
      # `MobNew.LiveViewPatcher.inject_deps/3` to append `:mob` + `:mob_dev`
      # to the user's mix.exs deps list. Phase 5 of the build-system
      # migration replaced the regex-on-Elixir-source approach that had
      # been the main fragility in the LV generator.
      {:sourceror, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # ex_slop — Credo check that catches AI-generated Elixir patterns
      # (blanket rescue, narrator docs, etc). Wired in via .credo.exs.
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "Mix.Tasks.Mob.New",
      source_url: "https://github.com/genericjam/mob",
      source_url_pattern: "https://github.com/genericjam/mob/blob/main/mob_new/%{path}#L%{line}",
      extras: ["README.md": [title: "mob_new"]]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/genericjam/mob"}
    ]
  end
end
