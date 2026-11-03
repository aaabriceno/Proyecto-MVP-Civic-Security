defmodule Civic.Incidents.BboxTest do
  use ExUnit.Case, async: true

  alias Civic.Incidents.Bbox

  test "parsea un bbox válido en el orden minLng,minLat,maxLng,maxLat" do
    assert {:ok, {-71.54, -16.40, -71.53, -16.39}} =
             Bbox.parse("-71.54,-16.40,-71.53,-16.39")
  end

  test "acepta enteros" do
    assert {:ok, {-72.0, -17.0, -71.0, -16.0}} = Bbox.parse("-72,-17,-71,-16")
  end

  test "rechaza una cantidad de números distinta de 4" do
    assert {:error, :invalid_bbox} = Bbox.parse("-71.54,-16.40,-71.53")
    assert {:error, :invalid_bbox} = Bbox.parse("1,2,3,4,5")
  end

  test "rechaza texto que no es número" do
    assert {:error, :invalid_bbox} = Bbox.parse("a,b,c,d")
    assert {:error, :invalid_bbox} = Bbox.parse("-71.5x,-16.4,-71.4,-16.3")
  end

  test "rechaza min mayor o igual que max" do
    assert {:error, :invalid_bbox} = Bbox.parse("-71.53,-16.40,-71.54,-16.39")
    assert {:error, :invalid_bbox} = Bbox.parse("-71.54,-16.39,-71.53,-16.40")
    assert {:error, :invalid_bbox} = Bbox.parse("-71.5,-16.4,-71.5,-16.3")
  end

  test "rechaza coordenadas fuera de rango" do
    assert {:error, :invalid_bbox} = Bbox.parse("-200,-16.4,-71.5,-16.3")
    assert {:error, :invalid_bbox} = Bbox.parse("-71.6,-95,-71.5,-16.3")
  end

  test "rechaza nil y valores que no son texto" do
    assert {:error, :invalid_bbox} = Bbox.parse(nil)
    assert {:error, :invalid_bbox} = Bbox.parse(["a"])
  end
end
