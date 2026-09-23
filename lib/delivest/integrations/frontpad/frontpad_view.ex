defmodule Delivest.Integrations.Frontpad.FrontpadView do
  @type t :: %__MODULE__{
          secret: String.t(),
          affiliate: String.t() | nil,
          phone: String.t() | nil,
          name: String.t() | nil,
          street: String.t() | nil,
          home: String.t() | nil,
          pod: String.t() | nil,
          et: String.t() | nil,
          apart: String.t() | nil,
          descr: String.t() | nil,
          pay: String.t() | nil,
          products: [%{external_id: String.t(), quantity: integer()}]
        }

  defstruct [
    :secret,
    :affiliate,
    :phone,
    :name,
    :street,
    :home,
    :pod,
    :et,
    :apart,
    :descr,
    :pay,
    products: []
  ]

  @spec build(Delivest.Oms.Order.t(), Delivest.Identity.Branch.t(), map()) ::
          {:ok, t()} | {:error, atom()}
  def build(order, branch, products_map) do
    with {:ok, secret} <- extract_secret(branch),
         {:ok, formatted_products} <- extract_products(order.items, products_map) do
      payload = %__MODULE__{
        secret: secret,
        affiliate: extract_branch_id(branch),
        phone: truncate(order.customer_phone, 50),
        name: truncate(order.customer_name, 50),
        street: truncate(order.address && order.address.street, 50),
        home: truncate(order.address && order.address.house, 50),
        pod: truncate_int_string(order.address && order.address.entrance, 2),
        et: truncate_int_string(order.address && order.address.floor, 2),
        apart: truncate(order.address && order.address.apartment, 50),
        descr: truncate(order.comment, 100),
        pay: map_payment_method(order.payment_method),
        products: formatted_products
      }

      {:ok, payload}
    end
  end

  @spec to_form_params(t()) :: [{String.t(), String.t()}]
  def to_form_params(%__MODULE__{} = view) do
    base_params =
      [
        {"secret", view.secret},
        {"affiliate", view.affiliate},
        {"phone", view.phone},
        {"name", view.name},
        {"street", view.street},
        {"home", view.home},
        {"pod", view.pod},
        {"et", view.et},
        {"apart", view.apart},
        {"descr", view.descr},
        {"pay", view.pay}
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)

    products_params =
      view.products
      |> Enum.with_index()
      |> Enum.flat_map(fn {item, index} ->
        [
          {"product[#{index}]", item.external_id},
          {"product_kol[#{index}]", to_string(item.quantity)}
        ]
      end)

    base_params ++ products_params
  end

  defp extract_secret(%{info: %{frontpad_api_key: secret}}) when not is_nil(secret),
    do: {:ok, secret}

  defp extract_secret(_), do: {:error, :missing_frontpad_api_key}

  defp extract_branch_id(%{info: %{frontpad_branch_id: fb_id}}) when not is_nil(fb_id),
    do: to_string(fb_id)

  defp extract_branch_id(_), do: nil

  defp extract_products(order_items, products_map) do
    result =
      Enum.reduce_while(order_items, [], fn item, acc ->
        case Map.get(products_map, item.product_id) do
          %{external_id: ext_id} when not is_nil(ext_id) ->
            {:cont, [%{external_id: ext_id, quantity: item.quantity} | acc]}

          _ ->
            {:halt, {:error, {:missing_external_id, item.product_id}}}
        end
      end)

    case result do
      {:error, _} = err -> err
      list -> {:ok, Enum.reverse(list)}
    end
  end

  defp truncate(nil, _max_len), do: nil

  defp truncate(str, max_len) when is_binary(str) do
    str
    |> String.trim()
    |> String.slice(0, max_len)
  end

  defp truncate(val, max_len) when not is_nil(val) do
    val |> to_string() |> truncate(max_len)
  end

  defp truncate_int_string(nil, _max_len), do: nil

  defp truncate_int_string(val, max_len) do
    val
    |> to_string()
    |> String.replace(~r/\D/, "")
    |> truncate(max_len)
  end

  defp map_payment_method(:cash), do: "1"
  defp map_payment_method(:card_offline), do: "2"
  defp map_payment_method(_), do: "1"
end
