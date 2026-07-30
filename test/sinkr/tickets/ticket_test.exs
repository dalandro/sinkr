defmodule Sinkr.Tickets.TicketTest do
  # Changeset validation is pure, so this case needs no database and no sandbox.
  use ExUnit.Case, async: true

  import Sinkr.DataCase, only: [errors_on: 1]

  alias Sinkr.Tickets.Ticket

  describe "changeset/2" do
    test "a ticket needs a title" do
      changeset = Ticket.changeset(%Ticket{}, %{title: ""})

      assert %{title: ["can't be blank"]} = errors_on(changeset)
    end

    test "a ticket needs a category" do
      changeset = Ticket.changeset(%Ticket{}, %{title: "Decide dry-run break semantics"})

      assert %{category: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "display_ref/1" do
    test "a ticket is referred to by its number" do
      assert Ticket.display_ref(%Ticket{id: 12}) == "s-12"
    end
  end
end
