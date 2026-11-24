defmodule Delivest.Identity.DashboardLayout do
  @moduledoc "A staff member's desktop dashboard layout, shared across their branches."

  use Ecto.Schema
  import Ecto.Changeset, only: [change: 1, foreign_key_constraint: 3]
  import Ecto.Query, only: [from: 2]

  alias Delivest.Repo

  @primary_key {:staff_id, :binary_id, autogenerate: false}
  schema "staff_dashboard_layouts" do
    field :layout, :map
    timestamps(type: :utc_datetime)
  end

  @columns 12
  @max_y 120
  @widget_ids ~w(attention quick_actions revenue orders avg_check in_work hourly cumulative_revenue latest_orders top_products branch_summary)
  @action_ids ~w(new_order orders statistics kitchen deliveries stop_list)

  @limits %{
    "attention" => %{min_w: 4, min_h: 2, max_w: 12, max_h: 8},
    "quick_actions" => %{min_w: 3, min_h: 2, max_w: 12, max_h: 8},
    "revenue" => %{min_w: 2, min_h: 2, max_w: 6, max_h: 5},
    "orders" => %{min_w: 2, min_h: 2, max_w: 6, max_h: 5},
    "avg_check" => %{min_w: 2, min_h: 2, max_w: 6, max_h: 5},
    "in_work" => %{min_w: 2, min_h: 2, max_w: 6, max_h: 5},
    "hourly" => %{min_w: 4, min_h: 3, max_w: 12, max_h: 12},
    "cumulative_revenue" => %{min_w: 4, min_h: 3, max_w: 12, max_h: 12},
    "latest_orders" => %{min_w: 3, min_h: 3, max_w: 12, max_h: 12},
    "top_products" => %{min_w: 3, min_h: 3, max_w: 12, max_h: 12},
    "branch_summary" => %{min_w: 3, min_h: 3, max_w: 12, max_h: 12}
  }

  @default_widgets [
    %{id: "attention", x: 0, y: 0, w: 8, h: 2},
    %{id: "quick_actions", x: 8, y: 0, w: 4, h: 2},
    %{id: "revenue", x: 0, y: 2, w: 3, h: 2},
    %{id: "orders", x: 3, y: 2, w: 3, h: 2},
    %{id: "avg_check", x: 6, y: 2, w: 3, h: 2},
    %{id: "in_work", x: 9, y: 2, w: 3, h: 2},
    %{id: "hourly", x: 0, y: 4, w: 8, h: 4},
    %{id: "latest_orders", x: 8, y: 4, w: 4, h: 4},
    %{id: "top_products", x: 0, y: 8, w: 6, h: 4},
    %{id: "branch_summary", x: 6, y: 8, w: 6, h: 4}
  ]

  def default, do: %{widgets: @default_widgets, actions: ~w(new_order orders statistics)}
  def widget_ids, do: @widget_ids
  def action_ids, do: @action_ids
  def widget_limits(id), do: Map.get(@limits, id)

  def get(staff_id) do
    case Repo.get(__MODULE__, staff_id) do
      nil ->
        default()

      %__MODULE__{layout: layout} ->
        case validate(layout) do
          {:ok, canonical} -> canonical
          {:error, _} -> default()
        end
    end
  end

  def save(staff_id, params) do
    with {:ok, _uuid} <- Ecto.UUID.cast(staff_id),
         {:ok, layout} <- validate(params),
         {:ok, _} <-
           Repo.insert(
             %__MODULE__{staff_id: staff_id, layout: layout}
             |> change()
             |> foreign_key_constraint(:staff_id, name: :staff_dashboard_layouts_staff_id_fkey),
             on_conflict: {:replace, [:layout, :updated_at]},
             conflict_target: :staff_id
           ) do
      {:ok, layout}
    else
      :error -> {:error, :invalid_staff_id}
      {:error, _} = error -> error
    end
  end

  def reset(staff_id) do
    with {:ok, _uuid} <- Ecto.UUID.cast(staff_id) do
      Repo.delete_all(from(layout in __MODULE__, where: layout.staff_id == ^staff_id))
      {:ok, default()}
    else
      :error -> {:error, :invalid_staff_id}
    end
  end

  defp validate(params) when is_map(params) do
    widgets = value(params, :widgets)
    actions = value(params, :actions)

    with true <- is_list(widgets) and length(widgets) <= length(@widget_ids),
         true <- is_list(actions) and length(actions) <= length(@action_ids),
         {:ok, widgets} <- validate_widgets(widgets),
         {:ok, actions} <- validate_actions(actions) do
      {:ok, %{widgets: widgets, actions: actions}}
    else
      _ -> {:error, :invalid_layout}
    end
  end

  defp validate(_), do: {:error, :invalid_layout}

  defp validate_widgets(widgets) do
    Enum.reduce_while(widgets, {:ok, [], MapSet.new()}, fn widget, {:ok, acc, seen} ->
      case validate_widget(widget) do
        {:ok, %{id: id} = canonical} ->
          if MapSet.member?(seen, id) do
            {:halt, {:error, :duplicate_widget}}
          else
            {:cont, {:ok, [canonical | acc], MapSet.put(seen, id)}}
          end

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, widgets, _seen} -> {:ok, Enum.reverse(widgets)}
      error -> error
    end
  end

  defp validate_widget(widget) when is_map(widget) do
    id = value(widget, :id)
    x = value(widget, :x)
    y = value(widget, :y)
    w = value(widget, :w)
    h = value(widget, :h)
    limits = widget_limits(id)

    if limits && is_integer(x) && is_integer(y) && is_integer(w) && is_integer(h) &&
         x >= 0 && y >= 0 && y <= @max_y && w >= limits.min_w && w <= limits.max_w &&
         h >= limits.min_h && h <= limits.max_h && x + w <= @columns do
      {:ok, %{id: id, x: x, y: y, w: w, h: h}}
    else
      {:error, :invalid_widget}
    end
  end

  defp validate_widget(_), do: {:error, :invalid_widget}

  defp validate_actions(actions) do
    if Enum.all?(actions, &(&1 in @action_ids)) && length(Enum.uniq(actions)) == length(actions) do
      {:ok, actions}
    else
      {:error, :invalid_actions}
    end
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
