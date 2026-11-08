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

  def me(%{user: %User{} = user}), do: %{data: user_data(user)}

  defp user_data(%User{} = user), do: %{id: user.id, alias: user.alias, nivel: user.nivel}
end
