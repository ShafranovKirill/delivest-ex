defmodule Delivest.Integrations.Zvonok.Config do
  @keys [:public_key, :campaign_id, :webhook_token]

  @enforce_keys @keys
  defstruct @keys

  @type t :: %__MODULE__{}

  @spec fetch() :: {:ok, t()} | {:error, :zvonok_not_configured}
  def fetch do
    env = Application.get_env(:delivest, Delivest.Integrations.Zvonok, [])

    if Enum.all?(@keys, &present?(env[&1])),
      do: {:ok, struct!(__MODULE__, Keyword.take(env, @keys))},
      else: {:error, :zvonok_not_configured}
  end

  defp present?(value), do: is_binary(value) and value != ""
end
