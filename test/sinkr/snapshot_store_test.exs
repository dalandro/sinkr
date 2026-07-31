defmodule Sinkr.SnapshotStoreTest do
  @moduledoc """
  The store is where a pinned copy survives its original being renamed or
  deleted, so what's asserted here is mostly "the bytes are still there, at a
  path you can hand to something else".
  """

  use ExUnit.Case, async: true

  # Every test gets its own store root, so the suite can never write into the
  # real one under ~/.local/share.
  @moduletag :tmp_dir

  alias Sinkr.SnapshotStore

  # sha256 of "hello\n", so a change in how the hash is computed fails loudly
  # rather than quietly moving every stored file.
  @hello_sha "5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03"

  setup %{tmp_dir: tmp_dir} do
    previous = Application.get_env(:sinkr, :snapshot_root)
    Application.put_env(:sinkr, :snapshot_root, tmp_dir)
    on_exit(fn -> Application.put_env(:sinkr, :snapshot_root, previous) end)

    source = Path.join(tmp_dir, "source.txt")
    File.write!(source, "hello\n")

    %{root: tmp_dir, source: source}
  end

  describe "put/1" do
    test "names the copy after its contents", %{source: source} do
      assert {:ok, %{sha256: @hello_sha, byte_size: 6}} = SnapshotStore.put(source)
    end

    test "the bytes are readable at the path the hash resolves to", %{source: source} do
      {:ok, %{sha256: sha}} = SnapshotStore.put(source)

      assert File.read!(SnapshotStore.path(sha)) == "hello\n"
    end

    test "the copy outlives the original being deleted", %{source: source} do
      {:ok, %{sha256: sha}} = SnapshotStore.put(source)
      File.rm!(source)

      assert File.read!(SnapshotStore.path(sha)) == "hello\n"
    end

    test "storing the same contents twice keeps one copy", %{source: source, root: root} do
      {:ok, %{sha256: first}} = SnapshotStore.put(source)
      {:ok, %{sha256: second}} = SnapshotStore.put(source)

      assert first == second
      assert length(stored_files(root)) == 1
    end

    test "spreads copies across directories rather than piling them in one", %{
      source: source,
      root: root
    } do
      {:ok, %{sha256: sha}} = SnapshotStore.put(source)

      assert [dir, file] = SnapshotStore.path(sha) |> Path.relative_to(root) |> Path.split()
      assert String.length(dir) == 2
      assert dir <> file == sha
    end

    test "a path with nothing at it is an error, not a stored empty file", %{root: root} do
      assert {:error, :enoent} = SnapshotStore.put(Path.join(root, "was-never-here.png"))
      assert stored_files(root) == []
    end
  end

  describe "put_bytes/2" do
    test "stores bytes that never had a file of their own" do
      {:ok, %{sha256: sha, byte_size: size}} =
        SnapshotStore.put_bytes("a screenshot pretending to be png", "shot.png")

      assert sha == "55a7c417e5b32bb53df4fa8f2d9e1eefbd6f600efc2c0d4a6d037a36662e50c6"
      assert size == 33
      assert File.read!(SnapshotStore.path(sha)) == "a screenshot pretending to be png"
    end

    test "hashes the same as putting the equivalent file", %{source: source} do
      {:ok, %{sha256: from_file}} = SnapshotStore.put(source)
      {:ok, %{sha256: from_bytes}} = SnapshotStore.put_bytes("hello\n", "hello.txt")

      assert from_file == from_bytes
    end
  end

  describe "exists?/1" do
    test "true once the bytes are stored", %{source: source} do
      {:ok, %{sha256: sha}} = SnapshotStore.put(source)

      assert SnapshotStore.exists?(sha)
    end

    test "false for a hash nothing was ever stored under" do
      refute SnapshotStore.exists?(String.duplicate("a", 64))
    end
  end

  defp stored_files(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.reject(&(Path.basename(&1) == "source.txt"))
  end
end
