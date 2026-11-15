defmodule CivicWeb.PhotoController do
  @moduledoc """
  La foto de un reporte: el autor la sube una vez y cualquiera puede verla.

  La foto llega como el cuerpo crudo de la petición con `content-type:
  image/jpeg` (nada de multipart: no escribe archivos temporales y es más simple
  de limitar). Se lee con un tope de `Civic.Evidence.max_bytes/0`.
  """

  use CivicWeb, :controller

  alias Civic.Accounts
  alias Civic.Accounts.User
  alias Civic.Evidence

  action_fallback CivicWeb.FallbackController

  def create(conn, %{"id" => id}) do
    with {:ok, user} <- current_user(conn),
         :ok <- check_content_type(conn),
         :ok <- check_declared_size(conn),
         {:ok, binary, conn} <- read_photo(conn),
         {:ok, incident} <- Evidence.attach_photo(user, id, binary) do
      broadcast_update(incident)

      # Sin `render`: este pipeline no negocia formato (el cuerpo no es JSON)
      conn
      |> put_status(:created)
      |> json(CivicWeb.IncidentJSON.show(%{incident: incident}))
    end
  end

  def show(conn, %{"id" => id}) do
    with {:ok, binary} <- Evidence.fetch_photo(id) do
      conn
      |> put_resp_content_type("image/jpeg", nil)
      |> send_resp(:ok, binary)
    end
  end

  # Para que los demás mapas abiertos vean el reporte con su foto. Es el mismo
  # incidente (mismo id) con `tiene_foto: true`: la app lo reemplaza.
  defp broadcast_update(incident) do
    CivicWeb.Endpoint.broadcast!(
      "mapa:arequipa",
      "incidente_actualizado",
      CivicWeb.IncidentJSON.data(incident)
    )
  end

  # El access token puede seguir vigente (15 min) aunque la cuenta ya se haya borrado
  defp current_user(conn) do
    case Accounts.get_user(conn.assigns.current_user_id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :unauthorized}
    end
  end

  # Solo el tipo, sin parámetros (`; charset=...`) y sin distinguir mayúsculas
  defp check_content_type(conn) do
    with [value | _] <- get_req_header(conn, "content-type"),
         "image/jpeg" <- value |> String.split(";") |> hd() |> String.trim() |> String.downcase() do
      :ok
    else
      _ -> {:error, :unsupported_media_type}
    end
  end

  # Si el encabezado ya dice que es enorme, ni se lee
  defp check_declared_size(conn) do
    with [value | _] <- get_req_header(conn, "content-length"),
         {size, ""} <- Integer.parse(value),
         true <- size > Evidence.max_bytes() do
      {:error, :photo_too_large}
    else
      _ -> :ok
    end
  end

  # `:more` significa que el cuerpo es más grande que el tope
  defp read_photo(conn) do
    case read_body(conn, length: Evidence.max_bytes(), read_timeout: 15_000) do
      {:ok, binary, conn} -> {:ok, binary, conn}
      {:more, _partial, _conn} -> {:error, :photo_too_large}
      {:error, _reason} -> {:error, :photo_too_large}
    end
  end
end
