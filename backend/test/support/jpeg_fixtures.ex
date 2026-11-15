defmodule Civic.JpegFixtures do
  @moduledoc """
  Fotos de prueba. Las de `test/support/fixtures/jpeg/` son JPEG reales (hechos
  con Pillow y exiftool): una limpia y varias con metadatos escondidos en
  distintos lugares. Los ayudantes de abajo fabrican variantes rotas a partir de
  la limpia.
  """

  @dir Path.join([__DIR__, "fixtures", "jpeg"])

  @doc "Lee una foto de prueba por nombre, p. ej. `\"limpia\"`."
  def fixture(name), do: File.read!(Path.join(@dir, name <> ".jpg"))

  @doc "Una foto sin metadatos (64×48, con ruido para que haya bytes FF en los datos)."
  def clean, do: fixture("limpia")

  @doc """
  Mete un segmento `marcador` con `payload` justo después del `FFD8` inicial.
  Sirve para probar cualquier segmento (APP13 de IPTC, APP0 con miniatura...).
  """
  def insert_segment(<<0xFF, 0xD8, rest::binary>>, marker, payload) do
    <<0xFF, 0xD8, 0xFF, marker, byte_size(payload) + 2::16, payload::binary, rest::binary>>
  end

  @doc "Cambia el ancho y el alto declarados en el primer segmento SOF."
  def patch_dimensions(jpeg, width, height) do
    {pos, _} = :binary.match(jpeg, <<0xFF, 0xC0>>)

    <<head::binary-size(pos), 0xFF, 0xC0, len::16, precision, _h::16, _w::16, rest::binary>> =
      jpeg

    <<head::binary, 0xFF, 0xC0, len::16, precision, height::16, width::16, rest::binary>>
  end

  @doc "Cambia el marcador del primer SOF (p. ej. de C0 a C3, JPEG sin pérdida)."
  def patch_sof_marker(jpeg, new_marker) do
    {pos, _} = :binary.match(jpeg, <<0xFF, 0xC0>>)
    <<head::binary-size(pos), 0xFF, 0xC0, rest::binary>> = jpeg
    <<head::binary, 0xFF, new_marker, rest::binary>>
  end
end
