defmodule SinkrWeb.PageController do
  use SinkrWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
