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

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{error: %{code: "not_found", message: "No encontrado"}})
  end

  # Solo quien hizo el reporte puede agregarle la foto
  def call(conn, {:error, :not_author}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      error: %{
        code: "not_author",
        message: "Solo quien hizo el reporte puede agregarle una foto"
      }
    })
  end

  # --- Validación comunitaria (votos) ---

  # Solo las cuentas verificadas con DNI votan: una persona, una cuenta
  def call(conn, {:error, :not_verified}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      error: %{
        code: "not_verified",
        message: "Verifica tu cuenta con el DNI para confirmar o negar reportes"
      }
    })
  end

  def call(conn, {:error, :own_report}) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      error: %{code: "own_report", message: "No puedes votar tu propio reporte"}
    })
  end

  def call(conn, {:error, :already_voted}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: %{code: "already_voted", message: "Ya votaste en este reporte"}})
  end

  # Verificado o descartado: la comunidad ya decidió
  def call(conn, {:error, :voting_closed}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: %{code: "voting_closed", message: "Este reporte ya no recibe votos"}})
  end

  def call(conn, {:error, :too_far}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "too_far",
        message: "Estás muy lejos del lugar para votar este reporte"
      }
    })
  end

  def call(conn, {:error, :invalid_vote}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "validation_failed",
        message: "Datos inválidos",
        fields: %{valor: ["debe ser confirmo o falso"]}
      }
    })
  end

  def call(conn, {:error, :invalid_location}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "validation_failed",
        message: "Datos inválidos",
        fields: %{ubicacion: ["lat y lng deben ser números válidos"]}
      }
    })
  end

  def call(conn, {:error, :photo_exists}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: %{code: "photo_exists", message: "Este reporte ya tiene una foto"}})
  end

  def call(conn, {:error, :photo_too_large}) do
    conn
    |> put_status(:request_entity_too_large)
    |> json(%{
      error: %{code: "photo_too_large", message: "La foto es demasiado pesada (máximo 2 MB)"}
    })
  end

  def call(conn, {:error, :unsupported_media_type}) do
    conn
    |> put_status(:unsupported_media_type)
    |> json(%{
      error: %{code: "unsupported_media_type", message: "La foto debe enviarse como image/jpeg"}
    })
  end

  # El archivo no se pudo guardar: no es culpa de quien lo envía, que puede reintentar
  def call(conn, {:error, :storage}) do
    conn
    |> put_resp_header("retry-after", "5")
    |> put_status(:service_unavailable)
    |> json(%{
      error: %{
        code: "storage_unavailable",
        message: "No pudimos guardar la foto. Intenta de nuevo en un momento."
      }
    })
  end

  def call(conn, {:error, {:invalid_photo, :has_metadata}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{
        code: "photo_has_metadata",
        message:
          "La foto trae datos ocultos (ubicación, modelo del teléfono o fecha). " <>
            "Se envía desde la app, que los quita."
      }
    })
  end

  def call(conn, {:error, {:invalid_photo, _reason}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: %{code: "invalid_photo", message: "El archivo no es una foto JPEG válida"}
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
