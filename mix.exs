defmodule MobNew.MixProject do
  use Mix.Project

  def project do
    [
      app: :mob_new,
      version: "0.1.0",
      elixir: "~> 1.17",
      deps: deps(),
      description: "Project generator for the Mob mobile framework",
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger, :eex]]
  end

  defp deps do
    [
      {:jason, "~> 1.4"}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/genericjam/mob"}
    ]
  end
end
