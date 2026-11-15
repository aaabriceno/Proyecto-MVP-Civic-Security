defmodule Civic.Accounts.Verification do
  @moduledoc """
  Verificación de la cuenta por DNI: "una persona = una cuenta".

  **No se guarda el DNI.** Se calcula `HMAC(k_verif, DNI)` (ver `Civic.Privacy`) y
  solo esa huella queda en la cuenta, con un índice único: si otra cuenta ya la
  tiene, el DNI ya está en uso. El número vive solo en memoria durante la
  petición y Phoenix lo oculta de los logs (`filter_parameters`).

  **Lo que esto NO prueba:** que quien escribe el número sea su titular. Alguien
  puede teclear el DNI de otra persona. Sin consultar a RENIEC (que devolvería el
  nombre y rompería la minimización de datos) lo que garantizamos es que un mismo
  número no abra varias cuentas verificadas. El resto se mitiga con el tope de
  intentos y el aviso en la pantalla de que suplantar es delito.

  **Tope de intentos:** responder "este DNI ya tiene cuenta" revela que esa
  persona usa la app, así que cada cuenta tiene pocos intentos por día
  (`config :civic, Civic.Accounts.Verification`). Como el cupo de reportes, el
  contador vive solo en RAM. Un formato inválido no gasta intentos: no consulta
  nada.
  """

  import Ecto.Query

  alias Civic.Accounts.User
  alias Civic.Privacy
  alias Civic.RateLimit
  alias Civic.Repo

  @type error ::
          :invalid_dni
          | :already_verified
          | :dni_taken
          | :unauthorized
          | {:attempts_exceeded, pos_integer()}

  @doc """
  Verifica `user` con `dni`. Devuelve la cuenta actualizada o un error:

    * `:invalid_dni` – no son exactamente 8 dígitos (no gasta intentos)
    * `:already_verified` – la cuenta ya está verificada; no puede cambiar de DNI
    * `:dni_taken` – ese DNI ya tiene otra cuenta
    * `{:attempts_exceeded, ms}` – se acabaron los intentos del día
    * `:unauthorized` – la cuenta ya no existe
  """
  @spec verify_dni(User.t(), term()) :: {:ok, User.t()} | {:error, error()}
  def verify_dni(%User{nivel: :verificado}, _dni), do: {:error, :already_verified}

  def verify_dni(%User{} = user, dni) do
    with {:ok, %{hash: hash, version: version}} <- Privacy.dni_hash(dni),
         :ok <- consume_attempt(user) do
      save(user, hash, version)
    end
  end

  # La fila se bloquea (FOR UPDATE) y se mira otra vez su nivel: así dos peticiones
  # a la vez de la misma cuenta no la dejan con un DNI y luego con otro. La copia
  # `user` que llega puede estar vieja.
  defp save(user, hash, version) do
    Repo.transaction(fn ->
      case Repo.one(from u in User, where: u.id == ^user.id, lock: "FOR UPDATE") do
        nil -> Repo.rollback(:unauthorized)
        %User{nivel: :verificado} -> Repo.rollback(:already_verified)
        %User{} = current -> mark_verified(current, hash, version)
      end
    end)
  end

  defp mark_verified(current, hash, version) do
    case current |> User.verification_changeset(hash, version) |> Repo.update() do
      {:ok, verified} -> verified
      {:error, %Ecto.Changeset{errors: [verif_hash: _]}} -> Repo.rollback(:dni_taken)
    end
  end

  defp consume_attempt(%User{id: id}) do
    {max, window_ms} = limit()

    case RateLimit.hit({:dni_attempts, id}, window_ms, max) do
      {:allow, _count} -> :ok
      {:deny, retry_ms} -> {:error, {:attempts_exceeded, retry_ms}}
    end
  end

  @doc "Límite `{intentos, ventana_ms}` de verificación por cuenta."
  @spec limit() :: {pos_integer(), pos_integer()}
  def limit do
    :civic
    |> Application.fetch_env!(__MODULE__)
    |> Keyword.fetch!(:dni_attempts)
  end
end
