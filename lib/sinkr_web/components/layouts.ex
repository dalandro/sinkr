defmodule SinkrWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SinkrWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :flags, :map,
    default: %{layout: :grouped, show_done: true, herdr: true, design: :classic},
    doc: "view preferences the cog menu offers; see SinkrWeb.TicketLive.Index"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar border-base-300 border-b px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="text-base font-semibold tracking-tight">sinkr</a>
      </div>
      <div class="flex-none flex items-center gap-2">
        <.cog_menu flags={@flags} />
        <.theme_toggle />
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-6xl space-y-4">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end

  @doc """
  The cog menu of view preferences: layout and show-done round-trip through
  `set_flag` on the parent LiveView; density and thumbnails never leave the
  client. See the pre-paint script in root.html.heex for the client half.
  """
  attr :flags, :map, required: true

  def cog_menu(assigns) do
    ~H"""
    <div class="dropdown dropdown-end">
      <div
        tabindex="0"
        role="button"
        aria-label="View options"
        class="btn btn-ghost btn-circle btn-sm"
      >
        <.icon name="hero-cog-6-tooth-micro" class="size-4 opacity-75 hover:opacity-100" />
      </div>

      <div
        id="cog-menu"
        tabindex="0"
        class="dropdown-content menu bg-base-100 border-base-300 z-10 mt-2 w-56 gap-3 rounded-box border p-3 shadow"
      >
        <.flag_row
          label="Layout"
          flag="layout"
          server
          options={[
            {"Grouped", "grouped", @flags.layout == :grouped},
            {"Flat", "flat", @flags.layout == :flat}
          ]}
        />
        <.flag_row
          label="Done"
          flag="show_done"
          server
          options={[
            {"Show", "true", @flags.show_done},
            {"Hide", "false", !@flags.show_done}
          ]}
        />
        <.flag_row
          label="Presence"
          flag="herdr"
          server
          options={[
            {"Show", "true", @flags.herdr},
            {"Hide", "false", !@flags.herdr}
          ]}
        />
        <.flag_row
          label="Design"
          flag="design"
          server
          options={[
            {"Classic", "classic", @flags.design == :classic},
            {"Calm", "calm", @flags.design == :calm}
          ]}
        />
        <.flag_row
          label="Density"
          flag="density"
          options={[
            {"Cozy", "cozy", "[[data-density=cozy]_&]:btn-primary"},
            {"Compact", "compact", "[[data-density=compact]_&]:btn-primary"}
          ]}
        />
        <.flag_row
          label="Thumbnails"
          flag="thumbs"
          options={[
            {"On", "on", "[[data-thumbs=on]_&]:btn-primary"},
            {"Off", "off", "[[data-thumbs=off]_&]:btn-primary"}
          ]}
        />
      </div>
    </div>
    """
  end

  # One row of the cog menu. A server flag's button also pushes `set_flag`
  # (via its phx-value-* attrs); a client flag's active look can't come from
  # an assign the server doesn't have, so its options carry a literal
  # `[[data-x=y]_&]:` class — literal so Tailwind's scanner sees it.
  attr :label, :string, required: true
  attr :flag, :string, required: true
  attr :server, :boolean, default: false
  attr :options, :list, required: true, doc: "{label, value, active-boolean-or-class} tuples"

  defp flag_row(assigns) do
    ~H"""
    <div>
      <span class="text-base-content/60 mb-1 block text-xs font-semibold tracking-wide uppercase">
        {@label}
      </span>
      <div class="join">
        <button
          :for={{label, to, active} <- @options}
          type="button"
          phx-click={
            if @server,
              do: JS.dispatch("sinkr:set-flag") |> JS.push("set_flag"),
              else: JS.dispatch("sinkr:set-flag")
          }
          phx-value-flag={if @server, do: @flag}
          phx-value-to={if @server, do: to}
          data-flag={@flag}
          data-to={to}
          class={[
            "btn btn-xs join-item",
            active == true && "btn-primary",
            is_binary(active) && active
          ]}
        >
          {label}
        </button>
      </div>
    </div>
    """
  end
end
