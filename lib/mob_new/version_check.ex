defmodule MobNew.VersionCheck do
  @moduledoc """
  Best-effort "is a newer `mob.new` available?" check, in the spirit of
  `phx.new`'s installer-version notice.

  `mix mob.new` calls `print_notice/0` once at the end of a run. It fetches the
  latest published version from the Hex API and, if the installed archive is
  behind, prints a one-line hint to update via `mix archive.install hex mob_new`.

  Constraints this module respects:

    * **Archive-safe.** mob_new ships as a Mix `.ez` that bundles only its own
      beams, so this code touches OTP/Elixir stdlib only (`:httpc`, `:ssl`,
      `Version`, `Regex`) — never a hex dep like Jason. The JSON body is parsed
      with a narrow regex rather than a JSON library for the same reason.
    * **Never fatal, never slow.** Every failure mode (offline, DNS, timeout,
      malformed body, unparseable version) collapses to "say nothing." The
      network call is capped by a short timeout so a fresh `mix mob.new` never
      hangs on it.
  """

  # Captured at compile time = the version of the mob_new being compiled, which
  # is exactly what an installed archive reports. (phx.new uses this pattern.)
  @version Mix.Project.config()[:version]

  @hex_url ~c"https://hex.pm/api/packages/mob_new"
  @default_timeout 2_000

  @doc "The version of this installed mob_new archive."
  @spec current_version() :: String.t()
  def current_version, do: @version

  @doc """
  Fetches the latest published version string from the Hex API.

  Returns `{:ok, version}` or `:error` (any failure). Best-effort, capped by
  `timeout` ms. Public for testing the orchestration boundary.
  """
  @spec fetch_latest(non_neg_integer()) :: {:ok, String.t()} | :error
  def fetch_latest(timeout \\ @default_timeout) do
    with :ok <- ensure_started(),
         {:ok, body} <- get(@hex_url, timeout) do
      parse_latest(body)
    end
  end

  @doc """
  Extracts the latest stable version from a Hex package API JSON body without a
  JSON dependency. Prefers `latest_stable_version`, falls back to
  `latest_version`. Returns `{:ok, version}` or `:error`. Pure — public for
  testing.
  """
  @spec parse_latest(binary()) :: {:ok, String.t()} | :error
  def parse_latest(body) when is_binary(body) do
    stable = Regex.run(~r/"latest_stable_version":\s*"([^"]+)"/, body)
    latest = Regex.run(~r/"latest_version":\s*"([^"]+)"/, body)

    case stable || latest do
      [_, vsn] -> {:ok, vsn}
      _ -> :error
    end
  end

  def parse_latest(_), do: :error

  @doc """
  The user-facing notice given the current version and a `fetch_latest/1`
  result. Returns the message string when the installed archive is strictly
  behind the latest, otherwise `nil` (up to date, ahead, fetch failed, or
  either version is unparseable). Pure — public for testing.
  """
  @spec notice(String.t(), {:ok, String.t()} | :error) :: String.t() | nil
  def notice(current, {:ok, latest}) when is_binary(current) and is_binary(latest) do
    if behind?(current, latest) do
      "A new mob.new is available: #{latest} (you have #{current}).\n" <>
        "Update with: mix archive.install hex mob_new"
    end
  end

  def notice(_current, _result), do: nil

  @doc """
  Fetches the latest version and prints an update hint if one is warranted.
  Always returns `:ok`; never raises and never blocks beyond the fetch timeout.
  """
  @spec print_notice(non_neg_integer()) :: :ok
  def print_notice(timeout \\ @default_timeout) do
    case notice(current_version(), fetch_latest(timeout)) do
      msg when is_binary(msg) -> Mix.shell().info([:yellow, "\n", msg, :reset])
      _ -> :ok
    end

    :ok
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  # `current` strictly older than `latest`. Tolerates non-semver strings by
  # treating any comparison error as "not behind" (say nothing).
  defp behind?(current, latest) do
    Version.compare(current, latest) == :lt
  rescue
    _ -> false
  end

  defp ensure_started do
    # Starting the apps isn't enough: on some OTP builds `ssl`/`httpc` aren't
    # code-loaded by `ensure_all_started`, and httpc's call into `ssl:connect/4`
    # then fails `:undef` instead of auto-loading. Force the module load.
    with {:ok, _} <- Application.ensure_all_started(:inets),
         {:ok, _} <- Application.ensure_all_started(:ssl),
         {:module, _} <- Code.ensure_loaded(:ssl),
         {:module, _} <- Code.ensure_loaded(:httpc) do
      :ok
    else
      _ -> :error
    end
  end

  defp get(url, timeout) do
    headers = [{~c"user-agent", ~c"mob_new-version-check"}]
    # verify_none is deliberate: this is a non-sensitive read of a public
    # version number, and pinning cert verification to the system CA store
    # (`:public_key.cacerts_get/0`) isn't portable across the OTP builds users
    # run — some lack it, and httpc's default verify path crashes on those.
    # Skipping validation for one version check is the lesser evil; a tampered
    # response can at worst suppress or fake an "update available" hint.
    http_opts = [timeout: timeout, connect_timeout: timeout, ssl: [verify: :verify_none]]

    case :httpc.request(:get, {url, headers}, http_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _resp_headers, body}} -> {:ok, body}
      _ -> :error
    end
  end
end
