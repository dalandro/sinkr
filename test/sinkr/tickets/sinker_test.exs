defmodule Sinkr.Tickets.SinkerTest do
  # Changeset validation is pure, so this case needs no database and no sandbox.
  use ExUnit.Case, async: true

  import Sinkr.DataCase, only: [errors_on: 1]

  alias Sinkr.Tickets.Sinker

  describe "changeset/2" do
    test "a sinker needs something to point at" do
      changeset = Sinker.changeset(%Sinker{}, %{type: :file, origin: :path, value: ""})

      assert %{value: ["can't be blank"]} = errors_on(changeset)
    end

    test "a sinker needs to say what kind of thing it points at" do
      changeset = Sinker.changeset(%Sinker{}, %{origin: :path, value: "/tmp/run.log"})

      assert %{type: ["can't be blank"]} = errors_on(changeset)
    end

    test "a sinker needs to say where its value came from" do
      changeset = Sinker.changeset(%Sinker{}, %{type: :file, value: "/tmp/run.log"})

      assert %{origin: ["can't be blank"]} = errors_on(changeset)
    end

    test "a type this slice can't resolve is rejected rather than stored" do
      changeset =
        Sinker.changeset(%Sinker{}, %{type: :herdr_space, origin: :path, value: "ws-1"})

      assert %{type: ["is invalid"]} = errors_on(changeset)
    end

    test "an origin that isn't one of the two ways in is rejected" do
      changeset =
        Sinker.changeset(%Sinker{}, %{type: :file, origin: :telepathy, value: "/tmp/run.log"})

      assert %{origin: ["is invalid"]} = errors_on(changeset)
    end

    test "a file at a path is valid" do
      changeset =
        Sinker.changeset(%Sinker{}, %{type: :file, origin: :path, value: "/tmp/run.log"})

      assert changeset.valid?
    end

    test "a dropped file, which has a name but no path, is valid" do
      changeset =
        Sinker.changeset(%Sinker{}, %{
          type: :file,
          origin: :upload,
          value: "Screenshot 2026-07-31.png"
        })

      assert changeset.valid?
    end
  end

  describe "display_name/1" do
    test "a path is shortened to the file at the end of it" do
      sinker = %Sinker{type: :file, origin: :path, value: "/home/dc/skillz/ci/validate.mjs"}

      assert Sinker.display_name(sinker) == "validate.mjs"
    end

    test "a dropped file is named by the name it arrived with" do
      sinker = %Sinker{type: :file, origin: :upload, value: "Screenshot 2026-07-31.png"}

      assert Sinker.display_name(sinker) == "Screenshot 2026-07-31.png"
    end
  end
end
