defmodule Civic.Evidence do
  @moduledoc """
  La foto opcional de un reporte.

  Qué se garantiza:

    * **Solo el autor** puede subirla (se recalcula su código de autor; ver
      `Civic.Privacy.reporter_token/2`), **una vez**: la primera que llega es la que
      queda.
    * **Sin metadatos.** La app quita el GPS, el modelo del teléfono y la fecha al
      volver a codificar la imagen, y aquí se vuelve a comprobar (`Civic.Evidence.Jpeg`)
      sin confiar en la app.
    * **Todo o nada.** O queda el archivo y la marca `tiene_foto`, o ninguno de los
      dos. Dos subidas a la vez no se pisan.
    * La foto de un reporte **descartado** no se muestra.

  Qué NO se garantiza: que el servidor no vea la foto. Como se muestra en el mapa
  público, el servidor la lee; solo se protege el camino (TLS) y el
  almacenamiento (cifrado en reposo del proveedor). Tampoco se detectan rostros
  ni placas.

  El archivo vive en un `Civic.Evidence.Store` (disco hoy, un bucket mañana).
  """

  import Ecto.Query

  alias Civic.Accounts.User
  alias Civic.Evidence.{Jpeg, Store}
  alias Civic.Incidents.Incident
  alias Civic.Privacy
  alias Civic.Repo

  # Una foto de 1280 px en JPEG pesa ~150 KB; 2 MB deja de sobra
  @max_bytes 2 * 1024 * 1024

  @type error ::
          :not_found
          | :not_author
          | :photo_exists
          | :photo_too_large
          | :storage
          | {:invalid_photo, Jpeg.reason()}

  @doc "Tamaño máximo de una foto, en bytes."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc """
  Guarda la foto del incidente `incident_id` si `user` es su autor.

  Devuelve el incidente ya marcado con `tiene_foto: true`. La opción `:store`
  cambia el almacenamiento (solo para pruebas).
  """
  @spec attach_photo(User.t(), term(), binary(), keyword()) ::
          {:ok, Incident.t()} | {:error, error()}
  def attach_photo(%User{} = user, incident_id, binary, opts \\ []) when is_binary(binary) do
    store = Keyword.get_lazy(opts, :store, &store/0)

    with :ok <- check_size(binary),
         {:ok, incident} <- find(incident_id),
         :ok <- check_author(incident, user),
         :ok <- check_photo(binary) do
      claim_and_store(incident, binary, store)
    end
  end

  @doc """
  Los bytes de la foto de un incidente, o `{:error, :not_found}` si no existe,
  no tiene foto, o el reporte fue descartado.
  """
  @spec fetch_photo(term()) :: {:ok, binary()} | {:error, :not_found}
  def fetch_photo(incident_id) do
    with {:ok, id} <- Store.cast_id(incident_id),
         %Incident{tiene_foto: true, estado: estado} when estado != :descartado <-
           Repo.get(Incident, id),
         {:ok, binary} <- store().get(id) do
      {:ok, binary}
    else
      _ -> {:error, :not_found}
    end
  end

  defp check_size(binary) when byte_size(binary) > @max_bytes, do: {:error, :photo_too_large}
  defp check_size(_binary), do: :ok

  # Un reporte descartado ya no recibe fotos
  defp find(incident_id) do
    with {:ok, id} <- Store.cast_id(incident_id),
         %Incident{estado: estado} = incident when estado != :descartado <-
           Repo.get(Incident, id) do
      {:ok, incident}
    else
      _ -> {:error, :not_found}
    end
  end

  # Se recalcula el código del autor y se compara en tiempo constante. Un reporte
  # sin autor (token nulo) no es de nadie.
  defp check_author(%Incident{reporter_token: token, id: id}, %User{id: user_id})
       when is_binary(token) do
    if Privacy.same_token?(token, Privacy.reporter_token(user_id, id)),
      do: :ok,
      else: {:error, :not_author}
  end

  defp check_author(_incident, _user), do: {:error, :not_author}

  defp check_photo(binary) do
    case Jpeg.validate(binary) do
      {:ok, _dimensions} -> :ok
      {:error, reason} -> {:error, {:invalid_photo, reason}}
    end
  end

  # Primero se reclama la marca (el UPDATE bloquea la fila: una segunda subida
  # espera y ve `tiene_foto` en true) y luego se guarda el archivo. Si el archivo
  # falla, se deshace la marca.
  defp claim_and_store(%Incident{id: id}, binary, store) do
    result =
      Repo.transaction(fn ->
        {claimed, _} =
          Repo.update_all(
            from(i in Incident, where: i.id == ^id and i.tiene_foto == false),
            set: [tiene_foto: true]
          )

        if claimed == 0, do: Repo.rollback(:photo_exists)

        case put(store, id, binary) do
          :ok -> :ok
          {:error, :io} -> Repo.rollback(:storage)
        end
      end)

    case result do
      {:ok, :ok} -> {:ok, Repo.get!(Incident, id)}
      {:error, reason} -> {:error, reason}
    end
  end

  # La base manda: si la marca estaba apagada, un archivo que ya existe es un
  # huérfano de un intento anterior que no llegó a confirmarse
  defp put(store, id, binary) do
    case store.put(id, binary) do
      :ok ->
        :ok

      {:error, :exists} ->
        _ = store.delete(id)
        if store.put(id, binary) == :ok, do: :ok, else: {:error, :io}

      {:error, _reason} ->
        {:error, :io}
    end
  end

  defp store, do: Application.fetch_env!(:civic, __MODULE__)[:store]
end
