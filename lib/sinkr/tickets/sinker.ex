defmodule Sinkr.Tickets.Sinker do
  @moduledoc """
  A ticket's optional link down to where the work actually lives.

  A ticket is shallow — a title, some comments. A sinker is what drops you
  back to the real thing a week later: a script, a screenshot, a log. This
  slice only knows one kind, `:file`; `type` is a row rather than a column so
  later kinds (`:worktree`, ...) are an insert, not a migration.

  `origin` earns its own field rather than being inferred from `value`: a
  dropped file arrives with a filename and nothing else, no directory it can
  be found in. Without `origin` to say so, that bare filename would get
  `stat`'d like a path, and "there was never a file on disk" would render
  identically to "the file used to be here and now it's gone" — the one case
  this app exists to tell apart from the other.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @types [:file]
  @origins [:path, :upload]

  schema "sinkers" do
    field :type, Ecto.Enum, values: @types
    field :value, :string
    field :origin, Ecto.Enum, values: @origins

    belongs_to :ticket, Sinkr.Tickets.Ticket
    has_one :snapshot, Sinkr.Tickets.Snapshot

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(sinker, attrs) do
    sinker
    |> cast(attrs, [:type, :value, :origin])
    |> validate_required([:type, :value, :origin])
  end

  @doc """
  What to show for a sinker without printing its whole value.

  A path is shortened to the file at the end of it — the directories are
  usually noise once you already know which ticket you're looking at. A
  dropped file has no directories to shorten; its value already is the name
  it arrived with.
  """
  def display_name(%__MODULE__{origin: :path, value: value}), do: Path.basename(value)
  def display_name(%__MODULE__{origin: :upload, value: value}), do: value
end
