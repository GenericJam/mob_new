defmodule MobNew.MixProject do
  use Mix.Project

  def project do
    [
      app: :mob_new,
      version: "0.1.24",
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
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
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
