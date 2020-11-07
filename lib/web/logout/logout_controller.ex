defmodule CommonsPub.Me.Web.LogoutController do

  use CommonsPub.WebPhoenix, [:controller]

  def index(conn, _) do
    conn |>
    logout()
  end


  defp logout(conn) do
    conn
    |> put_session(:account_id, nil)
    |> redirect(to: "/")
  end

end