defmodule Civic.Incidents.Bbox do
  @moduledoc """
  Rectángulo geográfico (bounding box) que pide el mapa.

  Formato de texto: `"minLng,minLat,maxLng,maxLat"`, por ejemplo
  `"-71.54,-16.40,-71.53,-16.39"`. Se mantiene el orden de PostGIS
  (longitud primero).
  """

  @type t :: {float(), float(), float(), float()}

  @spec parse(term()) :: {:ok, t()} | {:error, :invalid_bbox}
  def parse(texto) when is_binary(texto) do
    with partes = String.split(texto, ","),
         4 <- length(partes),
         {:ok, [min_lng, min_lat, max_lng, max_lat] = numeros} <- parse_floats(partes),
         true <- en_rango?(numeros),
         true <- min_lng < max_lng and min_lat < max_lat do
      {:ok, {min_lng, min_lat, max_lng, max_lat}}
    else
      _ -> {:error, :invalid_bbox}
    end
  end

  def parse(_), do: {:error, :invalid_bbox}

  defp parse_floats(partes) do
    resultado = Enum.map(partes, &parse_float/1)

    if Enum.all?(resultado, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(resultado, fn {:ok, n} -> n end)}
    else
      :error
    end
  end

  # Float.parse devuelve el resto del texto; si sobra algo ("12x") es inválido
  defp parse_float(texto) do
    case Float.parse(String.trim(texto)) do
      {numero, ""} -> {:ok, numero}
      _ -> :error
    end
  end

  defp en_rango?([min_lng, min_lat, max_lng, max_lat]) do
    Enum.all?([min_lng, max_lng], &(&1 >= -180 and &1 <= 180)) and
      Enum.all?([min_lat, max_lat], &(&1 >= -90 and &1 <= 90))
  end
end
