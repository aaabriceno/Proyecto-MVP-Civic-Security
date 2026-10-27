defmodule Civic.Incidents.Incident do
  use Ecto.Schema
  import Ecto.Changeset

  @tipos [:robo, :agresion_mujer, :maltrato_animal, :pelea_colegio, :actividad_sospechosa]

  # Bbox de Arequipa metropolitana
  @lat_min -16.60
  @lat_max -16.25
  @lng_min -71.75
  @lng_max -71.40

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "incidentes" do
    field :tipo, Ecto.Enum, values: @tipos
    field :descripcion, :string
    field :ubicacion, Geo.PostGIS.Geometry

    field :estado, Ecto.Enum,
      values: [:sin_verificar, :verificado, :descartado],
      default: :sin_verificar

    field :idempotency_key, Ecto.UUID

    field :lat, :float, virtual: true
    field :lng, :float, virtual: true

    timestamps()
  end

  def create_changeset(incident, attrs) do
    incident
    |> cast(attrs, [:tipo, :descripcion, :lat, :lng])
    |> validate_required([:tipo, :lat, :lng])
    |> update_change(:descripcion, &trim_or_nil/1)
    |> validate_length(:descripcion, max: 500)
    |> validate_arequipa()
    |> put_ubicacion()
    |> unique_constraint(:idempotency_key)
  end

  def coords(%__MODULE__{ubicacion: %Geo.Point{coordinates: {lng, lat}}}), do: {lat, lng}

  defp trim_or_nil(texto) do
    case String.trim(texto) do
      "" -> nil
      limpio -> limpio
    end
  end

  defp validate_arequipa(changeset) do
    lat = get_field(changeset, :lat)
    lng = get_field(changeset, :lng)

    if lat && lng && not dentro_de_arequipa?(lat, lng) do
      add_error(changeset, :ubicacion, "La ubicación debe estar dentro de Arequipa")
    else
      changeset
    end
  end

  defp dentro_de_arequipa?(lat, lng) do
    lat >= @lat_min and lat <= @lat_max and lng >= @lng_min and lng <= @lng_max
  end

  defp put_ubicacion(%Ecto.Changeset{valid?: true} = changeset) do
    lat = get_field(changeset, :lat)
    lng = get_field(changeset, :lng)
    put_change(changeset, :ubicacion, %Geo.Point{coordinates: {lng, lat}, srid: 4326})
  end

  defp put_ubicacion(changeset), do: changeset
end
