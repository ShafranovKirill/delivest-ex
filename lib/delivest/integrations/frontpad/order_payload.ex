defmodule Delivest.Integrations.Frontpad.OrderPayload do
  import Delivest.Integrations.Frontpad.Fields

  alias Delivest.Integrations.Crm.OrderNotes

  alias Delivest.Integrations.Frontpad.{
    AddressFields,
    PaymentCodes,
    Settings,
    StatusCodes,
    TagCodes
  }

  @type product_item :: %{
          external_id: String.t(),
          quantity: integer(),
          mod: String.t() | nil,
          price: String.t() | nil
        }

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
          datetime: String.t() | nil,
          hook_url: String.t() | nil,
          hook_status: [String.t()],
          tags: [String.t()],
          sale_amount: String.t() | nil,
          products: [product_item()]
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
    :datetime,
    :hook_url,
    :sale_amount,
    hook_status: [],
    tags: [],
    products: []
  ]

  @spec build(Delivest.Oms.Order.t(), Settings.t(), map()) :: {:ok, t()} | {:error, term()}
  def build(order, %Settings{} = settings, products_map) do
    with {:ok, secret} <- extract_secret(settings),
         {:ok, formatted_products} <- extract_products(order.items, products_map, settings) do
      payload =
        %__MODULE__{
          secret: secret,
          affiliate: text(settings.affiliate, 50),
          phone: text(customer_phone(order), 50),
          name: text(customer_name(order), 50),
          descr: OrderNotes.text(order, 100),
          pay: PaymentCodes.code_for(settings.payments, order.payment_method),
          tags: TagCodes.codes(settings.tags, order),
          datetime: format_cook_by(order.cook_by),
          sale_amount: sale_amount(order.items, settings),
          products: formatted_products
        }
        |> struct!(AddressFields.build(order.address))
        |> put_hooks(settings)

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
        {"pay", view.pay},
        {"datetime", view.datetime},
        {"hook_url", view.hook_url},
        {"sale_amount", view.sale_amount}
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)

    products_params =
      view.products
      |> Enum.with_index()
      |> Enum.flat_map(fn {item, index} ->
        [
          {"product[#{index}]", item.external_id},
          {"product_kol[#{index}]", to_string(item.quantity)},
          {"product_mod[#{index}]", item.mod},
          {"product_price[#{index}]", item.price}
        ]
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      end)

    hook_params =
      view.hook_status
      |> Enum.with_index()
      |> Enum.map(fn {code, index} -> {"hook_status[#{index}]", code} end)

    tag_params =
      view.tags
      |> Enum.with_index()
      |> Enum.map(fn {code, index} -> {"tags[#{index}]", code} end)

    base_params ++ products_params ++ hook_params ++ tag_params
  end

  defp put_hooks(view, %Settings{webhook_token: token, statuses: statuses}) do
    case StatusCodes.codes(statuses) do
      codes when codes == [] or is_nil(token) ->
        view

      codes ->
        %{view | hook_status: codes, hook_url: Delivest.Integrations.Frontpad.webhook_url(token)}
    end
  end

  defp customer_phone(%{customer_phone: phone}) when is_binary(phone) and phone != "", do: phone
  defp customer_phone(%{client: %{phone: phone}}), do: phone
  defp customer_phone(%{channel: %{details: %{"phone" => phone}}}), do: phone
  defp customer_phone(_), do: nil

  defp customer_name(%{customer_name: name}) when is_binary(name) and name != "", do: name
  defp customer_name(%{client: %{name: name}}), do: name
  defp customer_name(%{channel: %{details: %{"client_name" => name}}}), do: name
  defp customer_name(_), do: nil

  defp extract_secret(%Settings{api_key: secret}) when is_binary(secret) and secret != "",
    do: {:ok, secret}

  defp extract_secret(_settings), do: {:error, :missing_api_key}

  defp sale_amount(_items, %Settings{price_override: true}), do: nil

  defp sale_amount(items, _settings) do
    case items |> Enum.map(&(discount_per_unit(&1) * &1.quantity)) |> Enum.sum() do
      0 -> nil
      amount -> to_string(amount)
    end
  end

  defp forced_price(item, %Settings{price_override: true}) do
    if discount_per_unit(item) > 0, do: to_string(item.price)
  end

  defp forced_price(_item, _settings), do: nil

  defp discount_per_unit(%{base_price: base, price: price})
       when is_integer(base) and is_integer(price),
       do: max(base - price, 0)

  defp discount_per_unit(_item), do: 0

  defp extract_products(order_items, products_map, settings) do
    result =
      Enum.reduce_while(order_items, [], fn item, acc ->
        case Map.get(products_map, item.product_id) do
          %{external_id: ext_id} = product when not is_nil(ext_id) ->
            mod = Map.get(item, :mod) || Map.get(product, :mod)

            line = %{
              external_id: ext_id,
              quantity: item.quantity,
              mod: mod,
              price: forced_price(item, settings)
            }

            {:cont, [line | acc]}

          _ ->
            {:halt, {:error, {:missing_external_id, item.product_id}}}
        end
      end)

    case result do
      {:error, _} = err -> err
      list -> {:ok, Enum.reverse(list)}
    end
  end

  defp format_cook_by(%NaiveDateTime{} = cook_by),
    do: Calendar.strftime(cook_by, "%Y-%m-%d %H:%M:%S")

  defp format_cook_by(_), do: nil
end
