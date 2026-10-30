defmodule Delivest.Integrations.Frontpad.OrderPayload do
  use Gettext, backend: DelivestWeb.Gettext

  import Delivest.Integrations.Frontpad.Fields

  alias Delivest.Integrations.Crm.OrderNotes
  alias Delivest.Money

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
          person: String.t() | nil,
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
    :person,
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
          phone: text(order.customer_phone, 50),
          name: text(order.customer_name, 50),
          person: person(order.persons),
          descr: descr(order, settings),
          pay: PaymentCodes.code_for(settings.payments, order.payment_method),
          tags: TagCodes.codes(settings.tags, order),
          datetime: format_cook_by(order),
          sale_amount: sale_amount(order.items, settings),
          products: formatted_products ++ delivery_line(order, settings)
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
        {"person", view.person},
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

  defp person(count) when is_integer(count) and count > 0, do: Integer.to_string(count)
  defp person(_count), do: nil

  defp extract_secret(%Settings{api_key: secret}) when is_binary(secret) and secret != "",
    do: {:ok, secret}

  defp extract_secret(_settings), do: {:error, :missing_api_key}

  defp sale_amount(_items, %Settings{price_override: true}), do: nil

  defp sale_amount(items, _settings) do
    case items |> Enum.map(&(discount_per_unit(&1) * &1.quantity)) |> Enum.sum() do
      0 -> nil
      amount -> rubles(amount)
    end
  end

  defp forced_price(item, %Settings{price_override: true}) do
    if discount_per_unit(item) > 0, do: rubles(item.price - modifiers_unit(item))
  end

  defp forced_price(_item, _settings), do: nil

  defp modifiers_unit(%{modifiers: modifiers}) when is_list(modifiers),
    do: modifiers |> Enum.map(&(&1.price * &1.quantity)) |> Enum.sum()

  defp modifiers_unit(_item), do: 0

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

            case modifier_lines(item, length(acc), products_map) do
              {:ok, extra} -> {:cont, Enum.reverse(extra) ++ [line | acc]}
              error -> {:halt, error}
            end

          _ ->
            {:halt, {:error, {:missing_external_id, item.product_id}}}
        end
      end)

    case result do
      {:error, _} = err -> err
      list -> {:ok, Enum.reverse(list)}
    end
  end

  defp modifier_lines(%{modifiers: modifiers} = item, parent, products_map)
       when is_list(modifiers) do
    Enum.reduce_while(modifiers, {:ok, []}, fn modifier, {:ok, acc} ->
      case products_map[modifier.modifier_id] do
        %{external_id: ext_id} ->
          line = %{
            external_id: ext_id,
            quantity: item.quantity * modifier.quantity,
            mod: Integer.to_string(parent),
            price: nil
          }

          {:cont, {:ok, acc ++ [line]}}

        _missing when modifier.price == 0 ->
          {:cont, {:ok, acc}}

        _missing ->
          {:halt, {:error, {:missing_external_id, modifier.modifier_id || modifier.name}}}
      end
    end)
  end

  defp modifier_lines(_item, _parent, _products_map), do: {:ok, []}

  defp delivery_line(%{delivery_amount: amount}, %Settings{delivery_article: article})
       when is_integer(amount) and amount > 0 and article not in [nil, ""],
       do: [%{external_id: article, quantity: 1, mod: nil, price: rubles(amount)}]

  defp delivery_line(_order, _settings), do: []

  defp rubles(amount), do: amount |> Money.to_rubles() |> to_string()

  defp descr(order, settings) do
    case {order, delivery_line(order, settings)} do
      {%{delivery_amount: amount}, []} when is_integer(amount) and amount > 0 ->
        note = gettext("Delivery %{amount}", amount: Money.format(amount))

        [number_note(order), note | OrderNotes.lines(order)]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(". ")
        |> String.slice(0, 100)

      _sent_as_product ->
        [number_note(order) | OrderNotes.lines(order)]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(". ")
        |> String.slice(0, 100)
    end
  end

  defp number_note(%{number: number}) when is_binary(number), do: "№#{number}"
  defp number_note(_order), do: nil

  defp format_cook_by(%{cook_by: %DateTime{} = cook_by} = order),
    do:
      cook_by
      |> Delivest.LocalTime.local(order.branch_id)
      |> Calendar.strftime("%Y-%m-%d %H:%M:%S")

  defp format_cook_by(_), do: nil
end
