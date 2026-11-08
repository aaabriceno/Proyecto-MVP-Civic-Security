defmodule Civic.Accounts.Password do
  @moduledoc """
  Política, hash y verificación de contraseñas.

  **Nunca se guarda la contraseña**, solo su hash Argon2id. Un hash de contraseña
  tiene que ser *lento a propósito* y gastar memoria: así, si se filtra la base,
  adivinar cada contraseña le cuesta caro al atacante. Por eso NO se usa SHA-256
  ni HMAC aquí (son rápidos: una GPU prueba miles de millones por segundo).
  Argon2 agrega además una sal aleatoria por cuenta, que queda dentro del propio
  texto del hash.

  Reglas (NIST 800-63B): largo mínimo, sin reglas de composición ("una
  mayúscula, un símbolo..." empuja a contraseñas peores), y se normaliza el
  Unicode para que la misma contraseña funcione sin importar cómo la escriba
  el teclado.
  """

  @min_length 12
  @max_length 128
  # Un "carácter" Unicode puede ocupar muchos bytes; este tope evita abusos
  @max_bytes 512
  @min_distinct 5
  # Caracteres de control ASCII (incluido NUL) y de control C1
  @control ~r/[\x00-\x1F\x7F-\x9F]/u

  @doc """
  Forma canónica NFKC: "ñ" escrita como un solo carácter o como "n" + tilde
  combinada da el mismo resultado. Un texto que no es UTF-8 válido se deja
  igual (la validación lo rechaza).
  """
  @spec normalize(binary()) :: binary()
  def normalize(password) when is_binary(password) do
    if String.valid?(password), do: :unicode.characters_to_nfkc_binary(password), else: password
  end

  @doc "Mensajes de error de una contraseña nueva (lista vacía si es válida)."
  @spec errors(binary(), binary() | nil) :: [String.t()]
  def errors(password, alias_) when is_binary(password) do
    if String.valid?(password) do
      length = String.length(password)

      Enum.filter(
        [
          length < @min_length and "debe tener al menos #{@min_length} caracteres",
          (length > @max_length or byte_size(password) > @max_bytes) and
            "debe tener como máximo #{@max_length} caracteres",
          Regex.match?(@control, password) and "no puede tener caracteres de control",
          contains_alias?(password, alias_) and "no puede contener tu alias",
          too_simple?(password) and "es demasiado simple"
        ],
        &is_binary/1
      )
    else
      ["no es un texto válido"]
    end
  end

  @doc "Hash Argon2id (con sal aleatoria) de una contraseña ya validada."
  @spec hash(binary()) :: String.t()
  def hash(password), do: password |> normalize() |> Argon2.hash_pwd_salt()

  @doc "¿La contraseña corresponde al hash? Compara en tiempo constante."
  @spec valid?(binary(), binary()) :: boolean()
  def valid?(password, hash), do: password |> normalize() |> Argon2.verify_pass(hash)

  @doc """
  Hace el mismo trabajo que `valid?/2` sin que exista la cuenta. Así, un alias
  inexistente tarda lo mismo en responder que uno real y no se puede averiguar
  qué alias existen midiendo el tiempo.
  """
  @spec no_user_verify() :: false
  def no_user_verify, do: Argon2.no_user_verify()

  defp contains_alias?(_password, alias_) when not is_binary(alias_) or alias_ == "", do: false

  defp contains_alias?(password, alias_),
    do: String.contains?(String.downcase(password), String.downcase(alias_))

  # "aaaaaaaaaaaa" o "abababababab": largas pero triviales de adivinar
  defp too_simple?(password),
    do: password |> String.graphemes() |> Enum.uniq() |> length() < @min_distinct
end
