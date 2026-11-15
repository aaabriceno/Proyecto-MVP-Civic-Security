defmodule Civic.Evidence.Jpeg do
  @moduledoc """
  Revisa la **estructura** de una foto JPEG sin decodificarla: que sea un JPEG
  completo y que no lleve metadatos escondidos.

  Una foto de celular trae, sin que se vea, el GPS exacto de quien la tomó, el
  modelo del teléfono y la fecha. La app los quita volviendo a codificar la
  imagen; esta revisión es la **segunda barrera**: no confía en que la app lo
  haya hecho bien (ni en que quien sube la foto use nuestra app).

  Los metadatos de un JPEG viven en segmentos propios (EXIF, XMP, IPTC, perfiles
  de color y comentarios), así que se usa una lista **permitida**: solo pasan los
  segmentos necesarios para dibujar la imagen, y un único `APP0` que sea un JFIF
  mínimo (sin miniatura). Todo lo demás se rechaza, incluso lo que hoy no
  conocemos.

  Lo que NO hace: no detecta rostros ni placas en los píxeles, ni mensajes
  escondidos en los propios datos de imagen (esteganografía).
  """

  @max_side 4096

  @type reason ::
          :not_jpeg
          | :malformed
          | :has_metadata
          | :unsupported
          | :dimensions
          | :trailing_data

  @doc """
  Devuelve `{:ok, %{width: ancho, height: alto}}` o `{:error, motivo}`.

  Opciones: `:max_side` (por defecto 4096 px por lado; protege contra "bombas de
  descompresión": un archivo chico que al abrirlo ocupa gigas de memoria).
  """
  @spec validate(term(), keyword()) ::
          {:ok, %{width: pos_integer(), height: pos_integer()}} | {:error, reason()}
  def validate(binary, opts \\ [])

  def validate(<<0xFF, 0xD8, rest::binary>>, opts) do
    walk(rest, %{dims: nil, scans: 0, max_side: Keyword.get(opts, :max_side, @max_side)})
  end

  def validate(_other, _opts), do: {:error, :not_jpeg}

  # Entre segmentos puede haber bytes FF de relleno. Se descarta uno sin
  # reconstruir el binario (rearmarlo copiaría todo en cada vuelta: con megas de
  # FF seguidos se volvería cuadrático y alguien podría colgar el servidor).
  defp walk(<<0xFF, 0xFF, _::binary>> = binary, state) do
    <<_fill, rest::binary>> = binary
    walk(rest, state)
  end

  # Fin de la imagen: debe haber visto el encabezado y al menos un barrido, y no
  # debe quedar nada después
  defp walk(<<0xFF, 0xD9, rest::binary>>, %{dims: dims, scans: scans}) do
    cond do
      dims == nil or scans == 0 -> {:error, :malformed}
      rest != <<>> -> {:error, :trailing_data}
      true -> {:ok, dims}
    end
  end

  # Encabezado de la imagen: baseline (C0), extendido (C1) o progresivo (C2)
  defp walk(<<0xFF, marker, rest::binary>>, state) when marker in 0xC0..0xC2 do
    with {:ok, payload, rest} <- segment(rest),
         {:ok, dims} <- frame_dimensions(payload, state.max_side),
         true <- state.dims == nil or {:error, :malformed} do
      walk(rest, %{state | dims: dims})
    end
  end

  # Tablas de Huffman (C4), de cuantización (DB) y de reinicio (DD): solo se saltan
  defp walk(<<0xFF, marker, rest::binary>>, state) when marker in [0xC4, 0xDB, 0xDD] do
    with {:ok, _payload, rest} <- segment(rest), do: walk(rest, state)
  end

  # APP0: solo el JFIF mínimo (14 bytes y sin miniatura)
  defp walk(<<0xFF, 0xE0, rest::binary>>, state) do
    case segment(rest) do
      {:ok, <<"JFIF", 0, _version::16, _units, _xdensity::16, _ydensity::16, 0, 0>>, rest} ->
        walk(rest, state)

      {:ok, _otro_app0, _rest} ->
        {:error, :has_metadata}

      error ->
        error
    end
  end

  # APP1 a APP15 (EXIF, XMP, ICC, IPTC, Photoshop...) y comentarios (FE)
  defp walk(<<0xFF, marker, _rest::binary>>, _state) when marker in 0xE1..0xEF or marker == 0xFE,
    do: {:error, :has_metadata}

  # Barrido: encabezado + datos comprimidos hasta el siguiente marcador
  defp walk(<<0xFF, 0xDA, rest::binary>>, %{dims: dims} = state) when dims != nil do
    with {:ok, _payload, rest} <- segment(rest),
         {:ok, rest} <- skip_scan_data(rest) do
      walk(rest, %{state | scans: state.scans + 1})
    end
  end

  # Un barrido sin haber visto el encabezado de la imagen
  defp walk(<<0xFF, 0xDA, _rest::binary>>, _state), do: {:error, :malformed}

  # Cualquier otro marcador conocido (sin pérdida, aritmético, jerárquico,
  # extensiones...): no se usa en fotos de cámara
  defp walk(<<0xFF, marker, _rest::binary>>, _state) when marker >= 0xC3,
    do: {:error, :unsupported}

  # Se acabaron los bytes sin llegar al final de la imagen, o no hay un marcador
  defp walk(_other, _state), do: {:error, :malformed}

  # <<largo::16, contenido>>; el largo cuenta sus propios 2 bytes
  defp segment(<<length::16, rest::binary>>) when length >= 2 do
    size = length - 2

    case rest do
      <<payload::binary-size(size), rest::binary>> -> {:ok, payload, rest}
      _ -> {:error, :malformed}
    end
  end

  defp segment(_other), do: {:error, :malformed}

  # Precisión (8 bits), alto, ancho y número de componentes (1 gris, 3 color)
  defp frame_dimensions(<<8, height::16, width::16, components, _::binary>>, max_side)
       when components in [1, 3] do
    if width in 1..max_side and height in 1..max_side,
      do: {:ok, %{width: width, height: height}},
      else: {:error, :dimensions}
  end

  defp frame_dimensions(_payload, _max_side), do: {:error, :malformed}

  # Los datos comprimidos no tienen marcadores: un FF va seguido de 00 (relleno)
  # o de D0-D7 (reinicio). Cualquier otro FFxx es ya el siguiente marcador.
  defp skip_scan_data(binary) do
    case :binary.match(binary, <<0xFF>>) do
      :nomatch ->
        {:error, :malformed}

      {position, 1} ->
        # Siempre sub-binarios (sin copiar lo que queda)
        <<_data::binary-size(position), at_ff::binary>> = binary

        case at_ff do
          <<0xFF, 0x00, rest::binary>> -> skip_scan_data(rest)
          <<0xFF, marker, rest::binary>> when marker in 0xD0..0xD7 -> skip_scan_data(rest)
          <<0xFF, _marker, _::binary>> -> {:ok, at_ff}
          <<0xFF>> -> {:error, :malformed}
        end
    end
  end
end
