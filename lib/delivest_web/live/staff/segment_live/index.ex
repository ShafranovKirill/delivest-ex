defmodule DelivestWeb.Staff.SegmentLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.{Features, Identity, Segments}

  on_mount {DelivestWeb.Hooks.Permission, "segments.read"}

  @impl true
  def mount(_params, _session, socket) do
    if Segments.available?(socket.assigns.current_staff) do
      branches =
        Enum.filter(
          socket.assigns.staff_branches,
          &Features.enabled?("segments", {:branch, &1.id})
        )

      socket =
        socket
        |> assign(
          page_title: "Сегменты",
          can_manage: Identity.can?(socket.assigns.current_staff, "segments.manage"),
          branches: branches,
          group: nil,
          members: [],
          has_more_members: false,
          candidates: [],
          selected_clients: %{},
          selected_branches: [],
          conditions: [],
          condition_metric: "order_count",
          step: 1,
          after_id: nil,
          last_group_id: nil,
          member_after: nil,
          draft: %{"name" => "", "kind" => "manual", "scope" => "branches", "match" => "all"},
          form:
            to_form(%{"name" => "", "kind" => "manual", "scope" => "branches", "match" => "all"},
              as: :segment
            ),
          condition_form:
            to_form(%{"metric" => "order_count", "op" => "gte", "value" => "1"}, as: :condition),
          search_form: to_form(%{"query" => ""}, as: :search)
        )
        |> attach_hook(:segments_feature_gate, :handle_event, &check_event/3)

      {:ok, socket}
    else
      {:ok, redirect(socket, to: ~p"/staff/branches/select")}
    end
  end

  defp check_event(_event, _params, socket) do
    if Segments.available?(socket.assigns.current_staff) do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: ~p"/staff/branches/select")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    staff = socket.assigns.current_staff

    case socket.assigns.live_action do
      :index ->
        case Segments.list(staff, after: params["after"]) do
          {:ok, groups} ->
            {:noreply,
             socket
             |> assign(
               group: nil,
               after_id: params["after"],
               last_group_id: List.last(groups) && List.last(groups).id
             )
             |> stream(:groups, groups, reset: true)}

          _ ->
            {:noreply, redirect(socket, to: ~p"/staff/branches/select")}
        end

      :new ->
        if socket.assigns.can_manage,
          do: {:noreply, assign(socket, group: nil, step: 1)},
          else: {:noreply, push_navigate(socket, to: ~p"/staff/segments")}

      :edit ->
        if socket.assigns.can_manage do
          case Segments.get(staff, params["id"]) do
            {:ok, group} ->
              draft = %{
                "name" => group.name,
                "kind" => Atom.to_string(group.kind),
                "scope" => Atom.to_string(group.scope),
                "match" => (group.rules && group.rules["match"]) || "all"
              }

              {:noreply,
               socket
               |> assign(
                 group: group,
                 draft: draft,
                 selected_branches: Enum.map(group.branches, & &1.id),
                 conditions: (group.rules && group.rules["conditions"]) || [],
                 form: to_form(draft, as: :segment),
                 step: 1
               )}

            _ ->
              {:noreply, push_navigate(socket, to: ~p"/staff/segments")}
          end
        else
          {:noreply, push_navigate(socket, to: ~p"/staff/segments")}
        end

      :show ->
        case Segments.get(staff, params["id"]) do
          {:ok, group} ->
            {:ok, members} = Segments.list_members(staff, group.id)

            {:noreply,
             socket
             |> assign(
               group: group,
               members: members,
               has_more_members: length(members) == 50,
               member_after: nil
             )}

          _ ->
            {:noreply, push_navigate(socket, to: ~p"/staff/segments")}
        end
    end
  end

  @impl true
  def handle_event("details", %{"segment" => params}, socket) do
    fields = if socket.assigns.live_action == :edit, do: ~w(name), else: ~w(name kind scope match)
    draft = socket.assigns.draft |> Map.merge(Map.take(params, fields))
    {:noreply, socket |> assign(draft: draft, form: to_form(draft, as: :segment), step: 2)}
  end

  def handle_event("set_match", %{"segment" => %{"match" => match}}, socket)
      when match in ["all", "any"] do
    draft = Map.put(socket.assigns.draft, "match", match)
    {:noreply, assign(socket, draft: draft, form: to_form(draft, as: :segment))}
  end

  def handle_event("toggle_branch", %{"id" => id}, socket) do
    if socket.assigns.live_action == :edit do
      {:noreply, socket}
    else
      selected = socket.assigns.selected_branches

      if Enum.any?(socket.assigns.branches, &(&1.id == id)) do
        selected = if id in selected, do: List.delete(selected, id), else: [id | selected]
        {:noreply, assign(socket, selected_branches: selected)}
      else
        {:noreply, socket}
      end
    end
  end

  def handle_event("add_condition", %{"condition" => params}, socket) do
    rule = %{
      "metric" => params["metric"],
      "op" => params["op"],
      "value" => parse_value(params["metric"], params["value"])
    }

    candidate = socket.assigns.conditions ++ [rule]

    if match?(
         {:ok, _},
         Segments.Rules.validate(%{
           "version" => 1,
           "match" => socket.assigns.draft["match"],
           "conditions" => candidate
         })
       ) do
      {:noreply, assign(socket, conditions: candidate)}
    else
      {:noreply, put_flash(socket, :error, "Некорректное условие или превышен лимит 8 условий")}
    end
  end

  def handle_event("change_condition", %{"condition" => params}, socket) do
    {:noreply,
     assign(socket,
       condition_metric: params["metric"],
       condition_form: to_form(params, as: :condition)
     )}
  end

  def handle_event("remove_condition", %{"index" => index}, socket) do
    case Integer.parse(index) do
      {number, ""} when number >= 0 and number < length(socket.assigns.conditions) ->
        {:noreply, assign(socket, conditions: List.delete_at(socket.assigns.conditions, number))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("search_clients", %{"search" => %{"query" => query}}, socket) do
    staff = socket.assigns.current_staff

    result =
      if socket.assigns.live_action == :new do
        Segments.search_candidates(
          staff,
          socket.assigns.draft,
          socket.assigns.selected_branches,
          query
        )
      else
        Segments.search_eligible_clients(staff, socket.assigns.group.id, query)
      end

    {:noreply,
     assign(socket,
       candidates:
         case result do
           {:ok, clients} -> clients
           _ -> []
         end,
       search_form: to_form(%{"query" => query}, as: :search)
     )}
  end

  def handle_event("select_client", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.candidates, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      client ->
        {:noreply,
         assign(socket, selected_clients: Map.put(socket.assigns.selected_clients, id, client))}
    end
  end

  def handle_event("remove_selected_client", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket, selected_clients: Map.delete(socket.assigns.selected_clients, id))}

  def handle_event("review", _, socket) do
    rules = rules(socket)

    valid? =
      socket.assigns.draft["kind"] == "manual" or match?({:ok, _}, Segments.Rules.validate(rules))

    if valid?,
      do: {:noreply, assign(socket, step: 3)},
      else: {:noreply, put_flash(socket, :error, "Добавьте корректные условия")}
  end

  def handle_event("back", _, socket),
    do: {:noreply, assign(socket, step: max(1, socket.assigns.step - 1))}

  def handle_event("save", _, socket) do
    if socket.assigns.can_manage do
      attrs = socket.assigns.draft |> Map.take(~w(name kind scope))

      attrs =
        if attrs["kind"] == "dynamic", do: Map.put(attrs, "rules", rules(socket)), else: attrs

      result =
        if socket.assigns.live_action == :edit do
          updates = Map.take(attrs, ~w(name rules))

          Segments.update(
            socket.assigns.current_staff,
            socket.assigns.group.id,
            Map.put(updates, "expected_revision", socket.assigns.group.revision)
          )
        else
          Segments.create(
            socket.assigns.current_staff,
            attrs,
            socket.assigns.selected_branches,
            Map.keys(socket.assigns.selected_clients)
          )
        end

      case result do
        {:ok, group} ->
          {:noreply, push_navigate(socket, to: ~p"/staff/segments/#{group.id}")}

        {:error, :stale} ->
          {:noreply,
           put_flash(socket, :error, "Сегмент изменился. Откройте его заново перед сохранением")}

        _ ->
          {:noreply, put_flash(socket, :error, "Не удалось сохранить сегмент")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_member", %{"id" => id}, socket) do
    case Segments.add_member(socket.assigns.current_staff, socket.assigns.group.id, id) do
      :ok -> {:noreply, reload_members(socket)}
      _ -> {:noreply, put_flash(socket, :error, "Клиент не подходит для этого сегмента")}
    end
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    case Segments.remove_member(socket.assigns.current_staff, socket.assigns.group.id, id) do
      :ok -> {:noreply, reload_members(socket)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("more_members", _, socket) do
    after_id = List.last(socket.assigns.members) && List.last(socket.assigns.members).id

    case Segments.list_members(socket.assigns.current_staff, socket.assigns.group.id,
           after: after_id
         ) do
      {:ok, more} ->
        {:noreply,
         assign(socket,
           members: socket.assigns.members ++ more,
           has_more_members: length(more) == 50
         )}

      _ ->
        {:noreply, socket}
    end
  end

  defp reload_members(socket) do
    {:ok, members} = Segments.list_members(socket.assigns.current_staff, socket.assigns.group.id)
    assign(socket, members: members, has_more_members: length(members) == 50)
  end

  defp rules(socket),
    do: %{
      "version" => 1,
      "match" => socket.assigns.draft["match"],
      "conditions" => socket.assigns.conditions
    }

  defp parse_value(metric, text) when metric in ["total_spent", "avg_check"] do
    case Decimal.parse(text || "") do
      {rubles, ""} ->
        kopecks = Decimal.mult(rubles, 100)

        if Decimal.equal?(kopecks, Decimal.round(kopecks, 0)),
          do: Decimal.to_integer(kopecks),
          else: -1

      _ ->
        -1
    end
  end

  defp parse_value(_metric, text) do
    case Integer.parse(text || "") do
      {number, ""} -> number
      _ -> -1
    end
  end

  defp metric_label("days_since_last_order"), do: "Полных суток без покупок"
  defp metric_label("order_count"), do: "Количество заказов"
  defp metric_label("total_spent"), do: "Сумма покупок"
  defp metric_label("avg_check"), do: "Средний чек"
  defp metric_label(_), do: "Показатель"

  defp condition_label(%{"metric" => metric, "op" => op, "value" => value}) do
    comparison = %{"eq" => "равно", "gte" => "не меньше", "lte" => "не больше"}[op]

    display =
      if metric in ["total_spent", "avg_check"], do: "#{Decimal.div(value, 100)} ₽", else: value

    "#{metric_label(metric)} #{comparison} #{display}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl space-y-6 p-4 sm:p-8">
      <header class="flex items-center justify-between gap-4">
        <div>
          <p class="text-sm uppercase tracking-wide text-zinc-500">Клиенты</p><h1 class="text-3xl font-semibold">
            Сегменты
          </h1>
        </div>
        <.link
          :if={@can_manage and @live_action not in [:new, :edit]}
          navigate={~p"/staff/segments/new"}
          class="btn btn-primary"
        >Создать сегмент</.link>
      </header>

      <section :if={@live_action == :index} id="segment-list" class="space-y-3" phx-update="stream">
        <div
          :for={{dom_id, group} <- @streams.groups}
          id={dom_id}
          class="rounded-xl border border-zinc-200 bg-white p-4 shadow-sm transition hover:shadow-md"
        >
          <.link navigate={~p"/staff/segments/#{group.id}"} class="block font-semibold">{group.name}</.link>
          <p class="text-sm text-zinc-500">
            {if group.kind == :manual, do: "Ручной", else: "Динамический"} · {if group.scope ==
                                                                                   :franchise,
                                                                                 do: "Вся сеть",
                                                                                 else:
                                                                                   "Выбранные филиалы"}
          </p>
        </div>
      </section>
      <.link
        :if={@live_action == :index and @after_id}
        patch={~p"/staff/segments"}
        class="text-sm text-zinc-600"
      >К началу списка</.link>
      <.link
        :if={@live_action == :index and @last_group_id}
        patch={~p"/staff/segments?after=#{@last_group_id}"}
        class="btn btn-ghost"
      >Следующая страница</.link>

      <section
        :if={@live_action in [:new, :edit]}
        id="segment-wizard"
        class="rounded-2xl border border-zinc-200 bg-white p-6 shadow-sm"
      >
        <p class="mb-5 text-sm text-zinc-500">Шаг {@step} из 3</p>
        <.form
          :if={@step == 1}
          for={@form}
          id="segment-details-form"
          phx-submit="details"
          class="space-y-4"
        >
          <.input field={@form[:name]} type="text" label="Название" required />
          <.input
            :if={@live_action == :new}
            field={@form[:kind]}
            type="select"
            label="Тип"
            options={[{"Ручной", "manual"}, {"Динамический", "dynamic"}]}
          />
          <.input
            :if={@live_action == :new}
            field={@form[:scope]}
            type="select"
            label="Охват"
            options={[{"Выбранные филиалы", "branches"}, {"Вся сеть", "franchise"}]}
          />
          <p :if={@live_action == :edit} class="text-sm text-zinc-500">
            Тип и охват сохраняются после создания.
          </p>
          <button class="btn btn-primary">Далее</button>
        </.form>

        <div :if={@step == 2} class="space-y-5">
          <div
            :if={@draft["scope"] == "branches" and @live_action == :new}
            id="segment-branches"
            class="space-y-2"
          >
            <h2 class="font-medium">Филиалы</h2>
            <button
              :for={branch <- @branches}
              id={"branch-#{branch.id}"}
              type="button"
              phx-click="toggle_branch"
              phx-value-id={branch.id}
              class={[
                "mr-2 rounded-full border px-3 py-1 text-sm",
                branch.id in @selected_branches && "bg-indigo-600 text-white"
              ]}
            >{branch.name}</button>
          </div>
          <div :if={@draft["kind"] == "dynamic"} id="segment-conditions" class="space-y-3">
            <h2 class="font-medium">Условия</h2>
            <p class="text-sm text-zinc-500">
              Суммы вводятся в рублях; срок с последнего заказа — полные сутки.
            </p>
            <.form for={@form} id="segment-match-form" phx-change="set_match">
              <.input
                field={@form[:match]}
                type="select"
                label="Совпадение условий"
                options={[{"Все условия", "all"}, {"Любое условие", "any"}]}
              />
            </.form>
            <.form
              for={@condition_form}
              id="segment-condition-form"
              phx-change="change_condition"
              phx-submit="add_condition"
              class="flex flex-wrap gap-2"
            >
              <.input
                field={@condition_form[:metric]}
                type="select"
                label="Показатель"
                options={[
                  {"Дней с последнего заказа", "days_since_last_order"},
                  {"Количество заказов", "order_count"},
                  {"Сумма покупок", "total_spent"},
                  {"Средний чек", "avg_check"}
                ]}
              />
              <.input
                field={@condition_form[:op]}
                type="select"
                label="Сравнение"
                options={[{"Равно", "eq"}, {"Не меньше", "gte"}, {"Не больше", "lte"}]}
              />
              <.input
                field={@condition_form[:value]}
                type="number"
                label={
                  if @condition_metric in ["total_spent", "avg_check"], do: "Рубли", else: "Значение"
                }
                min="0"
                step={if @condition_metric in ["total_spent", "avg_check"], do: "0.01", else: "1"}
              />
              <button class="btn btn-outline self-end">Добавить условие</button>
            </.form>
            <div
              :for={{condition, index} <- Enum.with_index(@conditions)}
              id={"condition-#{index}"}
              class="flex justify-between border-b py-2 text-sm"
            >
              <span>{condition_label(condition)}</span>
              <button type="button" phx-click="remove_condition" phx-value-index={index}>Удалить</button>
            </div>
          </div>
          <div :if={@draft["kind"] == "manual" and @live_action == :new} id="segment-client-picker">
            <h2 class="font-medium">Клиенты</h2>
            <.form
              for={@search_form}
              id="segment-client-search"
              phx-submit="search_clients"
              class="flex gap-2"
            >
              <.input field={@search_form[:query]} type="text" label="Имя или телефон" />
              <button class="btn btn-outline self-end">Найти</button>
            </.form>
            <div
              :for={client <- @candidates}
              id={"candidate-#{client.id}"}
              class="flex justify-between py-2 text-sm"
            >
              <span>{client.name} · {client.phone}</span><button
                type="button"
                phx-click="select_client"
                phx-value-id={client.id}
              >Добавить</button>
            </div>
            <div
              :for={{id, client} <- @selected_clients}
              id={"selected-#{id}"}
              class="flex justify-between py-2 text-sm"
            >
              <span>{client.name}</span><button
                type="button"
                phx-click="remove_selected_client"
                phx-value-id={id}
              >Убрать</button>
            </div>
          </div>
          <p :if={@draft["kind"] == "manual" and @live_action == :edit} class="text-sm text-zinc-500">
            Участников можно изменить на странице сегмента.
          </p>
          <div class="flex gap-2">
            <button type="button" phx-click="back" class="btn btn-ghost">Назад</button><button
              id="segment-review"
              type="button"
              phx-click="review"
              class="btn btn-primary"
            >Проверить</button>
          </div>
        </div>
        <div :if={@step == 3} id="segment-review-panel" class="space-y-4">
          <h2 class="text-xl font-semibold">Проверьте сегмент</h2>
          <p>
            {@draft["name"]} · {if @draft["kind"] == "manual", do: "Ручной", else: "Динамический"}
          </p>
          <p>
            Охват: {if @draft["scope"] == "franchise",
              do: "Все доступные филиалы",
              else: "Выбранные филиалы"}
          </p>
          <p :if={@draft["kind"] == "manual"}>Клиентов: {map_size(@selected_clients)}</p>
          <p :if={@draft["kind"] == "dynamic"}>Условий: {length(@conditions)}</p>
          <div class="flex gap-2">
            <button type="button" phx-click="back" class="btn btn-ghost">Назад</button><button
              id="segment-save"
              type="button"
              phx-click="save"
              class="btn btn-primary"
            >Сохранить</button>
          </div>
        </div>
      </section>

      <section
        :if={@live_action == :show and @group}
        id="segment-detail"
        class="space-y-5 rounded-2xl border bg-white p-6"
      >
        <.link navigate={~p"/staff/segments"} class="text-sm text-indigo-600">← Все сегменты</.link>
        <h2 class="text-2xl font-semibold">{@group.name}</h2>
        <.link
          :if={@can_manage}
          navigate={~p"/staff/segments/#{@group.id}/edit"}
          id="segment-edit-link"
          class="text-sm text-indigo-600"
        >Изменить</.link>
        <p class="text-sm text-zinc-500">
          {if @group.kind == :manual, do: "Ручной", else: "Динамический"} · {if @group.scope ==
                                                                                  :franchise,
                                                                                do: "Вся сеть",
                                                                                else:
                                                                                  "Выбранные филиалы"}
        </p>
        <p :if={@group.kind == :dynamic} class="text-sm">
          Последнее обновление: {if @group.last_refreshed_at,
            do:
              Calendar.strftime(
                Delivest.LocalTime.local(@group.last_refreshed_at, nil),
                "%d.%m.%Y %H:%M"
              ) <> " (" <> Delivest.LocalTime.timezone(nil) <> ")",
            else: "Ещё не рассчитан"}
        </p>
        <p :if={@group.last_refresh_error} class="text-sm text-red-600">
          Последнее обновление не удалось: {@group.last_refresh_error}
        </p>
        <div id="segment-members" class="space-y-2">
          <h3 class="font-medium">Участники</h3>
          <div
            :for={client <- @members}
            id={"member-#{client.id}"}
            class="flex justify-between rounded-lg border p-3 text-sm"
          >
            <span>{client.name} · {client.phone}</span>
            <button
              :if={@can_manage and @group.kind == :manual}
              type="button"
              phx-click="remove_member"
              phx-value-id={client.id}
            >Удалить</button>
          </div>
          <button
            :if={@has_more_members}
            type="button"
            phx-click="more_members"
            class="btn btn-ghost"
          >Показать ещё</button>
        </div>
        <div :if={@can_manage and @group.kind == :manual} id="segment-add-member">
          <.form
            for={@search_form}
            id="segment-member-search"
            phx-submit="search_clients"
            class="flex gap-2"
          >
            <.input field={@search_form[:query]} type="text" label="Найти клиента" /><button class="btn btn-outline self-end">Найти</button>
          </.form>
          <div
            :for={client <- @candidates}
            id={"candidate-#{client.id}"}
            class="flex justify-between py-2 text-sm"
          >
            <span>{client.name} · {client.phone}</span><button
              type="button"
              phx-click="add_member"
              phx-value-id={client.id}
            >Добавить</button>
          </div>
        </div>
      </section>
    </div>
    """
  end
end
