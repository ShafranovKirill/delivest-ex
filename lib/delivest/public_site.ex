defmodule Delivest.PublicSite do
  @moduledoc "Durable canonical storefront URL and approved browser origins."

  @type config :: map()

  def current do
    case path() do
      nil ->
        fallback()

      file ->
        case File.read(file) do
          {:ok, contents} ->
            with {:ok, decoded} <- Jason.decode(contents),
                 {:ok, normalized} <- validate(decoded) do
              normalized
            else
              _ -> raise "invalid public-site configuration at #{file}"
            end

          {:error, :enoent} ->
            fallback()

          {:error, reason} ->
            raise "cannot read public-site configuration: #{inspect(reason)}"
        end
    end
  end

  def primary_url, do: current()["primary_url"]
  def origins, do: current()["origins"]

  def apply(config) do
    :global.trans({{__MODULE__, :apply}, self()}, fn -> do_apply(config) end)
  end

  def validate_boot! do
    _ = current()
    :ok
  end

  def current_json, do: IO.puts(Jason.encode!(current()))

  def apply_encoded(value) when is_binary(value) do
    with {:ok, json} <- Base.decode64(value),
         {:ok, config} <- Jason.decode(json),
         {:ok, result} <- apply(config) do
      IO.puts(Jason.encode!(result))
    else
      _ -> raise "public-site update failed"
    end
  end

  def cors_rules(config) do
    api = Application.get_env(:delivest, DelivestWeb.Endpoint, []) |> Keyword.get(:url, [])

    api_origin =
      case api[:host] do
        host when is_binary(host) and host != "" ->
          "#{api[:scheme] || "https"}://#{host}" <> port_suffix(api[:port], api[:scheme])

        _ ->
          nil
      end

    origins = Enum.uniq(config["origins"] ++ if(api_origin, do: [api_origin], else: []))

    [
      %{
        allowed_origins: origins,
        allowed_methods: ["GET", "PUT", "POST", "HEAD"],
        allowed_headers: ["*"],
        exposed_headers: ["ETag"],
        max_age_seconds: 3600
      }
    ]
  end

  defp do_apply(config) do
    with {:ok, normalized} <- validate(config),
         file when is_binary(file) <- path() do
      previous = current()

      with :ok <- update_bucket_cors(normalized),
           :ok <- write_atomic(file, Jason.encode!(normalized) <> "\n") do
        {:ok, normalized}
      else
        error ->
          case update_bucket_cors(previous) do
            :ok -> {:error, error}
            rollback_error -> {:error, {:rollback_failed, error, rollback_error}}
          end
      end
    else
      nil -> {:error, :not_managed}
      error -> error
    end
  end

  defp update_bucket_cors(config) do
    adapter = Application.get_env(:delivest, :public_site_cors_adapter, __MODULE__)
    adapter.put(config)
  end

  def put(config) do
    for bucket <- Enum.uniq([Delivest.Media.public_bucket(), Delivest.Media.private_bucket()]) do
      case ExAws.S3.put_bucket_cors(bucket, cors_rules(config)) |> ExAws.request() do
        {:ok, _} -> :ok
        error -> throw({:error, {:bucket_cors, bucket, error}})
      end
    end

    :ok
  catch
    error -> error
  end

  defp write_atomic(file, content) do
    parent = Path.dirname(file)
    temp = file <> ".#{System.unique_integer([:positive])}.tmp"

    try do
      with :ok <- File.mkdir_p(parent),
           {:ok, io} <- File.open(temp, [:write, :binary, :exclusive]) do
        result =
          try do
            with :ok <- File.chmod(temp, 0o600),
                 :ok <- IO.binwrite(io, content),
                 :ok <- :file.sync(io) do
              :ok
            end
          after
            File.close(io)
          end

        if result == :ok, do: File.rename(temp, file), else: result
      else
        error -> error
      end
    after
      File.rm(temp)
    end
  end

  defp validate(%{"primary_url" => primary, "origins" => origins})
       when is_binary(primary) and is_list(origins) and origins != [] do
    with true <- length(origins) <= 16 and Enum.all?(origins, &valid_origin?/1),
         true <- valid_origin?(primary) and primary in origins do
      {:ok, %{"primary_url" => primary, "origins" => Enum.uniq(origins)}}
    else
      _ -> {:error, :invalid_origin}
    end
  end

  defp validate(_), do: {:error, :invalid_configuration}

  defp valid_origin?(value) when is_binary(value) do
    uri = URI.parse(value)
    production = Application.get_env(:delivest, :env) == :prod

    uri.scheme in if(production, do: ["https"], else: ["http", "https"]) and
      is_binary(uri.host) and uri.host != "" and uri.userinfo == nil and
      uri.path in [nil, ""] and uri.query == nil and uri.fragment == nil and
      URI.to_string(uri) == value and not String.contains?(value, "*")
  end

  defp valid_origin?(_), do: false

  defp fallback do
    origin = Application.get_env(:delivest, :client_origin, "http://localhost:3000")
    %{"primary_url" => origin, "origins" => [origin]}
  end

  defp path, do: Application.get_env(:delivest, :public_site_config_path)

  defp port_suffix(port, _scheme) when port in [nil, 80, 443], do: ""
  defp port_suffix(port, _scheme), do: ":#{port}"
end
