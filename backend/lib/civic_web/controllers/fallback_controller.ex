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

  def call(conn, {:error, :unauthorized}), do: CivicWeb.Plugs.Authenticate.deny(conn)

  # Cupo diario de reportes agotado. `retry-after` en segundos, redondeado hacia
  # arriba para que reintentar justo a tiempo no vuelva a recibir 429.
  def call(conn, {:error, {:quota_exceeded, retry_ms}}) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(max(div(retry_ms + 999, 1000), 1)))
    |> put_status(:too_many_requests)
    |> json(%{
      error: %{
        code: "report_quota_exceeded",
        message: "Llegaste al límite de reportes de hoy. Intenta de nuevo más tarde."
      }
    })
  end

  # El DNI no tiene 8 dígitos. Nunca se repite lo que escribió la persona.
  def call(conn, {:error, :invalid_dni}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "validation_failed",
        message: "Datos inválidos",
        fields: %{dni: ["debe tener 8 dígitos"]}
      }
    })
  end

  def call(conn, {:error, :dni_taken}) do
    conn
    |> put_status(:conflict)
    |> json(%{
      error: %{code: "dni_taken", message: "Este DNI ya tiene una cuenta"}
    })
  end

  def call(conn, {:error, :already_verified}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: %{code: "already_verified", message: "Tu cuenta ya está verificada"}})
  end

  # Se acabaron los intentos de verificar el DNI del día
  def call(conn, {:error, {:attempts_exceeded, retry_ms}}) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(max(div(retry_ms + 999, 1000), 1)))
    |> put_status(:too_many_requests)
    |> json(%{
      error: %{
        code: "dni_attempts_exceeded",
        message: "Llegaste al límite de intentos de hoy. Intenta de nuevo más tarde."
      }
    })
  end

  # Mismo mensaje para "alias que no existe" y "contraseña equivocada"
  def call(conn, {:error, :invalid_credentials}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: "invalid_credentials", message: "Alias o contraseña incorrectos"}})
  end

  def call(conn, {:error, {:locked, seconds}}) do
    conn
    |> put_resp_header("retry-after", Integer.to_string(seconds))
    |> put_status(:too_many_requests)
    |> json(%{
      error: %{
        code: "account_locked",
        message: "Demasiados intentos fallidos. Intenta de nuevo en #{seconds} s."
      }
    })
  end

  # Un solo error para token inexistente, vencido, manipulado o ya usado
  def call(conn, {:error, :invalid_token}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: "invalid_token", message: "Sesión inválida o vencida"}})
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

  # Un campo de un formulario que se verificó contra la cuenta (p. ej. la
  # contraseña actual) y no coincide
  def call(conn, {:error, {:invalid_field, field}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "validation_failed",
        message: "Datos inválidos",
        fields: %{field => ["es incorrecta"]}
      }
    })
  end

  def call(conn, {:error, :invalid_window}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: %{code: "invalid_window", message: "ventana debe ser 1h, 24h o 7d"}
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
