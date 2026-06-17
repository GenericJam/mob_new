defmodule MobNew.VersionCheckTest do
  use ExUnit.Case, async: true

  alias MobNew.VersionCheck

  describe "current_version/0" do
    test "matches the project version" do
      assert VersionCheck.current_version() == Mix.Project.config()[:version]
    end
  end

  describe "parse_latest/1" do
    test "prefers latest_stable_version" do
      body = ~s({"name":"mob_new","latest_stable_version":"0.4.7","latest_version":"0.5.0-rc.1"})
      assert VersionCheck.parse_latest(body) == {:ok, "0.4.7"}
    end

    test "falls back to latest_version when no stable field" do
      body = ~s({"name":"mob_new","latest_version":"0.4.7"})
      assert VersionCheck.parse_latest(body) == {:ok, "0.4.7"}
    end

    test "tolerates whitespace after the colon" do
      assert VersionCheck.parse_latest(~s({"latest_stable_version": "1.2.3"})) == {:ok, "1.2.3"}
    end

    test "errors on a body with no version field" do
      assert VersionCheck.parse_latest(~s({"name":"mob_new"})) == :error
    end

    test "errors on non-binary input" do
      assert VersionCheck.parse_latest(nil) == :error
    end
  end

  describe "notice/2" do
    test "returns an update hint when behind" do
      msg = VersionCheck.notice("0.4.6", {:ok, "0.4.7"})
      assert msg =~ "0.4.7"
      assert msg =~ "0.4.6"
      assert msg =~ "mix archive.install hex mob_new"
    end

    test "nil when up to date" do
      assert VersionCheck.notice("0.4.7", {:ok, "0.4.7"}) == nil
    end

    test "nil when ahead (e.g. local dev build)" do
      assert VersionCheck.notice("0.5.0", {:ok, "0.4.7"}) == nil
    end

    test "nil when the fetch failed" do
      assert VersionCheck.notice("0.4.7", :error) == nil
    end

    test "nil (not a crash) when a version is unparseable" do
      assert VersionCheck.notice("not-a-version", {:ok, "0.4.7"}) == nil
    end
  end
end
