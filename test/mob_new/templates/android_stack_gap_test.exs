# Source-contract tests for Row and Column spacing in the generated Android bridge (MOB-234).
# credo:disable-for-this-file Jump.CredoChecks.VacuousTest
defmodule MobNew.Templates.AndroidStackGapTest do
  use ExUnit.Case, async: true

  @bridge Path.expand(
            "../../../priv/templates/mob.new/android/app/src/main/java/MobBridge.kt.eex",
            __DIR__
          )

  setup_all do
    {:ok, source: File.read!(@bridge)}
  end

  test "column maps gap to its vertical arrangement", %{source: source} do
    column_branch =
      source
      |> String.split(~s|"column" -> Column(|)
      |> Enum.at(1)
      |> String.split(~s|"row" -> Row(|)
      |> hd()

    assert column_branch =~
             ~r/verticalArrangement\s*=\s*Arrangement\.spacedBy\(\s*\(floatProp\(node\.props, "gap"\) \?: 0f\)\.dp\s*\)/
  end

  test "row maps gap to its horizontal arrangement", %{source: source} do
    row_branch =
      source
      |> String.split(~s|"row" -> Row(|)
      |> Enum.at(1)
      |> String.split(~s|"wrap" -> FlowRow(|)
      |> hd()

    assert row_branch =~
             ~r/horizontalArrangement\s*=\s*Arrangement\.spacedBy\(\s*\(floatProp\(node\.props, "gap"\) \?: 0f\)\.dp\s*\)/
  end
end
