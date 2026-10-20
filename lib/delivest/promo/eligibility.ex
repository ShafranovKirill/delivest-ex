defmodule Delivest.Promo.Eligibility do
  alias Delivest.Promo.{Context, PromoCode, Promotion, Usage}

  @type reason ::
          :not_started
          | :expired
          | :exhausted
          | :requires_client
          | :client_limit
          | :not_owner
          | :code_used
          | :code_required

  @spec check(Promotion.t(), PromoCode.t() | nil, Context.t(), Usage.t()) ::
          :ok | {:error, reason()}
  def check(%Promotion{} = promotion, code, %Context{} = context, %Usage{} = usage) do
    with :ok <- window(promotion, context.now),
         :ok <- code_present(promotion, code),
         :ok <- owner(code, context.client_id),
         :ok <- code_limit(code, usage) do
      limits(promotion, context.client_id, usage)
    end
  end

  @spec limits(Promotion.t(), binary() | nil, Usage.t()) :: :ok | {:error, reason()}
  def limits(%Promotion{} = promotion, client_id, %Usage{} = usage) do
    with :ok <- total_limit(promotion, usage) do
      client_limit(promotion, client_id, usage)
    end
  end

  defp window(%Promotion{starts_at: starts_at, ends_at: ends_at}, now) do
    cond do
      starts_at && DateTime.compare(now, starts_at) == :lt -> {:error, :not_started}
      ends_at && DateTime.compare(now, ends_at) != :lt -> {:error, :expired}
      true -> :ok
    end
  end

  defp code_present(%Promotion{kind: :automatic}, _code), do: :ok
  defp code_present(_promotion, %PromoCode{}), do: :ok
  defp code_present(_promotion, nil), do: {:error, :code_required}

  defp owner(nil, _client_id), do: :ok
  defp owner(%PromoCode{client_id: nil}, _client_id), do: :ok
  defp owner(%PromoCode{}, nil), do: {:error, :requires_client}
  defp owner(%PromoCode{client_id: client_id}, client_id), do: :ok
  defp owner(%PromoCode{}, _client_id), do: {:error, :not_owner}

  defp code_limit(%PromoCode{usage_limit: limit, id: id}, usage) when is_integer(limit) do
    if Usage.code(usage, id) >= limit, do: {:error, :code_used}, else: :ok
  end

  defp code_limit(_code, _usage), do: :ok

  defp total_limit(%Promotion{usage_limit: limit, id: id}, usage) when is_integer(limit) do
    if Usage.total(usage, id) >= limit, do: {:error, :exhausted}, else: :ok
  end

  defp total_limit(_promotion, _usage), do: :ok

  defp client_limit(%Promotion{per_client_limit: nil}, _client_id, _usage), do: :ok
  defp client_limit(%Promotion{}, nil, _usage), do: {:error, :requires_client}

  defp client_limit(%Promotion{per_client_limit: limit, id: id}, _client_id, usage) do
    if Usage.client(usage, id) >= limit, do: {:error, :client_limit}, else: :ok
  end
end
