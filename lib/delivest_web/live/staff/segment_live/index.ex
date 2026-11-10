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
          policy_impact: nil,
          pending_member: nil,
          members: [],
          has_more_members: false,
          candidates: [],
          selected_clients: %{},
          selected_branches: [],
          conditions: [],
          condition_metric: "order_count",
          condition_error: nil,
          scope_error: nil,
          search_attempted: false,
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
            to_form(%{"metric" => "order_count", "op" => "gte", "value" => ""}, as: :condition),
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
          do:
            {:noreply,
             assign(socket,
               group: nil,
               policy_impact: nil,
               pending_member: nil,
               step: 1,
               draft: %{"name" => "", "kind" => "manual", "scope" => "branches", "match" => "all"},
               form:
                 to_form(
                   %{"name" => "", "kind" => "manual", "scope" => "branches", "match" => "all"},
                   as: :segment
                 ),
               selected_branches: [],
               selected_clients: %{},
               conditions: [],
               condition_metric: "order_count",
               condition_error: nil,
               scope_error: nil,
               condition_form:
                 to_form(%{"metric" => "order_count", "op" => "gte", "value" => ""},
                   as: :condition
                 ),
               candidates: [],
               search_attempted: false,
               search_form: to_form(%{"query" => ""}, as: :search)
             )},
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
                 policy_impact: nil,
                 pending_member: nil,
                 draft: draft,
                 selected_branches: Enum.map(group.branches, & &1.id),
                 conditions: (group.rules && group.rules["conditions"]) || [],
                 condition_error: nil,
                 scope_error: nil,
                 condition_metric: "order_count",
                 condition_form:
                   to_form(%{"metric" => "order_count", "op" => "gte", "value" => ""},
                     as: :condition
                   ),
                 candidates: [],
                 search_attempted: false,
                 search_form: to_form(%{"query" => ""}, as: :search),
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
               policy_impact: nil,
               pending_member: nil,
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

    kind_changed =
      socket.assigns.live_action == :new and draft["kind"] != socket.assigns.draft["kind"]

    selection_changed =
      kind_changed or
        (socket.assigns.live_action == :new and draft["scope"] != socket.assigns.draft["scope"])

    socket =
      if selection_changed do
        socket
        |> clear_client_selection()
        |> assign(
          selected_branches:
            if(draft["scope"] == "franchise", do: [], else: socket.assigns.selected_branches),
          conditions: if(kind_changed, do: [], else: socket.assigns.conditions),
          condition_metric:
            if(kind_changed, do: "order_count", else: socket.assigns.condition_metric),
          condition_error: if(kind_changed, do: nil, else: socket.assigns.condition_error),
          condition_form:
            if(kind_changed,
              do:
                to_form(%{"metric" => "order_count", "op" => "gte", "value" => ""},
                  as: :condition
                ),
              else: socket.assigns.condition_form
            )
        )
      else
        socket
      end

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

        {:noreply,
         socket
         |> clear_client_selection()
         |> assign(selected_branches: selected, scope_error: nil)}
      else
        {:noreply, socket}
      end
    end
  end

  def handle_event("add_condition", %{"condition" => params}, socket) do
    case append_condition(socket, params) do
      {:ok, socket} ->
        {:noreply, socket}

      {:error, message} ->
        {:noreply,
         assign(socket, condition_error: message, condition_form: to_form(params, as: :condition))}
    end
  end

  def handle_event("change_condition", %{"condition" => params}, socket) do
    {:noreply,
     assign(socket,
       condition_metric: params["metric"],
       condition_error: nil,
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
           {:ok, clients} ->
             if socket.assigns.live_action == :new do
               Enum.reject(clients, &Map.has_key?(socket.assigns.selected_clients, &1.id))
             else
               Enum.reject(clients, &Segments.published_member?(socket.assigns.group, &1.id))
             end

           _ ->
             []
         end,
       search_form: to_form(%{"query" => query}, as: :search),
       search_attempted: true
     )}
  end

  def handle_event("select_client", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.candidates, &(&1.id == id)) do
      nil ->
        {:noreply, socket}

      client ->
        {:noreply,
         assign(socket,
           selected_clients: Map.put(socket.assigns.selected_clients, id, client),
           candidates: Enum.reject(socket.assigns.candidates, &(&1.id == id))
         )}
    end
  end

  def handle_event("remove_selected_client", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket, selected_clients: Map.delete(socket.assigns.selected_clients, id))}

  def handle_event("review", _, socket) do
    if socket.assigns.live_action == :new and socket.assigns.draft["scope"] == "branches" and
         socket.assigns.selected_branches == [] do
      {:noreply, assign(socket, scope_error: "Выберите хотя бы один филиал.")}
    else
      review_conditions(socket)
    end
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
            updates
            |> Map.put("expected_revision", socket.assigns.group.revision)
            |> Map.put(
              "policy_confirmation",
              socket.assigns.policy_impact && socket.assigns.policy_impact.fingerprint
            )
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

        {:error, {:policy_confirmation_required, impact}} ->
          {:noreply, assign(socket, policy_impact: impact)}

        _ ->
          {:noreply, put_flash(socket, :error, "Не удалось сохранить сегмент")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_member", %{"id" => id}, socket) do
    mutate_member(socket, :add, id)
  end

  def handle_event("remove_member", %{"id" => id}, socket) do
    mutate_member(socket, :remove, id)
  end

  def handle_event("confirm_member", _, socket) do
    case socket.assigns.pending_member do
      {action, id, revision, fingerprint} ->
        mutate_member(socket, action, id, %{
          expected_revision: revision,
          policy_confirmation: fingerprint
        })

      nil ->
        {:noreply, socket}
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

  defp mutate_member(socket, action, id, opts \\ %{}) do
    result =
      case action do
        :add ->
          Segments.add_member(socket.assigns.current_staff, socket.assigns.group.id, id, opts)

        :remove ->
          Segments.remove_member(socket.assigns.current_staff, socket.assigns.group.id, id, opts)
      end

    case result do
      :ok ->
        {:noreply,
         socket
         |> assign(
           group: elem(Segments.get(socket.assigns.current_staff, socket.assigns.group.id), 1),
           pending_member: nil,
           policy_impact: nil,
           candidates:
             if(action == :add,
               do: Enum.reject(socket.assigns.candidates, &(&1.id == id)),
               else: socket.assigns.candidates
             )
         )
         |> reload_members()}

      {:error, {:policy_confirmation_required, impact}} ->
        {:noreply,
         assign(socket,
           policy_impact: impact,
           pending_member: {action, id, socket.assigns.group.revision, impact.fingerprint}
         )}

      {:error, :stale} ->
        {:noreply, put_flash(socket, :error, "Сегмент изменился. Откройте его заново")}

      _ ->
        {:noreply, put_flash(socket, :error, "Не удалось изменить участника")}
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

  defp clear_client_selection(socket) do
    had_clients? = map_size(socket.assigns.selected_clients) > 0

    socket =
      assign(socket,
        selected_clients: %{},
        candidates: [],
        search_attempted: false,
        search_form: to_form(%{"query" => ""}, as: :search)
      )

    if had_clients?,
      do: put_flash(socket, :info, "Тип или охват изменился. Выберите клиентов заново."),
      else: socket
  end

  defp review_conditions(socket) do
    if socket.assigns.draft["kind"] == "manual" do
      {:noreply, assign(socket, step: 3)}
    else
      params = socket.assigns.condition_form.params
      pending = String.trim(to_string(params["value"] || ""))

      result =
        if pending == "" and socket.assigns.conditions != [],
          do: {:ok, socket},
          else: append_condition(socket, params)

      case result do
        {:ok, updated} -> {:noreply, assign(updated, step: 3)}
        {:error, message} -> {:noreply, assign(socket, condition_error: message)}
      end
    end
  end

  defp append_condition(socket, params) do
    value = String.trim(to_string(params["value"] || ""))
    metric = params["metric"]

    message =
      cond do
        value == "" ->
          "Укажите значение условия. Например, 1 заказ."

        parse_value(metric, value) < 0 ->
          if metric in ["total_spent", "avg_check"],
            do: "Введите неотрицательную сумму в рублях с точностью до копеек.",
            else: "Введите целое неотрицательное число."

        parse_value(metric, value) >
            if(metric in ["total_spent", "avg_check"], do: 1_000_000_000_000, else: 1_000_000) ->
          if metric in ["total_spent", "avg_check"],
            do: "Сумма слишком большая. Максимум — 10 000 000 000 ₽.",
            else: "Значение слишком большое. Максимум — 1 000 000."

        length(socket.assigns.conditions) >= 8 ->
          "Можно добавить не больше 8 условий."

        true ->
          nil
      end

    if message do
      {:error, message}
    else
      rule = %{"metric" => metric, "op" => params["op"], "value" => parse_value(metric, value)}
      candidate = socket.assigns.conditions ++ [rule]
      rules = Map.put(rules(socket), "conditions", candidate)

      if match?({:ok, _}, Segments.Rules.validate(rules)) do
        {:ok,
         assign(socket,
           conditions: candidate,
           condition_error: nil,
           condition_form:
             to_form(%{"metric" => metric, "op" => params["op"], "value" => ""}, as: :condition)
         )}
      else
        {:error, "Выберите показатель и сравнение для условия."}
      end
    end
  end

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

  defp branch_names(branches, selected_ids) do
    branches
    |> Enum.filter(&(&1.id in selected_ids))
    |> Enum.map_join(", ", & &1.name)
  end

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
      <header class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <p class="text-sm uppercase tracking-wide text-base-content/60">Клиенты</p><h1 class="text-3xl font-semibold">
            Сегменты
          </h1>
          <p class="mt-2 text-sm text-base-content/70">
            Группируйте клиентов вручную или по их выполненным заказам.
          </p>
        </div>
        <.link
          :if={@can_manage and @live_action not in [:new, :edit]}
          navigate={~p"/staff/segments/new"}
          class="btn btn-primary"
        >Создать сегмент</.link>
      </header>

      <section :if={@live_action == :index} id="segment-list" class="space-y-3" phx-update="stream">
        <div
          id="segment-type-help"
          class="rounded-xl border border-base-300 bg-base-200 p-4 text-sm text-base-content/75"
        >
          <strong>Ручной:</strong>
          выбираете клиентов сами. <strong>Динамический:</strong>
          клиенты подбираются по условиям выполненных заказов; состав обновляется фоновым пересчётом, обычно раз в сутки.
        </div>
        <div
          :for={{dom_id, group} <- @streams.groups}
          id={dom_id}
          class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm transition hover:border-primary/40 hover:shadow-md"
        >
          <.link navigate={~p"/staff/segments/#{group.id}"} class="block font-semibold">{group.name}</.link>
          <p class="mt-1 text-sm text-base-content/65">
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
        class="text-sm text-primary"
      >К началу списка</.link>
      <.link
        :if={@live_action == :index and @last_group_id}
        patch={~p"/staff/segments?after=#{@last_group_id}"}
        class="btn btn-ghost"
      >Следующая страница</.link>

      <section
        :if={@live_action in [:new, :edit]}
        id="segment-wizard"
        class="rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm sm:p-7"
      >
        <.link navigate={~p"/staff/segments"} class="mb-4 inline-block text-sm text-primary">← Все сегменты</.link>
        <p class="text-sm font-medium text-primary">Шаг {@step} из 3</p>
        <h2 class="mb-5 mt-1 text-xl font-semibold">
          {Enum.at(["Название и тип", "Кого включить", "Проверка"], @step - 1)}
        </h2>
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
          <p :if={@live_action == :new} class="text-sm text-base-content/70">
            <strong>Ручной:</strong>
            вы сами добавляете и убираете клиентов. <strong>Динамический:</strong>
            состав рассчитывается по условиям на основе выполненных заказов и обновляется периодически.
          </p>
          <.input
            :if={@live_action == :new}
            field={@form[:scope]}
            type="select"
            label="Охват"
            options={
              [{"Выбранные филиалы", "branches"}] ++
                if(Identity.can?(@current_staff, "segments.network"),
                  do: [{"Вся сеть", "franchise"}],
                  else: []
                )
            }
          />
          <p :if={@live_action == :new} class="text-sm text-base-content/70">
            Выберите филиалы на следующем шаге или охватите всю доступную сеть.
          </p>
          <p :if={@live_action == :edit} class="text-sm text-base-content/70">
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
            <h3 class="font-semibold">Филиалы</h3>
            <p class="text-sm text-base-content/70">Выберите хотя бы один филиал.</p>
            <button
              :for={branch <- @branches}
              id={"branch-#{branch.id}"}
              type="button"
              phx-click="toggle_branch"
              phx-value-id={branch.id}
              class={[
                "btn btn-sm mr-2 rounded-full",
                if(branch.id in @selected_branches, do: "btn-primary", else: "btn-outline")
              ]}
              aria-pressed={branch.id in @selected_branches}
            >{branch.name}</button>
            <p :if={@scope_error} class="text-sm text-error" role="alert">{@scope_error}</p>
          </div>
          <div :if={@draft["kind"] == "dynamic"} id="segment-conditions" class="space-y-3">
            <h3 class="font-semibold">Условия</h3>
            <p class="text-sm text-base-content/70">
              Учитываются только выполненные заказы. Суммы вводятся в рублях; срок с последнего заказа — полные сутки.
            </p>
            <.form for={@form} id="segment-match-form" phx-change="set_match">
              <.input
                field={@form[:match]}
                type="select"
                label="Совпадение условий"
                options={[{"Все условия", "all"}, {"Любое условие", "any"}]}
              />
            </.form>
            <p class="text-sm text-base-content/70">
              «Все» — клиент соответствует каждому условию. «Любое» — достаточно одного.
            </p>
            <.form
              for={@condition_form}
              id="segment-condition-form"
              phx-change="change_condition"
              phx-submit="add_condition"
              class="grid gap-3 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_minmax(7rem,0.7fr)_auto] md:items-end [&_fieldset]:mb-0 [&_fieldset]:pb-0"
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
                  if @condition_metric in ["total_spent", "avg_check"],
                    do: "Сумма, ₽",
                    else: "Значение"
                }
                min="0"
                step={if @condition_metric in ["total_spent", "avg_check"], do: "0.01", else: "1"}
              />
              <button
                class="btn btn-outline w-full md:w-auto"
                phx-disable-with="Добавляем…"
              >Добавить условие</button>
            </.form>
            <p :if={@condition_error} id="condition-error" class="text-sm text-error" role="alert">
              {@condition_error}
            </p>
            <p class="text-xs text-base-content/60">
              Можно нажать «Проверить» сразу после ввода: заполненное условие добавится автоматически.
            </p>
            <div
              :for={{condition, index} <- Enum.with_index(@conditions)}
              id={"condition-#{index}"}
              class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-base-300 bg-base-200 p-3 text-sm"
            >
              <span>{condition_label(condition)}</span>
              <button
                type="button"
                phx-click="remove_condition"
                phx-value-index={index}
                class="btn btn-ghost btn-sm text-error"
              >Убрать</button>
            </div>
          </div>
          <div
            :if={@draft["kind"] == "manual" and @live_action == :new}
            id="segment-client-picker"
            class="space-y-4"
          >
            <h3 class="font-semibold">Клиенты в сегменте</h3>
            <p class="text-sm text-base-content/70">
              Найдите клиента по имени или телефону и добавьте его. Состав можно изменить позже.
            </p>
            <p
              :if={@draft["scope"] == "branches" and @selected_branches == []}
              class="text-sm text-warning"
            >
              Сначала выберите филиал выше, затем ищите клиентов.
            </p>
            <.form
              for={@search_form}
              id="segment-client-search"
              phx-submit="search_clients"
              class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end [&_fieldset]:mb-0 [&_fieldset]:pb-0"
            >
              <.input field={@search_form[:query]} type="text" label="Имя или телефон" />
              <button class="btn btn-outline w-full sm:w-auto" phx-disable-with="Ищем…">Найти</button>
            </.form>
            <div class="grid gap-4 lg:grid-cols-2">
              <div class="min-w-0 rounded-xl border border-base-300 p-4">
                <h4 class="mb-2 font-medium">Результаты поиска</h4>
                <p :if={!@search_attempted} class="text-sm text-base-content/60">
                  Введите хотя бы 2 символа для поиска.
                </p>
                <p :if={@search_attempted and @candidates == []} class="text-sm text-base-content/60">
                  Новых клиентов среди найденных нет. Уточните имя или телефон.
                </p>
                <div class="max-h-64 overflow-y-auto">
                  <div
                    :for={client <- @candidates}
                    id={"candidate-#{client.id}"}
                    class="flex items-center justify-between gap-2 border-t border-base-300 py-2 text-sm"
                  >
                    <span class="min-w-0"><span class="block truncate font-medium">{client.name}</span><span class="block text-xs text-base-content/65">{client.phone}</span></span><button
                      type="button"
                      phx-click="select_client"
                      phx-value-id={client.id}
                      class="btn btn-outline btn-sm shrink-0"
                      phx-disable-with="Добавляем…"
                    >Добавить</button>
                  </div>
                </div>
                <p :if={@search_attempted} class="mt-2 text-xs text-base-content/60">
                  Поиск показывает до 20 совпадений. Для точного поиска укажите телефон или полное имя.
                </p>
              </div>
              <div class="min-w-0 rounded-xl border border-base-300 bg-base-200 p-4">
                <h4 class="mb-2 font-medium">Выбрано: {map_size(@selected_clients)}</h4>
                <p :if={map_size(@selected_clients) == 0} class="text-sm text-base-content/60">
                  Пока никого нет. Можно сохранить пустой сегмент и добавить клиентов позже.
                </p>
                <div class="max-h-64 overflow-y-auto">
                  <div
                    :for={{id, client} <- @selected_clients}
                    id={"selected-#{id}"}
                    class="flex items-center justify-between gap-2 border-t border-base-300 py-2 text-sm"
                  >
                    <span class="min-w-0"><span class="block truncate font-medium">{client.name}</span><span class="block text-xs text-base-content/65">{client.phone}</span></span><button
                      type="button"
                      phx-click="remove_selected_client"
                      phx-value-id={id}
                      class="btn btn-ghost btn-sm shrink-0 text-error"
                      phx-disable-with="Убираем…"
                      aria-label={"Убрать #{client.name} из сегмента"}
                    >Убрать</button>
                  </div>
                </div>
              </div>
            </div>
          </div>
          <p
            :if={@draft["kind"] == "manual" and @live_action == :edit}
            class="text-sm text-base-content/70"
          >
            Участников можно изменить на странице сегмента.
          </p>
          <div class="flex gap-2">
            <button type="button" phx-click="back" class="btn btn-ghost">Назад</button><button
              id="segment-review"
              type="button"
              phx-click="review"
              class="btn btn-primary"
              phx-disable-with="Проверяем…"
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
              else: branch_names(@branches, @selected_branches)}
          </p>
          <p :if={@draft["kind"] == "manual" and @live_action == :new}>
            Клиентов: {map_size(@selected_clients)}
          </p>
          <p :if={@draft["kind"] == "manual" and @live_action == :edit}>
            Состав участников сохранится. Изменить его можно на странице сегмента.
          </p>
          <div
            :if={@draft["kind"] == "dynamic"}
            class="rounded-xl border border-base-300 bg-base-200 p-4"
          >
            <p class="font-medium">
              {if @draft["match"] == "all", do: "Все условия", else: "Любое условие"} · {length(
                @conditions
              )} услов.
            </p>
            <ul class="mt-2 list-disc space-y-1 pl-5 text-sm">
              <li :for={condition <- @conditions}>{condition_label(condition)}</li>
            </ul>
            <p class="mt-3 text-xs text-base-content/65">
              Состав обновляется фоновым пересчётом, обычно раз в сутки.
            </p>
          </div>
          <div
            :if={@policy_impact}
            id="segment-policy-impact"
            class="rounded-xl border border-warning/40 bg-warning/10 p-4 text-sm text-base-content"
          >
            <p>
              Изменение затронет действующие политики. Новые условия применятся к будущим проверкам; прошлые выдачи сохранятся.
            </p>
            <ul class="mt-2 list-disc pl-5">
              <li :for={policy <- @policy_impact.policies}>{policy.name}</li>
            </ul>
            <p class="mt-2 font-medium">
              Нажмите «Подтвердить и сохранить», чтобы применить изменение.
            </p>
          </div>
          <div class="flex gap-2">
            <button type="button" phx-click="back" class="btn btn-ghost">Назад</button><button
              id="segment-save"
              type="button"
              phx-click="save"
              class="btn btn-primary"
              phx-disable-with="Сохраняем…"
            >{if @policy_impact, do: "Подтвердить и сохранить", else: "Сохранить"}</button>
          </div>
        </div>
      </section>

      <section
        :if={@live_action == :show and @group}
        id="segment-detail"
        class="space-y-5 rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm sm:p-7"
      >
        <.link navigate={~p"/staff/segments"} class="text-sm text-primary">← Все сегменты</.link>
        <h2 class="text-2xl font-semibold">{@group.name}</h2>
        <.link
          :if={@can_manage}
          navigate={~p"/staff/segments/#{@group.id}/edit"}
          id="segment-edit-link"
          class="btn btn-outline btn-sm"
        >Изменить</.link>
        <p class="text-sm text-base-content/70">
          {if @group.kind == :manual, do: "Ручной", else: "Динамический"} · {if @group.scope ==
                                                                                  :franchise,
                                                                                do: "Вся сеть",
                                                                                else:
                                                                                  "Выбранные филиалы"}
        </p>
        <p :if={@group.kind == :manual} class="text-sm text-base-content/70">
          Ручной сегмент: вы сами добавляете и убираете участников.
        </p>
        <div
          :if={@group.kind == :dynamic and @group.rules}
          class="rounded-xl border border-base-300 bg-base-200 p-4"
        >
          <h3 class="font-semibold">Условия отбора</h3>
          <p class="mt-1 text-sm text-base-content/70">
            {if @group.rules["match"] == "all",
              do: "Нужно выполнить все условия",
              else: "Достаточно любого условия"}. Учитываются выполненные заказы.
          </p>
          <ul class="mt-2 list-disc space-y-1 pl-5 text-sm">
            <li :for={condition <- @group.rules["conditions"]}>{condition_label(condition)}</li>
          </ul>
          <p class="mt-2 text-xs text-base-content/65">
            Состав обновляется фоновым пересчётом, обычно раз в сутки.
          </p>
        </div>
        <p :if={@group.kind == :dynamic} class="text-sm">
          Последнее обновление: {if @group.last_refreshed_at,
            do:
              Calendar.strftime(
                Delivest.LocalTime.local(@group.last_refreshed_at, nil),
                "%d.%m.%Y %H:%M"
              ) <> " (" <> Delivest.LocalTime.timezone(nil) <> ")",
            else: "Ещё не рассчитан"}
        </p>
        <p :if={@group.last_refresh_error} class="text-sm text-error">
          Последнее обновление не удалось: {@group.last_refresh_error}
        </p>
        <div id="segment-members" class="space-y-2">
          <h3 class="font-medium">Участники</h3>
          <p :if={@members == [] and @group.kind == :manual} class="text-sm text-base-content/65">
            Пока никого нет. Найдите клиента ниже и добавьте в сегмент.
          </p>
          <p :if={@members == [] and @group.kind == :dynamic} class="text-sm text-base-content/65">
            Совпадений пока нет или первый пересчёт ещё не завершён.
          </p>
          <div
            :if={@pending_member}
            id="segment-member-impact"
            class="rounded-xl border border-warning/40 bg-warning/10 p-4 text-sm"
          >
            <p>Изменение состава затронет политики. Прошлые выдачи сохранятся:</p>
            <ul class="list-disc pl-5">
              <li :for={policy <- @policy_impact.policies}>{policy.name}</li>
            </ul>
            <button
              id="segment-confirm-member"
              type="button"
              phx-click="confirm_member"
              class="btn btn-primary mt-2"
            >Подтвердить изменение</button>
          </div>
          <div
            :for={client <- @members}
            id={"member-#{client.id}"}
            class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-base-300 p-3 text-sm"
          >
            <span>{client.name} · {client.phone}</span>
            <button
              :if={@can_manage and @group.kind == :manual}
              type="button"
              phx-click="remove_member"
              phx-value-id={client.id}
              class="btn btn-ghost btn-sm text-error"
              phx-disable-with="Убираем…"
            >Убрать из сегмента</button>
          </div>
          <button
            :if={@has_more_members}
            type="button"
            phx-click="more_members"
            class="btn btn-ghost"
          >Показать ещё</button>
        </div>
        <div
          :if={@can_manage and @group.kind == :manual}
          id="segment-add-member"
          class="space-y-3 rounded-xl border border-base-300 p-4"
        >
          <h3 class="font-semibold">Добавить клиента</h3>
          <.form
            for={@search_form}
            id="segment-member-search"
            phx-submit="search_clients"
            class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end [&_fieldset]:mb-0 [&_fieldset]:pb-0"
          >
            <.input field={@search_form[:query]} type="text" label="Найти клиента" /><button
              class="btn btn-outline w-full sm:w-auto"
              phx-disable-with="Ищем…"
            >Найти</button>
          </.form>
          <p :if={!@search_attempted} class="text-sm text-base-content/60">
            Введите хотя бы 2 символа имени или телефона.
          </p>
          <p :if={@search_attempted and @candidates == []} class="text-sm text-base-content/60">
            Новых клиентов среди найденных нет. Уточните имя или телефон.
          </p>
          <div
            :for={client <- @candidates}
            id={"candidate-#{client.id}"}
            class="flex flex-wrap items-center justify-between gap-2 border-t border-base-300 py-2 text-sm"
          >
            <span>{client.name} · {client.phone}</span><button
              type="button"
              phx-click="add_member"
              phx-value-id={client.id}
              class="btn btn-outline btn-sm"
              phx-disable-with="Добавляем…"
            >Добавить в сегмент</button>
          </div>
          <p :if={@search_attempted} class="text-xs text-base-content/60">
            Поиск показывает до 20 совпадений. Для точного поиска укажите телефон или полное имя.
          </p>
        </div>
      </section>
    </div>
    """
  end
end
