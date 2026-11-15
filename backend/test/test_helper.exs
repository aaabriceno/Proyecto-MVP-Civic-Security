ExUnit.start()

# Las fotos de las pruebas se guardan en una carpeta temporal: se borra al terminar
ExUnit.after_suite(fn _ ->
  File.rm_rf(Application.fetch_env!(:civic, Civic.Evidence)[:root])
end)

Ecto.Adapters.SQL.Sandbox.mode(Civic.Repo, :manual)
