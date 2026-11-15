defmodule CivicWeb.AuthJSON do
  @moduledoc """
  Serialización de las respuestas de cuentas. De la cuenta solo se expone
  `id`, `alias` y `nivel`: nunca el hash de la contraseña ni los contadores.
  """

  alias Civic.Accounts.User

  def session(%{user: %User{} = user, tokens: tokens}) do
    %{data: Map.put(tokens, :user, user_data(user))}
  end

  def tokens(%{tokens: tokens}), do: %{data: tokens}

  # El perfil de quien pregunta: además de lo básico, desde cuándo existe la cuenta
  # (solo año y mes) y cuánto lleva gastado del cupo diario de reportes
  def me(%{user: %User{} = user, cupo: cupo}) do
    %{
      data:
        user
        |> user_data()
        |> Map.merge(%{desde: Calendar.strftime(user.inserted_at, "%Y-%m"), cupo: cupo})
    }
  end

  defp user_data(%User{} = user), do: %{id: user.id, alias: user.alias, nivel: user.nivel}
end
