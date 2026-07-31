defmodule Sinkr.SnapshotStore do
  @moduledoc """
  Where a pinned copy of a file lives once you've decided it must survive the
  original being renamed or deleted.

  Content addresses the bytes by their sha256, so storing the same contents
  twice is free — the second write finds a file already there and leaves it
  alone. Copies are spread two hex characters deep so a single directory never
  ends up holding thousands of entries.

  The root directory comes from `Application.fetch_env!(:sinkr, :snapshot_root)`
  rather than being wired in here, so dev, prod, and the test suite can each
  point it somewhere appropriate without this module knowing which is which.
  """

  @doc "Copies the file at `source_path` into the store, keyed by its contents."
  def put(source_path) do
    with {:ok, %File.Stat{size: size}} <- File.stat(source_path) do
      sha256 = hash_file!(source_path)
      store(sha256, fn dest -> File.cp!(source_path, dest) end)
      {:ok, %{sha256: sha256, byte_size: size}}
    end
  end

  @doc "Stores `bytes` directly, for content that never had a file of its own on disk."
  def put_bytes(bytes, _filename) do
    sha256 = hash_bytes(bytes)
    store(sha256, fn dest -> File.write!(dest, bytes) end)
    {:ok, %{sha256: sha256, byte_size: byte_size(bytes)}}
  end

  @sha256_pattern ~r/\A[a-f0-9]{64}\z/

  @doc "Whether `sha256` is 64 lowercase hex characters — the only shape safe to join into a path."
  def valid_sha256?(sha256), do: sha256 =~ @sha256_pattern

  @doc """
  The absolute path a sha256 resolves to, whether or not anything is stored
  there yet.

  Raises on anything that isn't 64 lowercase hex characters. `sha256` usually
  arrives here from outside this module (a URL param, in the controller's
  case), and this is where it gets joined into a filesystem path — so this
  function refuses bad shapes itself rather than trusting every caller to
  have checked first.
  """
  def path(sha256) do
    unless valid_sha256?(sha256) do
      raise ArgumentError, "not a sha256: #{inspect(sha256)}"
    end

    <<dir::binary-size(2), rest::binary>> = sha256
    Path.join([root(), dir, rest])
  end

  @doc "Whether bytes are already stored under this hash."
  def exists?(sha256), do: File.exists?(path(sha256))

  # Streamed rather than read whole, since attachments can be tens of
  # megabytes and this can't assume it's the only thing in memory.
  defp hash_file!(source_path) do
    source_path
    |> File.stream!(65_536)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
  end

  defp hash_bytes(bytes) do
    :sha256
    |> :crypto.hash(bytes)
    |> Base.encode16(case: :lower)
  end

  # Content-addressed, so if the destination already exists its bytes are
  # already the ones being written — writing again would be redundant, not
  # wrong, but skipping it is what keeps "storing twice" from touching disk.
  defp store(sha256, write_fun) do
    dest = path(sha256)

    unless File.exists?(dest) do
      File.mkdir_p!(Path.dirname(dest))
      write_fun.(dest)
    end

    :ok
  end

  defp root, do: Application.fetch_env!(:sinkr, :snapshot_root)
end
