defmodule Delivest.Integrations.Rkeeper.Api do
  alias Delivest.HTTP.Client

  @host "https://ws.ucs.ru"
  @sandbox "https://ws-test.ucs.ru"
  @path "/wsserverlp/api/v2/aggregators/Create"
  @wait_seconds 30

  def task(settings, type, params \\ %{}, opts \\ []) do
    sync = %{objectId: settings.object_id, timeout: Keyword.get(opts, :wait, @wait_seconds)}
    body = %{taskType: type, params: Map.put(params, :sync, sync)}

    @path
    |> Client.post(body, options(settings, sync.timeout))
    |> handle()
  end

  def task_response(settings, task_guid) do
    @path
    |> Client.post(
      %{taskType: "GetTaskResponse", params: %{taskGuid: task_guid}},
      options(settings, @wait_seconds)
    )
    |> handle()
  end

  defp handle({:ok, %{"error" => %{} = error}}), do: {:error, {:rkeeper, error_text(error)}}

  defp handle({:ok, %{"taskResponse" => %{} = response}}) do
    case response do
      %{"error" => %{} = error} -> {:error, {:rkeeper, error_text(error)}}
      _ok -> {:ok, response}
    end
  end

  defp handle({:ok, %{"taskGuid" => guid}}) when is_binary(guid), do: {:pending, guid}
  defp handle({:ok, %{} = body}), do: {:ok, body}
  defp handle({:ok, body}), do: {:error, {:rkeeper, inspect(body)}}

  defp handle({:error, {:http_error, status, %{"error" => %{} = error}}}) when status < 500,
    do: {:error, {:rkeeper, error_text(error)}}

  defp handle(error), do: error

  defp error_text(%{"wsError" => %{"desc" => desc}}) when is_binary(desc), do: desc
  defp error_text(%{"desc" => desc}) when is_binary(desc), do: desc
  defp error_text(error), do: inspect(error)

  defp options(settings, wait) do
    [
      base_url: if(settings.sandbox, do: @sandbox, else: @host),
      journal: :rkeeper,
      timeout: (wait + 10) * 1_000,
      headers: [{"aggregatorauthentication", token()}]
    ]
  end

  def token, do: Keyword.get(config(), :token) || ""

  def configured?, do: token() != ""

  defp config, do: Application.get_env(:delivest, Delivest.Integrations.Rkeeper, [])
end
