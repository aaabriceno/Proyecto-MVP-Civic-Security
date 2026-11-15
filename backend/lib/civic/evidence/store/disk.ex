defmodule Civic.Evidence.Store.Disk do
  @moduledoc """
  Guarda las fotos como archivos en una carpeta del servidor
  (`config :civic, Civic.Evidence, root: ...`).

  Reglas de seguridad:

    * El nombre del archivo sale del id del incidente **ya validado como UUID**:
      jamás de texto que escriba un usuario, así que no hay forma de escapar de la
      carpeta (`../`, rutas absolutas, bytes nulos).
    * La carpeta es `0700` y cada archivo `0600`: solo el usuario del sistema que
      corre el programa puede leerlos.
    * Se escribe a un archivo temporal y se publica con un enlace duro, que falla
      si el destino ya existe: dos subidas a la vez no se pisan y nadie lee una foto
      a medio escribir.
  """

  @behaviour Civic.Evidence.Store

  # Sobelow avisa de "Directory Traversal" en cada operación de archivo porque la
  # ruta se arma con una variable. Aquí no es explotable: el nombre sale de un UUID
  # ya validado a 36 caracteres (`Store.cast_id/1`, probado contra `../`, rutas
  # absolutas y bytes nulos en disk_store_test.exs) y la carpeta es configuración.

  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  def put(id, binary) when is_binary(binary) do
    with {:ok, uuid} <- cast(id),
         :ok <- ensure_root() do
      final = path(uuid)
      temp = "#{final}.tmp-#{System.unique_integer([:positive])}"

      try do
        with :ok <- File.write(temp, binary, [:binary, :exclusive]),
             :ok <- File.chmod(temp, 0o600) do
          publish(temp, final)
        else
          {:error, _reason} -> {:error, :io}
        end
      after
        File.rm(temp)
      end
    end
  end

  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  def get(id) do
    with {:ok, uuid} <- cast(id) do
      case File.read(path(uuid)) do
        {:ok, binary} -> {:ok, binary}
        {:error, :enoent} -> {:error, :not_found}
        {:error, _reason} -> {:error, :io}
      end
    end
  end

  @impl true
  # sobelow_skip ["Traversal.FileModule"]
  def delete(id) do
    with {:ok, uuid} <- cast(id) do
      case File.rm(path(uuid)) do
        ok when ok in [:ok, {:error, :enoent}] -> :ok
        {:error, _reason} -> {:error, :io}
      end
    end
  end

  # El enlace duro es atómico y falla con :eexist si ya hay una foto
  # sobelow_skip ["Traversal.FileModule"]
  defp publish(temp, final) do
    case File.ln(temp, final) do
      :ok -> :ok
      {:error, :eexist} -> {:error, :exists}
      {:error, _reason} -> {:error, :io}
    end
  end

  defp cast(id) when is_binary(id) do
    case Civic.Evidence.Store.cast_id(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :invalid_id}
    end
  end

  defp cast(_other), do: {:error, :invalid_id}

  defp path(uuid), do: Path.join(root(), uuid <> ".jpg")

  # sobelow_skip ["Traversal.FileModule"]
  defp ensure_root do
    dir = root()

    with :ok <- File.mkdir_p(dir),
         :ok <- File.chmod(dir, 0o700) do
      :ok
    else
      {:error, _reason} -> {:error, :io}
    end
  end

  defp root, do: Application.fetch_env!(:civic, Civic.Evidence)[:root]
end
