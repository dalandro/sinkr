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
  alias Sinkr.Tickets.Sinker
  alias Sinkr.Tickets.Snapshot
  alias Sinkr.Tickets.Ticket

  @impl true
  def mount(_params, _session, socket) do
    flags = parse_flags(get_connect_params(socket)["flags"])

    {:ok,
     socket
     |> assign(category_filter: nil, flags: flags)
     |> load_tickets()
     |> allow_upload(:files,
       accept: :any,
       max_entries: 10,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, selected: nil, editing: nil, form: nil)
  end

  defp apply_action(socket, :show, %{"ref" => ref}) do
    ticket = Tickets.get_ticket_by_ref!(ref)

    socket
    |> assign(selected: ticket, editing: nil, form: nil)
    |> load_file_entries()
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

  def handle_event("set_flag", %{"flag" => flag, "to" => to}, socket) do
    flags = merge_flag(socket.assigns.flags, flag, to)

    {:noreply, socket |> assign(flags: flags) |> load_tickets()}
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

  def handle_event("attach", %{"path" => path}, socket) do
    case Tickets.attach_file(socket.assigns.selected, path) do
      {:ok, _sinker} -> {:noreply, load_file_entries(socket)}
      {:error, :enoent} -> {:noreply, put_flash(socket, :error, "Nothing at that path: #{path}")}
    end
  end

  # Required for `phx-change` on the upload form; the drop/pick itself is
  # handled by the upload's `progress` callback, not this event.
  def handle_event("validate_upload", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("pin", %{"id" => id}, socket) do
    case Tickets.pin_sinker(Tickets.get_sinker!(id)) do
      {:error, :enoent} ->
        {:noreply, put_flash(socket, :error, "Nothing at that path.")}

      # {:ok, _snapshot} or {:error, :already_pinned} both land on a re-render.
      _ ->
        {:noreply, load_file_entries(socket)}
    end
  end

  def handle_event("unpin", %{"id" => id}, socket) do
    # Already-unpinned is a no-op, not an error worth surfacing.
    Tickets.unpin_sinker(Tickets.get_sinker!(id))

    {:noreply, load_file_entries(socket)}
  end

  def handle_event("detach", %{"id" => id}, socket) do
    {:ok, _sinker} = Tickets.detach_sinker(Tickets.get_sinker!(id))

    {:noreply, load_file_entries(socket)}
  end

  # Only act once an entry is fully received; intermediate progress ticks are
  # a no-op re-render, same as `auto_upload` expects.
  defp handle_progress(:files, entry, socket) do
    if entry.done? do
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        Tickets.attach_upload(socket.assigns.selected, %{
          filename: entry.client_name,
          tmp_path: path
        })
      end)

      {:noreply, load_file_entries(socket)}
    else
      {:noreply, socket}
    end
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

    visible =
      all
      |> filter_by_category(socket.assigns.category_filter)
      |> filter_by_show_done(socket.assigns.flags.show_done)

    assign(socket,
      total_count: length(all),
      visible_count: length(visible),
      visible: visible,
      grouped: Tickets.group_by_status(visible)
    )
  end

  defp filter_by_category(tickets, nil), do: tickets
  defp filter_by_category(tickets, category), do: Enum.filter(tickets, &(&1.category == category))

  defp filter_by_show_done(tickets, true), do: tickets
  defp filter_by_show_done(tickets, false), do: Enum.reject(tickets, &(&1.status == :done))

  defp default_flags, do: %{layout: :grouped, show_done: true}

  defp parse_flags(flags) when is_map(flags) do
    Enum.reduce(flags, default_flags(), fn {flag, to}, acc -> merge_flag(acc, flag, to) end)
  end

  defp parse_flags(_flags), do: default_flags()

  # Matching known flag/value pairs rather than String.to_atom/1 keeps a junk
  # flag or value from minting an atom; anything unrecognised is a no-op.
  defp merge_flag(flags, "layout", "flat"), do: %{flags | layout: :flat}
  defp merge_flag(flags, "layout", "grouped"), do: %{flags | layout: :grouped}
  defp merge_flag(flags, "show_done", "true"), do: %{flags | show_done: true}
  defp merge_flag(flags, "show_done", "false"), do: %{flags | show_done: false}
  defp merge_flag(flags, _flag, _to), do: flags

  defp load_file_entries(socket) do
    assign(socket, file_entries: Tickets.file_entries(socket.assigns.selected))
  end

  defp status_options, do: Enum.map(Ticket.statuses(), &{Phoenix.Naming.humanize(&1), &1})
  defp category_options, do: Enum.map(Ticket.categories(), &{Phoenix.Naming.humanize(&1), &1})

  defp priority_options do
    Enum.map(Ticket.priorities(), fn {level, label} -> {"P#{level} — #{label}", level} end)
  end

  defp status_tone(:active), do: "bg-success"
  defp status_tone(:blocked), do: "bg-error"
  defp status_tone(:queued), do: "bg-info"
  defp status_tone(:parked), do: "bg-warning"
  defp status_tone(:done), do: "bg-base-300"

  defp selected?(nil, _ticket), do: false
  defp selected?(selected, ticket), do: selected.id == ticket.id

  defp cancel_path(%Ticket{id: nil}), do: ~p"/"
  defp cancel_path(ticket), do: ~p"/tickets/#{Ticket.display_ref(ticket)}"

  # `origin: :upload` sinkers get neither button: they're pinned the moment
  # they're attached, so Pin would do nothing — and their copy is all there
  # is, so Unpin would leave a record of nothing. Detach is their only out.
  defp offer_pin?(%Sinker{origin: :path, snapshot: nil}), do: true
  defp offer_pin?(_sinker), do: false

  defp offer_unpin?(%Sinker{origin: :path, snapshot: %Snapshot{}}), do: true
  defp offer_unpin?(_sinker), do: false

  defp image_snapshot?(%{mime: "image/" <> _}), do: true
  defp image_snapshot?(_snapshot), do: false

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} flags={@flags}>
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
          <p :if={@visible == []} class="text-base-content/70 text-sm">
            Nothing to show. <.link navigate={~p"/tickets/new"} class="link">Open one</.link>.
          </p>

          <ul :if={@flags.layout == :flat} class="divide-base-300 divide-y">
            <.ticket_row
              :for={ticket <- Tickets.sort_by_priority(@visible)}
              ticket={ticket}
              selected={@selected}
            />
          </ul>

          <section :for={{status, tickets} <- @grouped} :if={@flags.layout == :grouped}>
            <h2 class="text-base-content/60 mb-1 flex items-center gap-2 text-xs font-semibold tracking-wide uppercase">
              <span class={["size-2 rounded-full", status_tone(status)]}></span>
              {Phoenix.Naming.humanize(status)}
              <span class="text-base-content/60 font-normal">{length(tickets)}</span>
            </h2>

            <ul class="divide-base-300 divide-y">
              <.ticket_row :for={ticket <- tickets} ticket={ticket} selected={@selected} />
            </ul>
          </section>
        </div>

        <div class="lg:border-base-300 lg:sticky lg:top-4 lg:max-h-[calc(100vh-2rem)] lg:self-start lg:overflow-y-auto lg:border-l lg:pl-6">
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

            <p class="text-base-content/70 text-xs">
              ID: {Ticket.display_ref(@selected)} · Category: {Phoenix.Naming.humanize(
                @selected.category
              )} · Priority: {Ticket.priority_label(@selected.priority)} (P{@selected.priority})
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

            <div class="space-y-2">
              <h3 class="text-base-content/60 text-xs font-semibold tracking-wide uppercase">
                Files
              </h3>

              <p :if={@file_entries == []} class="text-base-content/70 text-sm">
                Nothing attached yet.
              </p>

              <div
                :for={entry <- @file_entries}
                id={"sinker-#{entry.sinker.id}"}
                data-role="sinker"
                class="border-base-300 flex items-center justify-between gap-2 rounded border px-2 py-1.5 text-sm"
              >
                <div class="flex min-w-0 items-center gap-2">
                  <img
                    :if={entry.sinker.snapshot && image_snapshot?(entry.sinker.snapshot)}
                    src={~p"/snapshots/#{entry.sinker.snapshot.sha256}"}
                    class="sinker-thumb max-h-24 rounded"
                  />

                  <div class="min-w-0">
                    <a
                      :if={entry.sinker.snapshot}
                      href={~p"/snapshots/#{entry.sinker.snapshot.sha256}"}
                      class="link block truncate"
                    >
                      {Sinker.display_name(entry.sinker)}
                    </a>
                    <span :if={is_nil(entry.sinker.snapshot)} class="block truncate">
                      {Sinker.display_name(entry.sinker)}
                    </span>

                    <div class="flex gap-1 pt-0.5">
                      <span :if={entry.sinker.snapshot} class="badge badge-xs badge-success">
                        pinned
                      </span>
                      <span :if={entry.status == :missing} class="badge badge-xs badge-warning">
                        missing
                      </span>
                    </div>
                  </div>
                </div>

                <div class="flex shrink-0 gap-1">
                  <button
                    :if={offer_pin?(entry.sinker)}
                    type="button"
                    phx-click="pin"
                    phx-value-id={entry.sinker.id}
                    class="btn btn-xs"
                  >
                    Pin
                  </button>
                  <button
                    :if={offer_unpin?(entry.sinker)}
                    type="button"
                    phx-click="unpin"
                    phx-value-id={entry.sinker.id}
                    class="btn btn-xs"
                  >
                    Unpin
                  </button>
                  <button
                    type="button"
                    phx-click="detach"
                    phx-value-id={entry.sinker.id}
                    class="btn btn-xs btn-error btn-soft"
                  >
                    Detach
                  </button>
                </div>
              </div>

              <form id="attach-file-form" phx-submit="attach" class="flex gap-2 pt-1">
                <input
                  type="text"
                  name="path"
                  placeholder="/path/to/file"
                  class="input input-bordered input-sm flex-1"
                />
                <button type="submit" class="btn btn-sm">Attach</button>
              </form>

              <form id="upload-form" phx-change="validate_upload">
                <div
                  phx-drop-target={@uploads.files.ref}
                  class="border-base-300 rounded border border-dashed px-2 py-3 text-center text-xs text-base-content/70"
                >
                  <.live_file_input upload={@uploads.files} class="file-input file-input-sm" />
                  …or drop files here
                </div>
              </form>
            </div>

            <div class="flex gap-2">
              <.button patch={~p"/tickets/#{Ticket.display_ref(@selected)}/edit"} id="edit-ticket">
                Edit
              </.button>
              <.button
                variant="danger"
                phx-click="delete"
                id="delete-ticket"
                data-confirm="Throw this ticket away for good?"
              >
                Delete
              </.button>
            </div>
          </div>

          <p :if={is_nil(@form) && is_nil(@selected)} class="text-base-content/70 text-sm">
            Pick a ticket to see it.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # Shared by both the grouped and flat layouts, so a ticket looks the same
  # row either way — only what surrounds it changes.
  attr :ticket, Ticket, required: true
  attr :selected, :any, required: true

  defp ticket_row(assigns) do
    ~H"""
    <li>
      <.link
        patch={~p"/tickets/#{Ticket.display_ref(@ticket)}"}
        class={[
          "ticket-row hover:bg-base-200 block border-l-2 px-2 py-2",
          if(selected?(@selected, @ticket),
            do: "bg-base-200 border-primary",
            else: "border-transparent"
          )
        ]}
      >
        <span class="block truncate text-sm">{@ticket.title}</span>
        <span class="text-base-content/70 text-xs">
          <span title={Ticket.priority_label(@ticket.priority)}>P{@ticket.priority}</span>
          · {Phoenix.Naming.humanize(@ticket.category)}
        </span>
      </.link>
    </li>
    """
  end
end
