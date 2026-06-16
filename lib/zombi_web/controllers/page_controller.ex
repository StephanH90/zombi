defmodule ZombiWeb.PageController do
  use ZombiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
