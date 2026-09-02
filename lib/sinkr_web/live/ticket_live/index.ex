defmodule SinkrWeb.TicketLive.Index do
  @moduledoc """
  The whole dashboard: loose ends grouped by status on the left, whichever one
  you've picked on the right.

  Everything lives in one LiveView rather than an index/show pair, because the
  detail pane sits alongside the list rather than replacing it — picking a
  ticket is a `patch`, not a page load.
  """

  use SinkrWeb, :live_view

  alias Sinkr.Herdr
  alias Sinkr.Herdr.Episode
  alias Sinkr.Tickets
  alias Sinkr.Tickets.Comment
  alias Sinkr.Tickets.Sinker
  alias Sinkr.Tickets.Snapshot
  alias Sinkr.Tickets.Ticket

  @impl true
  def mount(_params, _session, socket) do
    flags = parse_flags(get_connect_params(socket)["flags"])

    # Presence rides PubSub from the poller; the static render and any
    # in-between mount fall back to what the poller last saw. The herdr cog
    # flag never reaches here — hiding chips doesn't stop the ears.
    if connected?(socket), do: Herdr.subscribe()

    {:ok,
     socket
     |> assign(
       category_filter: nil,
       flags: flags,
       workspaces: Herdr.current_workspaces(),
       pins: Herdr.pins()
     )
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
    # Cleared on every navigation; only apply_action(:new, ...) sets it, and
    # only for the visit that arrived via the strip's "Make ticket".
    socket = assign(socket, tether_workspace: nil)

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, selected: nil, editing: nil, form: nil)
  end

  defp apply_action(socket, :show, %{"ref" => ref}) do
    ticket = Tickets.get_ticket_by_ref!(ref)

    socket
    |> assign(selected: ticket, editing: nil, form: nil)
    |> load_episodes()
    |> load_comments()
    |> reset_composer()
    |> load_file_entries()
    # Folded is the arrival default for a crowd of files; decided once per
    # ticket-open so attaching another file can't yank the section shut
    # under the cursor.
    |> then(&assign(&1, files_open: length(&1.assigns.file_entries) <= 1))
  end

  # The strip's "Make ticket" arrives here carrying the workspace's label as
  # the title and the workspace itself to tether once the ticket exists. A
  # workspace that closed in the meantime just means a plain new-ticket form.
  defp apply_action(socket, :new, params) do
    workspace =
      Enum.find(socket.assigns.workspaces, &(&1.workspace_id == params["workspace"]))

    socket
    |> assign(tether_workspace: workspace)
    |> open_form(%Ticket{title: params["title"]}, nil)
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

    {:noreply,
     socket |> assign(selected: updated) |> load_tickets() |> flash_then_clear("Saved.")}
  end

  def handle_event("set_priority", %{"priority" => priority}, socket) do
    {:ok, updated} = Tickets.update_ticket(socket.assigns.selected, %{priority: priority})

    {:noreply,
     socket |> assign(selected: updated) |> load_tickets() |> flash_then_clear("Saved.")}
  end

  def handle_event("add_comment", %{"comment" => params}, socket) do
    case Tickets.add_comment(socket.assigns.selected, params) do
      {:ok, _comment} ->
        {:noreply, socket |> load_comments() |> reset_composer() |> flash_then_clear("Saved.")}

      {:error, _changeset} ->
        {:noreply, socket}
    end
  end

  def handle_event("edit_comment", %{"id" => id}, socket) do
    comment = Tickets.get_comment!(id)

    {:noreply,
     assign(socket,
       editing_comment: comment.id,
       comment_edit_form: to_form(%{"body" => comment.body}, as: :comment)
     )}
  end

  def handle_event("cancel_edit_comment", _params, socket) do
    {:noreply, assign(socket, editing_comment: nil, comment_edit_form: nil)}
  end

  def handle_event("update_comment", %{"comment" => params}, socket) do
    comment = Tickets.get_comment!(socket.assigns.editing_comment)

    case Tickets.update_comment(comment, params) do
      {:ok, _comment} -> {:noreply, socket |> load_comments() |> flash_then_clear("Saved.")}
      {:error, _changeset} -> {:noreply, socket}
    end
  end

  def handle_event("delete_comment", %{"id" => id}, socket) do
    {:ok, _comment} = Tickets.delete_comment(Tickets.get_comment!(id))

    {:noreply, load_comments(socket)}
  end

  def handle_event("tether", %{"workspace_id" => workspace_id, "ref" => ref}, socket) do
    case Enum.find(socket.assigns.workspaces, &(&1.workspace_id == workspace_id)) do
      nil ->
        {:noreply, put_flash(socket, :error, "That workspace has gone away.")}

      workspace ->
        {:noreply, tether(socket, Tickets.get_ticket_by_ref!(ref), workspace)}
    end
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
      {:ok, ticket} ->
        socket
        |> maybe_tether_newborn(ticket)
        |> saved(ticket, "Opened.")

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save(socket, %Ticket{} = ticket, params) do
    case Tickets.update_ticket(ticket, params) do
      {:ok, updated} -> saved(socket, updated, "Saved.")
      {:error, changeset} -> {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # A ticket born from the strip tethers its workspace the moment it exists.
  defp maybe_tether_newborn(%{assigns: %{tether_workspace: nil}} = socket, _ticket), do: socket

  defp maybe_tether_newborn(%{assigns: %{tether_workspace: workspace}} = socket, ticket) do
    tether(socket, ticket, workspace)
  end

  defp tether(socket, ticket, workspace) do
    {:ok, outcome} = Herdr.tether(ticket, workspace)

    # The rename only shows once the poller looks again; ask it to, now,
    # instead of letting the strip look stale for a whole interval.
    Herdr.poll_now()

    message =
      case outcome do
        :renamed -> "Tethered."
        :pinned -> "Rename refused — pinned instead."
      end

    socket |> assign(pins: Herdr.pins()) |> flash_then_clear(message)
  end

  defp saved(socket, ticket, message) do
    {:noreply,
     socket
     |> load_tickets()
     |> flash_then_clear(message)
     |> push_patch(to: ~p"/tickets/#{Ticket.display_ref(ticket)}")}
  end

  # Confirmation, not furniture: the flash announces the save, then clears
  # itself instead of parking on screen until clicked.
  defp flash_then_clear(socket, message) do
    Process.send_after(self(), :clear_flash, 3_000)
    put_flash(socket, :info, message)
  end

  @impl true
  def handle_info(:clear_flash, socket), do: {:noreply, clear_flash(socket)}

  def handle_info({:herdr_workspaces, workspaces}, socket) do
    socket = assign(socket, workspaces: workspaces)

    # The tick that moved the chips also moved episode rows; an open detail
    # pane's history should say the same thing the chips do.
    {:noreply, if(socket.assigns.selected, do: load_episodes(socket), else: socket)}
  end

  defp load_tickets(socket) do
    all = Tickets.list_tickets()

    visible =
      all
      |> filter_by_category(socket.assigns.category_filter)
      |> filter_by_show_done(socket.assigns.flags.show_done)

    assign(socket,
      all_tickets: all,
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

  defp default_flags, do: %{layout: :grouped, show_done: true, herdr: true}

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
  defp merge_flag(flags, "herdr", "true"), do: %{flags | herdr: true}
  defp merge_flag(flags, "herdr", "false"), do: %{flags | herdr: false}
  defp merge_flag(flags, _flag, _to), do: flags

  # Reloading the log closes any in-progress edit — the log changed under it.
  # The composer is deliberately NOT touched here: deleting or editing an old
  # comment shouldn't eat the draft you're typing. Emptying the composer is
  # `reset_composer/1`, called only when a comment lands or the ticket changes.
  defp load_comments(socket) do
    assign(socket,
      comments: Tickets.list_comments(socket.assigns.selected),
      editing_comment: nil,
      comment_edit_form: nil
    )
  end

  # A textarea whose rendered value is "" before and after never re-patches,
  # so a fresh form alone leaves typed text sitting there. The version below
  # keys the textarea's DOM id; a new key is a new node, and a new node is
  # actually empty.
  defp reset_composer(socket) do
    assign(socket,
      comment_form: to_form(%{"body" => ""}, as: :comment),
      composer_version: System.unique_integer([:positive, :monotonic])
    )
  end

  defp load_episodes(socket) do
    assign(socket, episodes: Herdr.episodes_for(socket.assigns.selected))
  end

  defp load_file_entries(socket) do
    assign(socket, file_entries: Tickets.file_entries(socket.assigns.selected))
  end

  defp status_options, do: Enum.map(Ticket.statuses(), &{Phoenix.Naming.humanize(&1), &1})
  defp category_options, do: Enum.map(Ticket.categories(), &{Phoenix.Naming.humanize(&1), &1})

  defp priority_options do
    Enum.map(Ticket.priorities(), fn {level, label} -> {"P#{level} — #{label}", level} end)
  end

  # The chip wears the workspace's agent_status; the tones rhyme with
  # status_tone/1 — working is the green of active, blocked the red of
  # blocked, idle claims no colour at all.
  defp presence_tone(:working), do: "badge-success"
  defp presence_tone(:blocked), do: "badge-error"
  defp presence_tone(:idle), do: "badge-ghost"

  # An empty list when the flag is off, so the row renders chipless without
  # owning the flag logic itself.
  defp presence_for(%{herdr: false}, _ticket, _workspaces, _pins), do: []

  defp presence_for(_flags, ticket, workspaces, pins) do
    Herdr.workspaces_for(ticket, workspaces, pins)
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

      <.untethered_strip
        :if={@flags.herdr}
        workspaces={Herdr.untethered(@workspaces, @pins)}
        tickets={@all_tickets}
      />

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
              presence={presence_for(@flags, ticket, @workspaces, @pins)}
            />
          </ul>

          <details
            :for={{status, tickets} <- @grouped}
            :if={@flags.layout == :grouped}
            open={status != :done}
          >
            <summary class="cursor-pointer select-none">
              <h2 class="text-base-content/60 mb-1 inline-flex items-center gap-2 text-xs font-semibold tracking-wide uppercase">
                <span class={["size-2 rounded-full", status_tone(status)]}></span>
                {Phoenix.Naming.humanize(status)}
                <span class="text-base-content/60 font-normal">{length(tickets)}</span>
              </h2>
            </summary>

            <ul class="divide-base-300 divide-y">
              <.ticket_row
                :for={ticket <- tickets}
                ticket={ticket}
                selected={@selected}
                presence={presence_for(@flags, ticket, @workspaces, @pins)}
              />
            </ul>
          </details>
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

              <div class="flex gap-2 pt-3">
                <.button variant="primary" phx-disable-with="Saving…">Save</.button>
                <.button patch={cancel_path(@editing)}>Cancel</.button>
              </div>
            </.form>
          </div>

          <div :if={is_nil(@form) && @selected} class="space-y-4">
            <h2 class="text-lg leading-snug font-semibold">{@selected.title}</h2>

            <p class="text-base-content/70 flex items-center gap-2 text-xs">
              <span>
                ID: {Ticket.display_ref(@selected)} · Category: {Phoenix.Naming.humanize(
                  @selected.category
                )}
              </span>
              <button
                :if={@flags.herdr}
                type="button"
                data-role="copy-label"
                data-copy={Herdr.suggested_label(@selected)}
                phx-hook=".CopyOnClick"
                id={"copy-label-#{@selected.id}"}
                title="Copy a workspace label for this ticket"
                class="badge badge-xs badge-outline cursor-pointer font-mono"
              >
                {Herdr.suggested_label(@selected)}
              </button>
            </p>

            <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyOnClick">
              export default {
                mounted() {
                  this.el.addEventListener("click", async () => {
                    await navigator.clipboard.writeText(this.el.dataset.copy)
                    const label = this.el.textContent
                    this.el.textContent = "copied!"
                    setTimeout(() => { this.el.textContent = label }, 1000)
                  })
                }
              }
            </script>

            <script :type={Phoenix.LiveView.ColocatedHook} name=".SubmitOnCtrlEnter">
              export default {
                mounted() {
                  this.el.addEventListener("keydown", (e) => {
                    if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
                      e.preventDefault()
                      this.el.form.requestSubmit()
                    }
                  })
                }
              }
            </script>

            <.form for={@comment_form} id="new-comment" phx-submit="add_comment" class="space-y-1">
              <textarea
                id={"new-comment-body-#{@selected.id}-#{@composer_version}"}
                name={@comment_form[:body].name}
                rows="2"
                phx-hook=".SubmitOnCtrlEnter"
                placeholder="What did you find? What's next?"
                class="border-warning bg-warning/10 focus:bg-warning/20 w-full resize-none rounded border-l-2 py-2 pl-3 text-sm outline-none"
              >{Phoenix.HTML.Form.normalize_value("textarea", @comment_form[:body].value)}</textarea>
              <div class="flex justify-end">
                <button type="submit" class="btn btn-xs">Add comment</button>
              </div>
            </.form>

            <ol id="comments" class="space-y-2">
              <li
                :for={comment <- @comments}
                id={"comment-#{comment.id}"}
                class="border-base-300 border-l-2 pl-3"
              >
                <.form
                  :if={@editing_comment == comment.id}
                  for={@comment_edit_form}
                  id={"edit-comment-#{comment.id}"}
                  phx-submit="update_comment"
                  class="space-y-1"
                >
                  <textarea
                    id={"edit-comment-body-#{comment.id}"}
                    name={@comment_edit_form[:body].name}
                    rows="3"
                    phx-hook=".SubmitOnCtrlEnter"
                    class="border-warning bg-warning/10 focus:bg-warning/20 w-full resize-none rounded border-l-2 py-2 pl-3 text-sm outline-none"
                  >{Phoenix.HTML.Form.normalize_value("textarea", @comment_edit_form[:body].value)}</textarea>
                  <div class="flex justify-end gap-1">
                    <button type="button" phx-click="cancel_edit_comment" class="btn btn-xs btn-ghost">
                      Cancel
                    </button>
                    <button type="submit" class="btn btn-xs">Save</button>
                  </div>
                </.form>

                <div :if={@editing_comment != comment.id}>
                  <p class="text-sm whitespace-pre-wrap">{comment.body}</p>
                  <div class="text-base-content/60 flex items-center justify-between text-xs">
                    <span>
                      {Comment.stamp(comment)}
                      <span :if={Comment.edited?(comment)}>
                        · edited {Comment.edited_stamp(comment)}
                      </span>
                    </span>
                    <div class="flex gap-1">
                      <button
                        type="button"
                        phx-click="edit_comment"
                        phx-value-id={comment.id}
                        class="btn btn-xs btn-ghost"
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        phx-click="delete_comment"
                        phx-value-id={comment.id}
                        data-confirm="Take this comment off the ticket?"
                        class="btn btn-xs btn-ghost"
                      >
                        Remove
                      </button>
                    </div>
                  </div>
                </div>
              </li>
            </ol>

            <div class="grid grid-cols-2 gap-2">
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

              <form phx-change="set_priority" id="quick-priority">
                <.input
                  type="select"
                  id="quick-priority-select"
                  name="priority"
                  label="Priority"
                  value={@selected.priority}
                  options={priority_options()}
                />
              </form>
            </div>

            <details id="files-section" open={@files_open} class="space-y-2">
              <summary class="cursor-pointer select-none">
                <h3 class="text-base-content/60 inline-flex text-xs font-semibold tracking-wide uppercase">
                  Files ({length(@file_entries)})
                </h3>
              </summary>

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
                    data-confirm="Take this file off the ticket?"
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
                  required
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
            </details>

            <details
              :if={@flags.herdr && @episodes != []}
              id="history-section"
              class="space-y-2"
            >
              <summary class="cursor-pointer select-none">
                <h3 class="text-base-content/60 inline-flex text-xs font-semibold tracking-wide uppercase">
                  History ({length(@episodes)})
                </h3>
              </summary>

              <div
                :for={episode <- @episodes}
                data-role="episode"
                class="border-base-300 flex items-center justify-between gap-2 rounded border px-2 py-1.5 text-sm"
              >
                <span class="truncate" title={episode.workspace_id}>{episode.label}</span>
                <span class="text-base-content/60 shrink-0 text-xs">
                  {Episode.first_seen_stamp(episode)} → {Episode.last_seen_stamp(episode)}
                </span>
              </div>
            </details>

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

  # Workspaces belonging to no ticket, kept apart from the ticket list. Two
  # ways out, both ending in a rename so the label stays the source of
  # truth: become a new ticket, or attach to one that exists.
  attr :workspaces, :list, required: true
  attr :tickets, :list, required: true, doc: "every ticket, for the attach select"

  defp untethered_strip(assigns) do
    ~H"""
    <section :if={@workspaces != []} id="untethered-strip" class="space-y-2">
      <h2 class="text-base-content/60 text-xs font-semibold tracking-wide uppercase">
        Untethered <span class="font-normal">{length(@workspaces)}</span>
      </h2>

      <div class="flex flex-wrap gap-2">
        <div
          :for={workspace <- @workspaces}
          id={"untethered-#{workspace.workspace_id}"}
          class="border-base-300 flex items-center gap-2 rounded border px-2 py-1.5 text-sm"
        >
          <span class={["badge badge-xs", presence_tone(workspace.agent_status)]}>
            {workspace.agent_status}
          </span>
          <span class="max-w-48 truncate" title={workspace.label}>{workspace.label}</span>

          <.link
            patch={~p"/tickets/new?#{[title: workspace.label, workspace: workspace.workspace_id]}"}
            class="btn btn-xs"
          >
            Make ticket
          </.link>

          <form
            phx-submit="tether"
            id={"tether-#{workspace.workspace_id}"}
            class="flex items-center gap-1"
          >
            <input type="hidden" name="workspace_id" value={workspace.workspace_id} />
            <select name="ref" class="select select-xs w-40">
              <option :for={ticket <- @tickets} value={Ticket.display_ref(ticket)}>
                {Ticket.display_ref(ticket)} · {ticket.title}
              </option>
            </select>
            <button type="submit" class="btn btn-xs">Attach</button>
          </form>
        </div>
      </div>
    </section>
    """
  end

  # Shared by both the grouped and flat layouts, so a ticket looks the same
  # row either way — only what surrounds it changes.
  attr :ticket, Ticket, required: true
  attr :selected, :any, required: true
  attr :presence, :list, required: true, doc: "workspaces wearing this ticket's ref right now"

  defp ticket_row(assigns) do
    ~H"""
    <li id={"ticket-#{@ticket.id}"}>
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
        <span class="flex items-center gap-1.5 text-sm">
          <span class="truncate">{@ticket.title}</span>
          <span
            :for={workspace <- @presence}
            data-role="presence"
            title={workspace.label}
            class={["badge badge-xs shrink-0", presence_tone(workspace.agent_status)]}
          >
            {workspace.agent_status}
          </span>
        </span>
        <span class="text-base-content/70 text-xs">
          <span title={Ticket.priority_label(@ticket.priority)}>P{@ticket.priority}</span>
          · {Phoenix.Naming.humanize(@ticket.category)}
        </span>
      </.link>
    </li>
    """
  end
end
