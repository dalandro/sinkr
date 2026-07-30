defmodule SinkrWeb.TicketLive.Index do
  @moduledoc """
  The whole dashboard: loose ends grouped by status on the left, whichever one
  you've picked on the right.

  Everything lives in one LiveView rather than an index/show pair, because the
  detail pane sits alongside the list rather than replacing it — picking a
  ticket is a `patch`, not a page load.
  """

  use SinkrWeb, :live_view

  alias Sinkr.Tickets
  alias Sinkr.Tickets.Ticket

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(category_filter: nil) |> load_tickets()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, selected: nil, editing: nil, form: nil)
  end

  defp apply_action(socket, :show, %{"ref" => ref}) do
    assign(socket, selected: Tickets.get_ticket_by_ref!(ref), editing: nil, form: nil)
  end

  defp apply_action(socket, :new, _params) do
    open_form(socket, %Ticket{}, nil)
  end

  defp apply_action(socket, :edit, %{"ref" => ref}) do
    ticket = Tickets.get_ticket_by_ref!(ref)
    open_form(socket, ticket, ticket)
  end

  # A new ticket has nothing to select in the list yet, so `selected` is passed
  # separately rather than assumed to be the ticket being edited.
  defp open_form(socket, ticket, selected) do
    assign(socket,
      selected: selected,
      editing: ticket,
      form: to_form(Tickets.change_ticket(ticket))
    )
  end

  @impl true
  def handle_event("filter", %{"category" => category}, socket) do
    # Matching against the known list rather than String.to_atom/1 keeps a junk
    # value from minting an atom; an unrecognised one just means "no filter".
    filter = Enum.find(Ticket.categories(), &(to_string(&1) == category))

    {:noreply, socket |> assign(category_filter: filter) |> load_tickets()}
  end

  def handle_event("validate", %{"ticket" => params}, socket) do
    form =
      socket.assigns.editing
      |> Tickets.change_ticket(params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, form: form)}
  end

  def handle_event("save", %{"ticket" => params}, socket) do
    save(socket, socket.assigns.editing, params)
  end

  def handle_event("set_status", %{"status" => status}, socket) do
    {:ok, updated} = Tickets.update_ticket(socket.assigns.selected, %{status: status})

    {:noreply, socket |> assign(selected: updated) |> load_tickets()}
  end

  def handle_event("delete", _params, socket) do
    {:ok, _ticket} = Tickets.delete_ticket(socket.assigns.selected)

    {:noreply,
     socket
     |> load_tickets()
     |> put_flash(:info, "Thrown away.")
     |> push_patch(to: ~p"/")}
  end

  defp save(socket, %Ticket{id: nil}, params) do
    case Tickets.create_ticket(params) do
      {:ok, ticket} -> saved(socket, ticket, "Opened.")
      {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save(socket, %Ticket{} = ticket, params) do
    case Tickets.update_ticket(ticket, params) do
      {:ok, updated} -> saved(socket, updated, "Saved.")
      {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp saved(socket, ticket, message) do
    {:noreply,
     socket
     |> load_tickets()
     |> put_flash(:info, message)
     |> push_patch(to: ~p"/tickets/#{Ticket.display_ref(ticket)}")}
  end

  defp load_tickets(socket) do
    all = Tickets.list_tickets()
    visible = filter_by_category(all, socket.assigns.category_filter)

    assign(socket,
      total_count: length(all),
      visible_count: length(visible),
      grouped: Tickets.group_by_status(visible)
    )
  end

  defp filter_by_category(tickets, nil), do: tickets
  defp filter_by_category(tickets, category), do: Enum.filter(tickets, &(&1.category == category))

  defp status_options, do: Enum.map(Ticket.statuses(), &{Phoenix.Naming.humanize(&1), &1})
  defp category_options, do: Enum.map(Ticket.categories(), &{Phoenix.Naming.humanize(&1), &1})
  defp priority_options, do: Enum.map(0..3, &{"P#{&1}", &1})

  defp status_tone(:active), do: "bg-success"
  defp status_tone(:blocked), do: "bg-error"
  defp status_tone(:queued), do: "bg-info"
  defp status_tone(:parked), do: "bg-warning"
  defp status_tone(:done), do: "bg-base-300"

  defp selected?(nil, _ticket), do: false
  defp selected?(selected, ticket), do: selected.id == ticket.id

  defp cancel_path(%Ticket{id: nil}), do: ~p"/"
  defp cancel_path(ticket), do: ~p"/tickets/#{Ticket.display_ref(ticket)}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Loose ends
        <:subtitle>
          {if @visible_count == @total_count,
            do: "#{@total_count} open",
            else: "#{@visible_count} of #{@total_count} shown"}
        </:subtitle>
        <:actions>
          <.button navigate={~p"/tickets/new"} variant="primary" id="new-ticket">
            New ticket
          </.button>
        </:actions>
      </.header>

      <div class="flex flex-wrap items-center gap-1">
        <button
          type="button"
          phx-click="filter"
          phx-value-category=""
          class={["btn btn-xs", is_nil(@category_filter) && "btn-primary"]}
        >
          All
        </button>
        <button
          :for={category <- Ticket.categories()}
          type="button"
          phx-click="filter"
          phx-value-category={category}
          class={["btn btn-xs", @category_filter == category && "btn-primary"]}
        >
          {Phoenix.Naming.humanize(category)}
        </button>
      </div>

      <div class="grid gap-6 lg:grid-cols-2">
        <div class="space-y-5">
          <p :if={@grouped == []} class="text-base-content/60 text-sm">
            Nothing to show. <.link navigate={~p"/tickets/new"} class="link">Open one</.link>.
          </p>

          <section :for={{status, tickets} <- @grouped}>
            <h2 class="text-base-content/60 mb-1 flex items-center gap-2 text-xs font-semibold tracking-wide uppercase">
              <span class={["size-2 rounded-full", status_tone(status)]}></span>
              {Phoenix.Naming.humanize(status)}
              <span class="text-base-content/40 font-normal">{length(tickets)}</span>
            </h2>

            <ul class="divide-base-300 divide-y">
              <li :for={ticket <- tickets}>
                <.link
                  patch={~p"/tickets/#{Ticket.display_ref(ticket)}"}
                  class={[
                    "hover:bg-base-200 block border-l-2 px-2 py-2",
                    if(selected?(@selected, ticket),
                      do: "bg-base-200 border-primary",
                      else: "border-transparent"
                    )
                  ]}
                >
                  <span class="block truncate text-sm">{ticket.title}</span>
                  <span class="text-base-content/50 font-mono text-xs">
                    {Ticket.display_ref(ticket)} · P{ticket.priority} · {Phoenix.Naming.humanize(
                      ticket.category
                    )}
                  </span>
                </.link>
              </li>
            </ul>
          </section>
        </div>

        <div class="lg:border-base-300 lg:border-l lg:pl-6">
          <div :if={@form} class="space-y-4">
            <h2 class="text-lg font-semibold">
              {if @editing.id, do: "Editing #{Ticket.display_ref(@editing)}", else: "New ticket"}
            </h2>

            <.form for={@form} id="ticket-form" phx-change="validate" phx-submit="save">
              <.input field={@form[:title]} label="Title" />
              <.input
                field={@form[:category]}
                type="select"
                label="Category"
                prompt="Pick one"
                options={category_options()}
              />
              <.input field={@form[:status]} type="select" label="Status" options={status_options()} />
              <.input
                field={@form[:priority]}
                type="select"
                label="Priority"
                options={priority_options()}
              />
              <.input
                field={@form[:next_step]}
                type="textarea"
                label="Next step"
                rows="3"
                placeholder="What's the next thing you'd do?"
              />

              <div class="flex gap-2 pt-3">
                <.button variant="primary" phx-disable-with="Saving…">Save</.button>
                <.button patch={cancel_path(@editing)}>Cancel</.button>
              </div>
            </.form>
          </div>

          <div :if={is_nil(@form) && @selected} class="space-y-4">
            <h2 class="text-lg leading-snug font-semibold">{@selected.title}</h2>

            <p class="text-base-content/50 font-mono text-xs">
              {Ticket.display_ref(@selected)} · P{@selected.priority} · {Phoenix.Naming.humanize(
                @selected.category
              )}
            </p>

            <div
              :if={@selected.next_step}
              class="border-warning bg-warning/10 rounded border-l-2 py-2 pl-3 text-sm"
            >
              {@selected.next_step}
            </div>

            <form phx-change="set_status" id="quick-status">
              <.input
                type="select"
                id="quick-status-select"
                name="status"
                label="Status"
                value={@selected.status}
                options={status_options()}
              />
            </form>

            <div class="flex gap-2">
              <.button patch={~p"/tickets/#{Ticket.display_ref(@selected)}/edit"} id="edit-ticket">
                Edit
              </.button>
              <.button
                phx-click="delete"
                id="delete-ticket"
                data-confirm="Throw this ticket away for good?"
              >
                Delete
              </.button>
            </div>
          </div>

          <p :if={is_nil(@form) && is_nil(@selected)} class="text-base-content/60 text-sm">
            Pick a ticket to see it.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
