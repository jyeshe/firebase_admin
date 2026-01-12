defmodule FirebaseAuth.Plug do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        case FirebaseAdmin.verify_token(token) do
          {:ok, claims} ->
            conn
            |> assign(:current_user_id, claims["sub"])
            |> assign(:firebase_claims, claims)

          {:error, _reason} ->
            conn
            |> put_status(:unauthorized)
            |> halt()
        end

      _ ->
        conn
        |> put_status(:unauthorized)
        |> halt()
    end
  end
end
