defmodule Civic.Evidence.Store do
  @moduledoc """
  Dónde viven los archivos de las fotos. Es un contrato para poder cambiar el
  almacenamiento sin tocar el resto: hoy `Civic.Evidence.Store.Disk` (una carpeta
  del servidor); para la nube, otro módulo que guarde en un bucket (R2/S3).

  Cada foto se identifica por el id del incidente al que pertenece, y **no se
  puede reemplazar**: la primera que se guarda es la que queda.
  """

  @type id :: String.t()

  @callback put(id(), binary()) :: :ok | {:error, :exists | :invalid_id | :io}
  @callback get(id()) :: {:ok, binary()} | {:error, :not_found | :invalid_id | :io}
  @callback delete(id()) :: :ok | {:error, :invalid_id | :io}

  @doc """
  El id en su forma canónica (minúsculas) o `:error` si no es un UUID en su forma
  de texto (36 caracteres con guiones).

  Ojo: `Ecto.UUID.cast/1` también acepta cualquier texto de **16 bytes** como un
  UUID "en crudo" (`"../../etc/passwd"` mide justo 16), así que aquí se exige el
  largo de la forma de texto antes de usarlo.
  """
  @spec cast_id(term()) :: {:ok, id()} | :error
  def cast_id(id) when is_binary(id) and byte_size(id) == 36, do: Ecto.UUID.cast(id)
  def cast_id(_other), do: :error
end
