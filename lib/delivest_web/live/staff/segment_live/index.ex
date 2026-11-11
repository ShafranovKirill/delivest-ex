defmodule DelivestWeb.Staff.SegmentLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.{Features, Identity, Segments}

  @poll_duration 1_800_000

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
          calculation: nil,
          poll_token: nil,
          poll_until: nil,
          poll_count: 0,
          policy_impact: nil,
          pending_member: nil,
          active_tab: nil,
          client_page: nil,
          client_params: %{},
          client_search_error: nil,
          selected_branches: [],
          conditions: [],
          condition_metric: "order_count",
          condition_error: nil,
          name_error: nil,
          scope_error: nil,
          reviewing: false,
          after_id: nil,
          last_group_id: nil,
          draft: %{"name" => "", "kind" => "manual", "scope" => "branches", "match" => "all"},
          form:
            to_form(%{"name" => "", "kind" => "manual", "scope" => "branches", "match" => "all"},
              as: :segment
            ),
          condition_form:
            to_form(%{"metric" => "order_count", "op" => "gte", "value" => ""}, as: :condition),
          client_filter_form: to_form(%{"search" => ""}, as: :filter)
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

    socket =
      assign(socket, poll_token: make_ref(), poll_until: nil, poll_count: 0, calculation: nil)

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
               reviewing: false,
               draft: %{"name" => "", "kind" => "manual", "scope" => "branches", "match" => "all"},
               form:
                 to_form(
                   %{"name" => "", "kind" => "manual", "scope" => "branches", "match" => "all"},
                   as: :segment
                 ),
               selected_branches: [],
               conditions: [],
               condition_metric: "order_count",
               condition_error: nil,
               name_error: nil,
               scope_error: nil,
               condition_form:
                 to_form(%{"metric" => "order_count", "op" => "gte", "value" => ""},
                   as: :condition
                 ),
               client_page: nil
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
                 reviewing: false,
                 draft: draft,
                 selected_branches: Enum.map(group.branches, & &1.id),
                 conditions: (group.rules && group.rules["conditions"]) || [],
                 condition_error: nil,
                 name_error: nil,
                 scope_error: nil,
                 condition_metric: "order_count",
                 condition_form:
                   to_form(%{"metric" => "order_count", "op" => "gte", "value" => ""},
                     as: :condition
                   ),
                 form: to_form(draft, as: :segment),
                 client_page: nil
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
            socket =
              socket
              |> assign(group: group, calculation: segment_status(staff, group))
              |> poll_segment()

            tab = if params["tab"] in ["clients", "settings"], do: params["tab"]

            if tab == "clients" do
              client_params =
                params
                |> Map.take(~w(page search sort direction mode))
                |> Map.put_new("mode", "members")

              case Segments.paginated_clients(staff, group.id, client_params) do
                {:ok, page} ->
                  {:noreply,
                   assign(socket,
                     group: group,
                     active_tab: tab,
                     client_page: page,
                     client_params: client_page_params(page),
                     client_filter_form: to_form(%{"search" => page.search}, as: :filter),
                     client_search_error: nil,
                     pending_member: nil,
                     policy_impact: nil
                   )}

                _ ->
                  {:noreply,
                   socket
                   |> put_flash(
                     :error,
                     "Не удалось открыть список с этими параметрами. Поиск сброшен."
                   )
                   |> push_patch(to: ~p"/staff/segments/#{group.id}?tab=clients")}
              end
            else
              {:noreply,
               assign(socket,
                 group: group,
                 active_tab: tab,
                 client_page: nil,
                 client_params: %{},
                 pending_member: nil,
                 policy_impact: nil
               )}
            end

          _ ->
            {:noreply, push_navigate(socket, to: ~p"/staff/segments")}
        end
    end
  end

  defp segment_status(staff, %{kind: :dynamic, id: id}) do
    case Segments.calculation_status(staff, id) do
      {:ok, status} -> status
      _ -> nil
    end
  end

  defp segment_status(_, _), do: nil

  defp poll_segment(socket) do
    if connected?(socket) && socket.assigns.calculation &&
         socket.assigns.calculation.state in [:queued, :running] do
      until_at = socket.assigns.poll_until || System.monotonic_time(:millisecond) + @poll_duration

      Process.send_after(
        self(),
        {:segment_poll, socket.assigns.poll_token, socket.assigns.group.id},
        if(socket.assigns.poll_count < 10, do: 1_500, else: 5_000)
      )

      assign(socket, poll_until: until_at, poll_count: socket.assigns.poll_count + 1)
    else
      socket
    end
  end

  @impl true
  def handle_info({:segment_poll, token, id}, socket) do
    if token == socket.assigns.poll_token && socket.assigns.live_action == :show &&
         socket.assigns.group && socket.assigns.group.id == id &&
         socket.assigns.poll_until &&
         System.monotonic_time(:millisecond) < socket.assigns.poll_until &&
         socket.assigns.calculation && socket.assigns.calculation.state in [:queued, :running] do
      case Segments.calculation_status(socket.assigns.current_staff, id) do
        {:ok, status} ->
          socket = assign(socket, calculation: status)

          socket =
            if status.state in [:ready, :error] do
              case Segments.get(socket.assigns.current_staff, id) do
                {:ok, group} ->
                  socket = assign(socket, group: group)

                  if socket.assigns.active_tab == "clients" && socket.assigns.client_page do
                    case Segments.paginated_clients(
                           socket.assigns.current_staff,
                           id,
                           socket.assigns.client_params
                         ) do
                      {:ok, page} ->
                        assign(socket, client_page: page, client_params: client_page_params(page))

                      _ ->
                        socket
                    end
                  else
                    socket
                  end

                _ ->
                  socket
              end
            else
              socket
            end

          {:noreply, poll_segment(socket)}

        _ ->
          {:noreply, assign(socket, calculation: nil)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event(
        "recalculate_segment",
        _,
        %{assigns: %{live_action: :show, can_manage: true, group: %{kind: :dynamic} = group}} =
          socket
      ) do
    case Segments.recalculate_now(socket.assigns.current_staff, group.id) do
      {:ok, status} ->
        {:noreply,
         socket
         |> assign(calculation: status, poll_until: nil, poll_count: 0, poll_token: make_ref())
         |> poll_segment()}

      _ ->
        {:noreply, put_flash(socket, :error, "Не удалось запустить пересчёт сегмента")}
    end
  end

  def handle_event("recalculate_segment", _, socket), do: {:noreply, socket}

  @impl true
  def handle_event("change_settings", params, socket) do
    {:noreply, update_settings(socket, params)}
  end

  def handle_event("toggle_branch", %{"id" => id}, socket) do
    if socket.assigns.live_action == :new and
         Enum.any?(socket.assigns.branches, &(&1.id == id)) do
      selected = socket.assigns.selected_branches
      selected = if id in selected, do: List.delete(selected, id), else: [id | selected]
      {:noreply, assign(socket, selected_branches: selected, scope_error: nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("add_condition", _, socket) do
    if socket.assigns.draft["kind"] == "dynamic" do
      case append_condition(socket, socket.assigns.condition_form.params) do
        {:ok, socket} -> {:noreply, socket}
        {:error, message} -> {:noreply, assign(socket, condition_error: message)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_condition", %{"index" => index}, socket) do
    case Integer.parse(index) do
      {number, ""} when number >= 0 and number < length(socket.assigns.conditions) ->
        {:noreply, assign(socket, conditions: List.delete_at(socket.assigns.conditions, number))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("submit_settings", params, socket) do
    socket = update_settings(socket, params)

    cond do
      String.trim(socket.assigns.draft["name"] || "") == "" ->
        {:noreply, assign(socket, name_error: "Введите название сегмента.")}

      socket.assigns.live_action == :new and socket.assigns.draft["scope"] == "branches" and
          socket.assigns.selected_branches == [] ->
        {:noreply, assign(socket, scope_error: "Выберите хотя бы один филиал.")}

      true ->
        review_conditions(socket)
    end
  end

  def handle_event("back", _, socket), do: {:noreply, assign(socket, reviewing: false)}

  def handle_event("client_sort", %{"field" => field}, socket)
      when field in ["name", "phone"] do
    direction =
      if socket.assigns.client_params["sort"] == field and
           socket.assigns.client_params["direction"] == "asc",
         do: "desc",
         else: "asc"

    {:noreply, patch_clients(socket, %{"sort" => field, "direction" => direction, "page" => "1"})}
  end

  def handle_event("client_search", %{"filter" => %{"search" => search}}, socket) do
    if String.length(search) > 100 do
      {:noreply, assign(socket, client_search_error: "Поиск: не больше 100 символов.")}
    else
      {:noreply, patch_clients(socket, %{"search" => search, "page" => "1"})}
    end
  end

  def handle_event("client_page", %{"page" => page}, socket) do
    {:noreply, patch_clients(socket, %{"page" => page})}
  end

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
            socket.assigns.selected_branches
          )
        end

      case result do
        {:ok, group} ->
          socket =
            if socket.assigns.live_action == :new and group.kind == :manual,
              do:
                put_flash(
                  socket,
                  :info,
                  "Сегмент создан. Добавьте клиентов во вкладке «Клиенты»."
                ),
              else: socket

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
        {:ok, group} = Segments.get(socket.assigns.current_staff, socket.assigns.group.id)

        {:ok, page} =
          Segments.paginated_clients(
            socket.assigns.current_staff,
            group.id,
            socket.assigns.client_params
          )

        requested_page = socket.assigns.client_params["page"]

        socket =
          assign(socket,
            group: group,
            pending_member: nil,
            policy_impact: nil,
            client_page: page,
            client_params: client_page_params(page)
          )

        {:noreply,
         if to_string(page.page) != to_string(requested_page) do
           patch_clients(socket, %{"page" => to_string(page.page)})
         else
           socket
         end}

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

  defp rules(socket),
    do: %{
      "version" => 1,
      "match" => socket.assigns.draft["match"],
      "conditions" => socket.assigns.conditions
    }

  defp update_settings(socket, params) do
    values = Map.get(params, "segment", %{})

    fields =
      if socket.assigns.live_action == :edit, do: ~w(name match), else: ~w(name kind scope match)

    draft = Map.merge(socket.assigns.draft, Map.take(values, fields))
    kind_changed = draft["kind"] != socket.assigns.draft["kind"]

    condition =
      if kind_changed do
        %{"metric" => "order_count", "op" => "gte", "value" => ""}
      else
        Map.merge(socket.assigns.condition_form.params, Map.get(params, "condition", %{}))
      end

    assign(socket,
      draft: draft,
      form: to_form(draft, as: :segment),
      selected_branches:
        if(draft["scope"] == "franchise", do: [], else: socket.assigns.selected_branches),
      conditions: if(kind_changed, do: [], else: socket.assigns.conditions),
      condition_form: to_form(condition, as: :condition),
      condition_metric: condition["metric"],
      condition_error: nil,
      name_error: nil,
      scope_error: nil
    )
  end

  defp client_page_params(page) do
    %{
      "page" => to_string(page.page),
      "search" => page.search,
      "sort" => page.sort,
      "direction" => page.direction,
      "mode" => page.mode
    }
  end

  defp patch_clients(socket, changes) do
    query = client_query(socket.assigns.client_params, changes)

    push_patch(socket, to: ~p"/staff/segments/#{socket.assigns.group.id}?#{query}")
  end

  defp client_query(params, changes),
    do: params |> Map.merge(changes) |> Map.put("tab", "clients")

  defp sort_marker(page, field) do
    if page.sort == field, do: if(page.direction == "asc", do: "↑", else: "↓"), else: ""
  end

  defp client_pager(assigns) do
    ~H"""
    <nav
      class="flex flex-wrap items-center justify-between gap-3"
      aria-label="Страницы клиентов"
    >
      <button
        type="button"
        phx-click="client_page"
        phx-value-page={@page.page - 1}
        disabled={@page.page <= 1}
        class="btn btn-outline btn-sm"
      >← Назад</button>
      <span class="text-sm">Страница {@page.page} из {@page.total_pages}</span>
      <button
        type="button"
        phx-click="client_page"
        phx-value-page={@page.page + 1}
        disabled={@page.page >= @page.total_pages}
        class="btn btn-outline btn-sm"
      >Вперёд →</button>
    </nav>
    """
  end

  defp review_conditions(socket) do
    if socket.assigns.draft["kind"] == "manual" do
      {:noreply, assign(socket, reviewing: true)}
    else
      params = socket.assigns.condition_form.params
      pending = String.trim(to_string(params["value"] || ""))

      result =
        if pending == "" and socket.assigns.conditions != [],
          do: {:ok, socket},
          else: append_condition(socket, params)

      case result do
        {:ok, updated} -> {:noreply, assign(updated, reviewing: true)}
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
    case Decimal.parse(text) do
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
    case Integer.parse(text) do
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

      <section :if={@live_action == :index} id="segment-list" class="space-y-3">
        <div
          id="segment-type-help"
          class="rounded-xl border border-base-300 bg-base-200 p-4 text-sm text-base-content/75"
        >
          <strong>Ручной:</strong>
          выбираете клиентов сами. <strong>Динамический:</strong>
          клиенты подбираются по условиям выполненных заказов; состав обновляется фоновым пересчётом, обычно раз в сутки.
        </div>
        <div id="segment-cards" class="grid gap-3 sm:grid-cols-2" phx-update="stream">
          <div
            :for={{dom_id, group} <- @streams.groups}
            id={dom_id}
            class="min-w-0 rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm transition hover:border-primary/40 hover:shadow-md"
          >
            <.link navigate={~p"/staff/segments/#{group.id}"} class="block break-words font-semibold">{group.name}</.link>
            <p class="mt-1 text-sm text-base-content/65">
              {if group.kind == :manual, do: "Ручной", else: "Динамический"} · {if group.scope ==
                                                                                     :franchise,
                                                                                   do: "Вся сеть",
                                                                                   else:
                                                                                     "Выбранные филиалы"}
            </p>
          </div>
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
        <div :if={!@reviewing}>
          <h2 class="mb-2 text-xl font-semibold">Настройки сегмента</h2>
          <p class="mb-5 text-sm text-base-content/70">
            Укажите тип, охват и условия, затем проверьте результат.
          </p>
          <.form
            for={@form}
            id="segment-settings-form"
            phx-change="change_settings"
            phx-submit="submit_settings"
            class="space-y-5"
          >
            <div>
              <.input field={@form[:name]} type="text" label="Название" required />
              <p :if={@name_error} class="text-sm text-error" role="alert">{@name_error}</p>
            </div>
            <div :if={@live_action == :new}>
              <.input
                field={@form[:kind]}
                type="select"
                label="Тип"
                options={[{"Ручной", "manual"}, {"Динамический", "dynamic"}]}
              />
              <p class="text-sm text-base-content/70">
                <strong>Ручной:</strong>
                создаётся пустым; клиентов добавите после сохранения. <strong>Динамический:</strong>
                состав рассчитывается по условиям выполненных заказов.
              </p>
            </div>
            <div :if={@live_action == :new}>
              <.input
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
              <p class="text-sm text-base-content/70">
                Выберите филиалы или охватите всю доступную сеть.
              </p>
            </div>
            <p :if={@live_action == :edit} class="text-sm text-base-content/70">
              Тип и охват сохраняются после создания.
            </p>
            <div
              :if={@draft["scope"] == "branches" and @live_action == :new}
              id="segment-branches"
              class="space-y-2"
            >
              <h3 class="font-semibold">Филиалы</h3>
              <div class="flex flex-wrap gap-2">
                <button
                  :for={branch <- @branches}
                  id={"branch-#{branch.id}"}
                  type="button"
                  phx-click="toggle_branch"
                  phx-value-id={branch.id}
                  class={[
                    "btn btn-sm rounded-full",
                    if(branch.id in @selected_branches, do: "btn-primary", else: "btn-outline")
                  ]}
                  aria-pressed={branch.id in @selected_branches}
                >{branch.name}</button>
              </div>
              <p :if={@scope_error} class="text-sm text-error" role="alert">{@scope_error}</p>
            </div>
            <div :if={@draft["kind"] == "dynamic"} id="segment-conditions" class="space-y-3">
              <h3 class="font-semibold">Условия</h3>
              <p class="text-sm text-base-content/70">
                Учитываются только выполненные заказы. Суммы вводятся в рублях; срок с последнего заказа — полные сутки.
              </p>
              <.input
                field={@form[:match]}
                type="select"
                label="Совпадение условий"
                options={[{"Все условия", "all"}, {"Любое условие", "any"}]}
              />
              <p class="text-sm text-base-content/70">
                «Все» — каждое условие обязательно. «Любое» — достаточно одного.
              </p>
              <div class="grid gap-3 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)_minmax(7rem,0.7fr)_auto] md:items-end [&_fieldset]:mb-0 [&_fieldset]:pb-0">
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
                  type="button"
                  phx-click="add_condition"
                  class="btn btn-outline w-full md:w-auto"
                  phx-disable-with="Добавляем…"
                >Добавить условие</button>
              </div>
              <p :if={@condition_error} id="condition-error" class="text-sm text-error" role="alert">
                {@condition_error}
              </p>
              <p class="text-xs text-base-content/60">
                Если строка заполнена, «Проверить» добавит её автоматически.
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
            <button
              id="segment-review"
              type="submit"
              name="action"
              value="review"
              class="btn btn-primary"
              phx-disable-with="Проверяем…"
            >Проверить</button>
          </.form>
        </div>
        <div :if={@reviewing} id="segment-review-panel" class="space-y-4">
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
            Сегмент будет пустым. Добавьте клиентов после сохранения во вкладке «Клиенты».
          </p>
          <p :if={@draft["kind"] == "manual" and @live_action == :edit}>
            Состав участников сохранится. Изменить его можно во вкладке «Клиенты».
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
          <div class="flex flex-wrap gap-2">
            <button type="button" phx-click="back" class="btn btn-ghost">Изменить настройки</button>
            <button
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
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="min-w-0 break-words text-2xl font-semibold">{@group.name}</h2>
          <.link
            :if={@can_manage}
            navigate={~p"/staff/segments/#{@group.id}/edit"}
            id="segment-edit-link"
            class="btn btn-outline btn-sm"
          >Изменить</.link>
        </div>
        <div
          class="tabs tabs-box border border-base-300 bg-base-200"
          role="tablist"
          aria-label="Раздел сегмента"
        >
          <.link
            patch={
              if @active_tab == "settings",
                do: ~p"/staff/segments/#{@group.id}",
                else: ~p"/staff/segments/#{@group.id}?tab=settings"
            }
            class={["tab", @active_tab == "settings" && "tab-active"]}
            role="tab"
            aria-selected={@active_tab == "settings"}
          >Параметры</.link>
          <.link
            patch={
              if @active_tab == "clients",
                do: ~p"/staff/segments/#{@group.id}",
                else: ~p"/staff/segments/#{@group.id}?tab=clients"
            }
            class={["tab", @active_tab == "clients" && "tab-active"]}
            role="tab"
            aria-selected={@active_tab == "clients"}
          >Клиенты</.link>
        </div>
        <div :if={@active_tab == "settings"} id="segment-settings" class="space-y-4">
          <p class="text-sm text-base-content/70">
            {if @group.kind == :manual, do: "Ручной", else: "Динамический"} · {if @group.scope ==
                                                                                    :franchise,
                                                                                  do: "Вся сеть",
                                                                                  else:
                                                                                    branch_names(
                                                                                      @group.branches,
                                                                                      Enum.map(
                                                                                        @group.branches,
                                                                                        & &1.id
                                                                                      )
                                                                                    )}
          </p>
          <p :if={@group.kind == :manual} class="text-sm text-base-content/70">
            Вы сами добавляете и убираете участников во вкладке «Клиенты».
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
          <div :if={@group.kind == :dynamic} class="flex flex-wrap items-center gap-3">
            <button
              :if={@can_manage}
              id="segment-recalculate-now"
              type="button"
              phx-click="recalculate_segment"
              phx-disable-with="Запускаем…"
              class="btn btn-outline btn-sm"
            >{if @calculation && @calculation.state in [:queued, :running],
              do: "Проверить расчёт",
              else: "Рассчитать сейчас"}</button>
            <p :if={@calculation} id="segment-calculation-status" class="text-sm" role="status">
              {case @calculation.state do
                :queued -> "Пересчёт поставлен в очередь"
                :running -> "Пересчёт выполняется"
                :ready -> "Состав обновлён"
                :error -> "Не удалось обновить состав"
                _ -> ""
              end}
            </p>
          </div>
          <p :if={@group.last_refresh_error} class="text-sm text-error">
            Последнее обновление не удалось: {@group.last_refresh_error}
          </p>
        </div>
        <div :if={@active_tab == "clients" and @client_page} id="segment-clients" class="space-y-4">
          <p class="text-sm text-base-content/70">
            {cond do
              @group.kind == :dynamic ->
                "Состав рассчитывается по условиям и обновляется фоновым пересчётом."

              @can_manage ->
                "Здесь можно посмотреть состав и вручную добавить или убрать клиентов."

              true ->
                "Состав ручного сегмента."
            end}
          </p>
          <div :if={@group.kind == :manual and @can_manage} class="flex flex-wrap gap-2">
            <.link
              patch={
                ~p"/staff/segments/#{@group.id}?#{client_query(@client_params, %{"mode" => "members", "page" => "1"})}"
              }
              class={[
                "btn btn-sm",
                @client_page.mode == "members" && "btn-primary",
                @client_page.mode != "members" && "btn-outline"
              ]}
            >В сегменте</.link>
            <.link
              :if={@group.kind == :manual and @can_manage}
              patch={
                ~p"/staff/segments/#{@group.id}?#{client_query(@client_params, %{"mode" => "available", "page" => "1"})}"
              }
              class={[
                "btn btn-sm",
                @client_page.mode == "available" && "btn-primary",
                @client_page.mode != "available" && "btn-outline"
              ]}
            >Добавить клиентов</.link>
          </div>
          <.form
            for={@client_filter_form}
            id="segment-client-search"
            phx-submit="client_search"
            class="grid gap-2 sm:grid-cols-[minmax(0,1fr)_auto] sm:items-end [&_fieldset]:mb-0 [&_fieldset]:pb-0"
          >
            <.input
              field={@client_filter_form[:search]}
              type="text"
              label="Поиск по имени или телефону"
              maxlength="100"
            />
            <button class="btn btn-outline w-full sm:w-auto" phx-disable-with="Ищем…">Найти</button>
          </.form>
          <p :if={@client_search_error} class="text-sm text-error" role="alert">
            {@client_search_error}
          </p>
          <div class="flex flex-wrap items-center justify-between gap-3">
            <p class="text-sm text-base-content/70">
              {if @client_page.mode == "members", do: "В сегменте", else: "Можно добавить"}: {@client_page.total_count} · по 20 на странице
            </p>
            <div id="segment-clients-pagination-top" class="min-w-60 flex-1 sm:max-w-sm">
              <.client_pager page={@client_page} />
            </div>
          </div>
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
              phx-disable-with="Применяем…"
            >Подтвердить изменение</button>
          </div>
          <div class="overflow-x-auto rounded-xl border border-base-300">
            <table class="table table-zebra table-sm w-full">
              <thead>
                <tr>
                  <th scope="col">
                    <button
                      type="button"
                      phx-click="client_sort"
                      phx-value-field="name"
                      class="btn btn-ghost btn-sm"
                    >Имя {sort_marker(@client_page, "name")}</button>
                  </th>
                  <th scope="col">
                    <button
                      type="button"
                      phx-click="client_sort"
                      phx-value-field="phone"
                      class="btn btn-ghost btn-sm"
                    >Телефон {sort_marker(@client_page, "phone")}</button>
                  </th>
                  <th :if={@group.kind == :manual and @can_manage} scope="col" class="text-right">
                    Действие
                  </th>
                </tr>
              </thead>
              <tbody id="segment-client-rows">
                <tr :for={client <- @client_page.clients} id={"client-row-#{client.id}"}>
                  <td class="font-medium">{client.name}</td>
                  <td>{client.phone}</td>
                  <td :if={@group.kind == :manual and @can_manage} class="text-right">
                    <button
                      type="button"
                      phx-click={
                        if @client_page.mode == "available", do: "add_member", else: "remove_member"
                      }
                      phx-value-id={client.id}
                      class={[
                        "btn btn-sm",
                        if(@client_page.mode == "available",
                          do: "btn-outline",
                          else: "btn-ghost text-error"
                        )
                      ]}
                      phx-disable-with="Обновляем…"
                    >{if @client_page.mode == "available", do: "Добавить", else: "Убрать"}</button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <p :if={@client_page.clients == []} class="text-sm text-base-content/65">
            {cond do
              @client_page.search != "" ->
                "По этому запросу клиентов нет. Попробуйте другое имя или телефон."

              @client_page.mode == "available" ->
                "Все подходящие клиенты уже в сегменте или недоступны для добавления."

              @group.kind == :dynamic ->
                "Совпадений пока нет или первый пересчёт ещё не завершён."

              @can_manage ->
                "Здесь пока нет клиентов. Откройте «Добавить клиентов»."

              true ->
                "Здесь пока нет клиентов."
            end}
          </p>
          <div id="segment-clients-pagination-bottom"><.client_pager page={@client_page} /></div>
        </div>
      </section>
    </div>
    """
  end
end
