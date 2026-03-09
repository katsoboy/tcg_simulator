defmodule TcgSimulatorWeb.PageController do
  use TcgSimulatorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
