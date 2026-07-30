defmodule Sinkr.TicketsTest do
  use Sinkr.DataCase

  alias Sinkr.Tickets
  alias Sinkr.Tickets.Ticket

  describe "group_by_status/1" do
    test "groups tickets in the fixed status order, skipping statuses nothing is in" do
      tickets = [
        %Ticket{title: "wrapped up", status: :done},
        %Ticket{title: "on it", status: :active},
        %Ticket{title: "not started", status: :queued}
      ]

      assert [
               {:active, [%Ticket{title: "on it"}]},
               {:queued, [%Ticket{title: "not started"}]},
               {:done, [%Ticket{title: "wrapped up"}]}
             ] = Tickets.group_by_status(tickets)
    end

    test "puts the most pressing ticket at the top of its group" do
      tickets = [
        %Ticket{title: "someday", status: :active, priority: 3},
        %Ticket{title: "dropping everything", status: :active, priority: 0},
        %Ticket{title: "this week", status: :active, priority: 1}
      ]

      assert [
               {:active,
                [
                  %Ticket{title: "dropping everything"},
                  %Ticket{title: "this week"},
                  %Ticket{title: "someday"}
                ]}
             ] = Tickets.group_by_status(tickets)
    end
  end

  describe "create_ticket/1" do
    test "a ticket you create shows up in the list" do
      {:ok, _ticket} =
        Tickets.create_ticket(%{title: "Tidy the standup skill", category: :chore})

      assert [%Ticket{title: "Tidy the standup skill", category: :chore}] =
               Tickets.list_tickets()
    end

    test "a new ticket starts queued, not active" do
      {:ok, ticket} = Tickets.create_ticket(%{title: "Never started", category: :idea})

      assert ticket.status == :queued
    end
  end

  describe "get_ticket_by_ref!/1" do
    test "you can look a ticket up by the number you see on it" do
      {:ok, ticket} = Tickets.create_ticket(%{title: "Planner won't load", category: :bug})

      found = Tickets.get_ticket_by_ref!("s-#{ticket.id}")

      assert found.title == "Planner won't load"
    end

    test "a ref that isn't a ticket raises rather than blowing up oddly" do
      assert_raise Ecto.NoResultsError, fn -> Tickets.get_ticket_by_ref!("banana") end
    end
  end

  describe "update_ticket/2" do
    test "you move a ticket's status yourself" do
      {:ok, ticket} = Tickets.create_ticket(%{title: "Review MR 1737", category: :review})

      {:ok, updated} = Tickets.update_ticket(ticket, %{status: :active})

      assert updated.status == :active
    end
  end

  describe "delete_ticket/1" do
    test "a deleted ticket leaves the list" do
      {:ok, ticket} = Tickets.create_ticket(%{title: "Never mind", category: :idea})

      {:ok, _} = Tickets.delete_ticket(ticket)

      assert Tickets.list_tickets() == []
    end
  end
end
