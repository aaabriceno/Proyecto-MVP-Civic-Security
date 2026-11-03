defmodule CivicWeb.FallbackController do
  @moduledoc """
  Traduce los errores de dominio al formato de error uniforme de la API:

      {"error": {"code": "...", "message": "...", "fields": {...}}}

  `fields` solo aparece en los 422.
  """

  use CivicWeb, :controller

  def call(conn, {:error, :idempotency_key_required}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: %{
        code: "idempotency_key_required",
        message: "Falta el encabezado idempotency-key o no es un UUID válido"
      }
    })
  end

  def call(conn, {:error, :idempotency_conflict}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      error: %{
        code: "idempotency_key_conflict",
        message: "Esa idempotency-key ya se usó con otro contenido; genera una nueva"
      }
    })
  end

  def call(conn, {:error, :invalid_bbox}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: %{
        code: "invalid_bbox",
        message: "bbox debe ser minLng,minLat,maxLng,maxLat (números, min menor que max)"
      }
    })
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    fields =
      Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
        Regex.replace(~r"%{(\w+)}", message, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: %{code: "validation_failed", message: "Datos inválidos", fields: fields}})
  end
end
