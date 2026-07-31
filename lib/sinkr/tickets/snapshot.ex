defmodule Sinkr.Tickets.Snapshot do
  @moduledoc """
  A copy of a sinker's bytes, taken on purpose and kept even once the
  original is renamed, moved, or deleted.

  The bytes themselves are not here — they live in `Sinkr.SnapshotStore`,
  addressed by `sha256`, so this row stays small and every copy still has a
  path something can `Read`. `pinned_at` is the only fact this table asserts;
  everything else (whether the *original* still exists) is derived elsewhere,
  never stored.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "snapshots" do
    field :sha256, :string
    field :filename, :string
    field :mime, :string
    field :byte_size, :integer
    field :pinned_at, :utc_datetime

    belongs_to :sinker, Sinkr.Tickets.Sinker

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(snapshot, attrs) do
    snapshot
    |> cast(attrs, [:sha256, :filename, :mime, :byte_size, :pinned_at])
    |> validate_required([:sha256, :filename, :mime, :byte_size, :pinned_at])
  end
end
