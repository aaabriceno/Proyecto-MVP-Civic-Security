defmodule Civic.Evidence.JpegTest do
  use ExUnit.Case, async: true

  import Civic.JpegFixtures

  alias Civic.Evidence.Jpeg

  describe "fotos limpias" do
    test "acepta una foto sin metadatos y dice su tamaño" do
      assert Jpeg.validate(clean()) == {:ok, %{width: 64, height: 48}}
    end

    test "acepta una foto progresiva (varios barridos)" do
      assert Jpeg.validate(fixture("progresiva")) == {:ok, %{width: 64, height: 48}}
    end

    test "los bytes FF dentro de los datos de imagen no se confunden con un marcador" do
      # Si no hubiera FF00 (relleno) en los datos, esta prueba no probaría nada
      assert :binary.match(clean(), <<0xFF, 0x00>>) != :nomatch
      assert {:ok, _} = Jpeg.validate(clean())
    end

    test "los marcadores de reinicio (RST0 a RST7) dentro de los datos son normales" do
      jpeg = clean()
      datos = binary_part(jpeg, 0, byte_size(jpeg) - 2)

      for n <- 0..7 do
        con_reinicio = datos <> <<0xFF, 0xD0 + n, 1, 2, 3, 0xFF, 0xD9>>

        assert {:ok, _} = Jpeg.validate(con_reinicio), "RST#{n}"
      end
    end

    test "acepta el JFIF sin miniatura que escriben todas las cámaras" do
      jfif = <<"JFIF", 0, 1, 1, 0, 0, 1, 0, 1, 0, 0>>

      assert {:ok, _} = Jpeg.validate(clean() |> strip_app0() |> insert_segment(0xE0, jfif))
    end
  end

  describe "metadatos: se rechaza cualquier lugar donde puedan esconderse" do
    test "EXIF con GPS, modelo y fecha del teléfono" do
      assert Jpeg.validate(fixture("con_exif_gps")) == {:error, :has_metadata}
    end

    test "XMP" do
      assert Jpeg.validate(fixture("con_xmp")) == {:error, :has_metadata}
    end

    test "perfil de color ICC" do
      assert Jpeg.validate(fixture("con_icc")) == {:error, :has_metadata}
    end

    test "comentario" do
      assert Jpeg.validate(fixture("con_comentario")) == {:error, :has_metadata}
    end

    test "cualquier segmento APP1 a APP15 (IPTC, Photoshop, MakerNotes...)" do
      for marker <- 0xE1..0xEF do
        jpeg = insert_segment(clean(), marker, "datos")

        assert Jpeg.validate(jpeg) == {:error, :has_metadata},
               "APP#{marker - 0xE0} debió rechazarse"
      end
    end

    test "un JFIF con miniatura incrustada (una foto dentro de la foto)" do
      con_miniatura =
        <<"JFIF", 0, 1, 1, 0, 0, 1, 0, 1, 2, 2, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12>>

      assert Jpeg.validate(clean() |> strip_app0() |> insert_segment(0xE0, con_miniatura)) ==
               {:error, :has_metadata}
    end

    test "una extensión JFXX (miniatura) o un APP0 que no es JFIF" do
      for payload <- [<<"JFXX", 0, 0x10, 1, 2, 3>>, "otra cosa", ""] do
        assert Jpeg.validate(clean() |> strip_app0() |> insert_segment(0xE0, payload)) ==
                 {:error, :has_metadata},
               inspect(payload)
      end
    end
  end

  describe "lo que no es una foto JPEG" do
    test "otros formatos y basura" do
      png = <<0x89, "PNG\r\n", 0x1A, "\n", 0::64>>

      for malo <- [<<>>, "hola", png, "<html><script>alert(1)</script></html>", <<0xFF>>] do
        assert Jpeg.validate(malo) == {:error, :not_jpeg}, inspect(malo)
      end
    end

    test "un archivo cortado a la mitad" do
      jpeg = clean()
      cortado = binary_part(jpeg, 0, div(byte_size(jpeg), 2))

      assert Jpeg.validate(cortado) == {:error, :malformed}
    end

    test "datos pegados después del final (un zip o un script escondido)" do
      assert Jpeg.validate(clean() <> "PK\x03\x04 contenido escondido") ==
               {:error, :trailing_data}
    end

    test "un segmento que dice ser más largo de lo que queda" do
      <<0xFF, 0xD8, rest::binary>> = clean()
      mentiroso = <<0xFF, 0xD8, 0xFF, 0xDB, 0xFF, 0xFF, rest::binary>>

      assert Jpeg.validate(mentiroso) == {:error, :malformed}
    end

    test "un segmento con largo menor a 2" do
      <<0xFF, 0xD8, rest::binary>> = clean()

      assert Jpeg.validate(<<0xFF, 0xD8, 0xFF, 0xDB, 0, 1, rest::binary>>) ==
               {:error, :malformed}
    end

    test "sin datos de imagen (sin barrido)" do
      assert Jpeg.validate(<<0xFF, 0xD8, 0xFF, 0xD9>>) == {:error, :malformed}
    end

    test "con encabezado de imagen pero sin ningún barrido" do
      jpeg = clean()
      {pos, _} = :binary.match(jpeg, <<0xFF, 0xC0>>)
      <<_::binary-size(pos), 0xFF, 0xC0, len::16, _::binary>> = jpeg
      sof = binary_part(jpeg, pos, len + 2)

      assert Jpeg.validate(<<0xFF, 0xD8>> <> sof <> <<0xFF, 0xD9>>) == {:error, :malformed}
    end

    test "con dos encabezados de imagen" do
      jpeg = clean()
      {pos, _} = :binary.match(jpeg, <<0xFF, 0xC0>>)
      <<_::binary-size(pos), 0xFF, 0xC0, len::16, _::binary>> = jpeg
      sof = binary_part(jpeg, pos, len + 2)
      <<head::binary-size(pos), tail::binary>> = jpeg

      assert Jpeg.validate(head <> sof <> tail) == {:error, :malformed}
    end

    test "tipos de JPEG que no usamos (sin pérdida, aritmético, jerárquico)" do
      for marker <- [0xC3, 0xC5, 0xC9, 0xCB, 0xCF] do
        assert Jpeg.validate(patch_sof_marker(clean(), marker)) == {:error, :unsupported},
               Integer.to_string(marker, 16)
      end
    end
  end

  describe "tamaño de la imagen" do
    test "hasta 4096 px por lado" do
      assert {:ok, %{width: 4096, height: 4096}} =
               Jpeg.validate(patch_dimensions(clean(), 4096, 4096))
    end

    test "más de 4096 px de un lado se rechaza (una bomba de descompresión)" do
      for {w, h} <- [{4097, 10}, {10, 4097}, {65_535, 65_535}] do
        assert Jpeg.validate(patch_dimensions(clean(), w, h)) == {:error, :dimensions},
               "#{w}x#{h}"
      end
    end

    test "ancho o alto cero" do
      assert Jpeg.validate(patch_dimensions(clean(), 0, 10)) == {:error, :dimensions}
      assert Jpeg.validate(patch_dimensions(clean(), 10, 0)) == {:error, :dimensions}
    end

    test "el límite se puede cambiar" do
      assert Jpeg.validate(clean(), max_side: 32) == {:error, :dimensions}
    end
  end

  describe "robustez" do
    test "cortada en cualquier punto nunca falla con una excepción, y solo la completa pasa" do
      jpeg = clean()

      for largo <- 0..(byte_size(jpeg) - 1) do
        resultado = Jpeg.validate(binary_part(jpeg, 0, largo))
        assert match?({:error, _}, resultado), "con #{largo} bytes dio #{inspect(resultado)}"
      end

      assert {:ok, _} = Jpeg.validate(jpeg)
    end

    test "basura que empieza como un JPEG nunca falla con una excepción" do
      :rand.seed(:exsss, {1, 2, 3})

      for _ <- 1..300 do
        basura = <<0xFF, 0xD8>> <> :rand.bytes(:rand.uniform(400))
        assert match?({:ok, _}, r = Jpeg.validate(basura)) or match?({:error, _}, r)
      end
    end

    test "dos megabytes de FF no la cuelgan" do
      {micros, resultado} =
        :timer.tc(fn -> Jpeg.validate(<<0xFF, 0xD8>> <> :binary.copy(<<0xFF>>, 2_000_000)) end)

      assert match?({:error, _}, resultado)
      assert micros < 1_000_000
    end
  end

  test "medio millón de barridos mínimos tampoco la cuelgan" do
    jpeg = clean()
    {pos, _} = :binary.match(jpeg, <<0xFF, 0xC0>>)
    <<_::binary-size(pos), 0xFF, 0xC0, len::16, _::binary>> = jpeg
    sof = binary_part(jpeg, pos, len + 2)
    abuso = <<0xFF, 0xD8>> <> sof <> :binary.copy(<<0xFF, 0xDA, 0, 2>>, 500_000) <> <<0xFF, 0xD9>>

    {micros, resultado} = :timer.tc(fn -> Jpeg.validate(abuso) end)

    # Un barrido sin datos es válido para el validador (no decodifica): lo que se
    # prueba es que el tiempo no crece de forma cuadrática
    assert match?({:ok, _}, resultado) or match?({:error, _}, resultado)
    assert micros < 1_000_000
  end

  # La foto limpia ya trae un JFIF; para probar otros APP0 hay que quitárselo
  defp strip_app0(<<0xFF, 0xD8, 0xFF, 0xE0, len::16, _::binary-size(len - 2), rest::binary>>),
    do: <<0xFF, 0xD8, rest::binary>>
end
