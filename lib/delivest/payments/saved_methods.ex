defmodule Delivest.Payments.SavedMethods do
  import Ecto.Query

  alias Delivest.Integrations.Yookassa
  alias Delivest.Payments.SavedPaymentMethod
  alias Delivest.Repo

  def enabled? do
    settings = Yookassa.get_settings()
    settings.saved_payment_methods_enabled == true and Yookassa.ready?()
  end

  def list(client_id) do
    settings = Yookassa.get_settings()

    if is_nil(settings.shop_id),
      do: [],
      else:
        Repo.all(
          from(m in SavedPaymentMethod,
            where:
              m.client_id == ^client_id and m.shop_id == ^settings.shop_id and
                is_nil(m.deleted_at),
            order_by: [desc: m.inserted_at]
          )
        )
  end

  def active(client_id, shop_id, id, lock \\ nil) do
    with true <- is_binary(shop_id), {:ok, uuid} <- Ecto.UUID.cast(id) do
      query =
        from(m in SavedPaymentMethod,
          where:
            m.id == ^uuid and m.client_id == ^client_id and m.shop_id == ^shop_id and
              is_nil(m.deleted_at)
        )

      query = if lock == "FOR UPDATE", do: from(m in query, lock: "FOR UPDATE"), else: query
      Repo.one(query)
    else
      _ -> nil
    end
  end

  def fallback_available?(order_id) do
    Repo.exists?(
      from(m in Delivest.Payments.Payment,
        where:
          m.order_id == ^order_id and m.status == :cancelled and
            fragment("(?->>'saved_payment_method_id') IS NOT NULL", m.details)
      )
    ) and
      not Repo.exists?(
        from(m in Delivest.Payments.Payment,
          where: m.order_id == ^order_id and m.method == :online and m.status == :pending
        )
      )
  end

  def delete(client_id, id) do
    settings = Yookassa.get_settings()

    if is_nil(settings.shop_id),
      do: {:error, :saved_payment_method_not_found},
      else:
        Repo.transaction(fn ->
          case active(client_id, settings.shop_id, id, "FOR UPDATE") do
            nil ->
              Repo.rollback(:saved_payment_method_not_found)

            method ->
              method
              |> Ecto.Changeset.change(deleted_at: DateTime.utc_now(:microsecond))
              |> Repo.update!()
          end
        end)
  end

  def save_from_provider(client_id, shop_id, data, consented_at \\ nil)

  def save_from_provider(
        client_id,
        shop_id,
        %{"saved" => true, "id" => provider_id} = data,
        consented_at
      )
      when is_binary(provider_id) do
    attrs = safe_metadata(data)

    Repo.transaction(fn ->
      method =
        Repo.one(
          from(m in SavedPaymentMethod,
            where:
              m.client_id == ^client_id and m.shop_id == ^shop_id and
                m.provider_method_id == ^provider_id,
            lock: "FOR UPDATE"
          )
        )

      case method do
        %SavedPaymentMethod{deleted_at: deleted_at} = method when not is_nil(deleted_at) ->
          if later_consent?(consented_at, deleted_at) do
            method
            |> SavedPaymentMethod.provider_changeset(attrs)
            |> Ecto.Changeset.put_change(:deleted_at, nil)
            |> Repo.update()
            |> result()
          else
            :ok
          end

        %SavedPaymentMethod{} = method ->
          method |> SavedPaymentMethod.provider_changeset(attrs) |> Repo.update() |> result()

        nil ->
          %SavedPaymentMethod{
            client_id: client_id,
            shop_id: shop_id,
            provider_method_id: provider_id
          }
          |> SavedPaymentMethod.provider_changeset(attrs)
          |> Repo.insert(on_conflict: :nothing)
          |> result()
      end
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  def save_from_provider(_client_id, _shop_id, _data, _consented_at), do: :ok

  defp later_consent?(consented_at, deleted_at) when is_binary(consented_at) do
    case DateTime.from_iso8601(consented_at) do
      {:ok, consented_at, _offset} -> DateTime.compare(consented_at, deleted_at) == :gt
      _ -> false
    end
  end

  defp later_consent?(_, _), do: false

  defp result({:ok, _method}), do: :ok
  defp result(_error), do: :ok

  defp safe_metadata(data) do
    details = data["card"] || %{}
    last4 = details["last4"]

    %{
      type:
        if(is_binary(data["type"]) and byte_size(data["type"]) <= 40,
          do: data["type"]
        ),
      title: safe_title(data["type"], details["card_type"]),
      last4: if(is_binary(last4) and Regex.match?(~r/^\d{4}$/, last4), do: last4)
    }
  end

  defp safe_title("bank_card", card_type) when card_type in ~w(Visa MasterCard Mir), do: card_type
  defp safe_title("bank_card", _), do: "Банковская карта"
  defp safe_title("sbp", _), do: "СБП"
  defp safe_title("yoo_money", _), do: "ЮMoney"
  defp safe_title(_, _), do: "Способ оплаты"
end
