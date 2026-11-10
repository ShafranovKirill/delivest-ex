defmodule DelivestWeb.Staff.MarketingLive.Index do
  use DelivestWeb, :live_view

  alias Delivest.{Features, Identity, Marketing, Segments}

  on_mount {DelivestWeb.Hooks.Permission, "marketing.read"}

  @defaults %{
    "name" => "",
    "scope" => "branches",
    "segment_id" => "",
    "reward_branch_id" => "",
    "bonus_amount" => "",
    "promotion_id" => "",
    "inactivity_days" => "30",
    "reward_ttl_days" => "14",
    "attribution_days" => "7",
    "initial_mode" => "future_only",
    "message_title" => "",
    "message_body" => "",
    "max_issues" => "",
    "excluded_client_ids" => "",
    "excluded_segment_ids" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    staff = socket.assigns.current_staff

    if Features.enabled?("marketing_policies", :franchise) do
      report_filters = %{
        "from" => Date.add(Date.utc_today(), -29) |> Date.to_iso8601(),
        "to" => Date.utc_today() |> Date.to_iso8601(),
        "branch_id" => ""
      }

      segments =
        case Segments.list(staff, limit: 50) do
          {:ok, rows} -> rows
          _ -> []
        end

      branches =
        Enum.filter(
          socket.assigns.staff_branches,
          &Features.enabled?("marketing_policies", {:branch, &1.id})
        )

      {:ok,
       socket
       |> assign(
         page_title: gettext("Marketing policies"),
         can_manage: Identity.can?(staff, "marketing.manage"),
         can_report: Identity.can?(staff, "marketing.reports"),
         segments: segments,
         branches: branches,
         policy: nil,
         preview: nil,
         report: nil,
         comparison: nil,
         comparison_policies: [],
         comparison_after: nil,
         compare_ids: [],
         promotions: [],
         promotion_search_form: to_form(%{"query" => ""}, as: :promotion_search),
         step: 1,
         report_filters: report_filters,
         report_form: to_form(report_filters, as: :report),
         segment_after: length(segments) == 50 && List.last(segments).id,
         policy_after: nil,
         draft: @defaults,
         selected_branches: [],
         excluded_clients: [],
         excluded_segments: [],
         client_results: [],
         segment_results: [],
         client_search_form: to_form(%{"query" => ""}, as: :client_search),
         segment_search_form: to_form(%{"query" => ""}, as: :segment_search),
         exclusions_reset?: false,
         channels: ["in_app"],
         form: to_form(@defaults, as: :policy)
       )
       |> stream(:policies, [])}
    else
      {:ok, redirect(socket, to: ~p"/staff/branches/select")}
    end
  end

  @impl true
  def handle_params(params, _uri, socket) do
    staff = socket.assigns.current_staff

    case socket.assigns.live_action do
      :index ->
        case Marketing.list(staff) do
          {:ok, policies} ->
            {:noreply,
             socket
             |> assign(
               policy: nil,
               policy_after: length(policies) == 50 && List.last(policies).id
             )
             |> stream(:policies, policies, reset: true)}

          _ ->
            {:noreply, redirect(socket, to: ~p"/staff/branches/select")}
        end

      :new ->
        if socket.assigns.can_manage do
          {:noreply,
           socket
           |> assign(
             policy: nil,
             promotions: [],
             preview: nil,
             step: 1,
             selected_branches: [],
             excluded_clients: [],
             excluded_segments: [],
             client_results: [],
             segment_results: [],
             client_search_form: to_form(%{"query" => ""}, as: :client_search),
             segment_search_form: to_form(%{"query" => ""}, as: :segment_search),
             exclusions_reset?: false,
             channels: ["in_app"],
             draft: @defaults,
             form: to_form(@defaults, as: :policy)
           )}
        else
          {:noreply, push_navigate(socket, to: ~p"/staff/marketing")}
        end

      action when action in [:show, :edit] ->
        case Marketing.get(staff, params["id"]) do
          {:ok, policy} ->
            if action == :edit and (not socket.assigns.can_manage or policy.status != :draft) do
              {:noreply, push_navigate(socket, to: ~p"/staff/marketing/#{policy.id}")}
            else
              exclusions =
                if action == :edit do
                  {:ok, saved} = Marketing.exclusions(staff, policy.id)
                  saved
                else
                  %{client_ids: [], segment_ids: [], clients: [], segments: []}
                end

              draft = policy_draft(policy, exclusions)
              {comparison_policies, comparison_after} = comparison_page(staff, policy.id)

              segments =
                if Enum.any?(socket.assigns.segments, &(&1.id == policy.segment_id)),
                  do: socket.assigns.segments,
                  else: [policy.segment | socket.assigns.segments]

              {:noreply,
               socket
               |> assign(
                 policy: policy,
                 preview: nil,
                 report: nil,
                 comparison: nil,
                 comparison_policies: comparison_policies,
                 comparison_after: comparison_after,
                 compare_ids: [policy.id],
                 promotions: promotions(staff, policy.reward_branch_id, policy.promotion),
                 step: 1,
                 segments: segments,
                 draft: draft,
                 selected_branches: Enum.map(policy.branches, & &1.id),
                 excluded_clients:
                   exclusion_choices(
                     exclusions.client_ids,
                     exclusions.clients,
                     gettext("Customer unavailable"),
                     &client_label/1
                   ),
                 excluded_segments:
                   exclusion_choices(
                     exclusions.segment_ids,
                     exclusions.segments,
                     gettext("Segment unavailable"),
                     & &1.name
                   ),
                 client_results: [],
                 segment_results: [],
                 client_search_form: to_form(%{"query" => ""}, as: :client_search),
                 segment_search_form: to_form(%{"query" => ""}, as: :segment_search),
                 exclusions_reset?: false,
                 channels: policy.channels,
                 form: to_form(draft, as: :policy)
               )}
            end

          _ ->
            {:noreply, push_navigate(socket, to: ~p"/staff/marketing")}
        end
    end
  end

  @impl true
  def handle_event("choose_reward_branch", %{"policy" => params}, socket) do
    branch_changed? =
      Map.get(params, "reward_branch_id", socket.assigns.draft["reward_branch_id"]) !=
        socket.assigns.draft["reward_branch_id"]

    draft =
      socket.assigns.draft
      |> Map.merge(params)
      |> then(&if(branch_changed?, do: Map.put(&1, "promotion_id", ""), else: &1))

    {:noreply,
     assign(socket,
       draft: draft,
       form: to_form(draft, as: :policy),
       promotions:
         if(branch_changed?,
           do: promotions(socket.assigns.current_staff, draft["reward_branch_id"], nil),
           else: socket.assigns.promotions
         )
     )}
  end

  def handle_event("change", %{"policy" => params}, socket) do
    {:noreply, sync_audience(socket, params)}
  end

  def handle_event("next", %{"policy" => params}, socket) do
    socket = sync_audience(socket, params)
    draft = socket.assigns.draft

    {:noreply,
     socket
     |> assign(
       draft: draft,
       step: min(socket.assigns.step + 1, 5),
       form: to_form(draft, as: :policy),
       promotions: socket.assigns.promotions
     )}
  end

  def handle_event("search_promotions", %{"promotion_search" => %{"query" => query}}, socket) do
    branch_id = socket.assigns.draft["reward_branch_id"]
    selected_id = socket.assigns.draft["promotion_id"]

    selected =
      Enum.find(socket.assigns.promotions, fn {_name, id} -> id == selected_id end)

    found = promotions(socket.assigns.current_staff, branch_id, nil, query)

    options =
      if selected && not Enum.any?(found, fn {_name, id} -> id == selected_id end),
        do: [selected | found],
        else: found

    {:noreply,
     assign(socket,
       promotions: options,
       promotion_search_form: to_form(%{"query" => query}, as: :promotion_search)
     )}
  end

  def handle_event("back", _, socket),
    do: {:noreply, assign(socket, step: max(socket.assigns.step - 1, 1))}

  def handle_event(
        "search_excluded_clients",
        %{"client_search" => %{"query" => query}},
        %{assigns: %{can_manage: true, step: 4, live_action: action}} = socket
      )
      when action in [:new, :edit] do
    results =
      case Segments.search_eligible_clients(
             socket.assigns.current_staff,
             socket.assigns.draft["segment_id"],
             query,
             limit: 20
           ) do
        {:ok, clients} -> Enum.map(clients, &%{id: &1.id, label: client_label(&1)})
        _ -> []
      end

    {:noreply,
     assign(socket,
       client_results: results,
       client_search_form: to_form(%{"query" => query}, as: :client_search)
     )}
  end

  def handle_event(
        "search_excluded_segments",
        %{"segment_search" => %{"query" => query}},
        %{assigns: %{can_manage: true, step: 4, live_action: action}} = socket
      )
      when action in [:new, :edit] do
    results =
      case Marketing.search_exclusion_segments(
             socket.assigns.current_staff,
             socket.assigns.draft["segment_id"],
             query
           ) do
        {:ok, segments} -> Enum.map(segments, &%{id: &1.id, label: &1.name})
        _ -> []
      end

    {:noreply,
     assign(socket,
       segment_results: results,
       segment_search_form: to_form(%{"query" => query}, as: :segment_search)
     )}
  end

  def handle_event(
        "add_excluded_client",
        %{"id" => id},
        %{assigns: %{can_manage: true, step: 4, live_action: action}} = socket
      )
      when action in [:new, :edit],
      do: {:noreply, add_exclusion(socket, :excluded_clients, :client_results, id)}

  def handle_event(
        "add_excluded_segment",
        %{"id" => id},
        %{assigns: %{can_manage: true, step: 4, live_action: action}} = socket
      )
      when action in [:new, :edit],
      do: {:noreply, add_exclusion(socket, :excluded_segments, :segment_results, id)}

  def handle_event(
        "remove_excluded_client",
        %{"id" => id},
        %{assigns: %{can_manage: true, step: 4, live_action: action}} = socket
      )
      when action in [:new, :edit],
      do: {:noreply, remove_exclusion(socket, :excluded_clients, id)}

  def handle_event(
        "remove_excluded_segment",
        %{"id" => id},
        %{assigns: %{can_manage: true, step: 4, live_action: action}} = socket
      )
      when action in [:new, :edit],
      do: {:noreply, remove_exclusion(socket, :excluded_segments, id)}

  def handle_event(event, _, socket)
      when event in ~w(search_excluded_clients search_excluded_segments add_excluded_client add_excluded_segment remove_excluded_client remove_excluded_segment),
      do: {:noreply, socket}

  def handle_event("more_segments", _, socket) do
    case Segments.list(socket.assigns.current_staff,
           after: socket.assigns.segment_after,
           limit: 50
         ) do
      {:ok, rows} ->
        {:noreply,
         assign(socket,
           segments: socket.assigns.segments ++ rows,
           segment_after: length(rows) == 50 && List.last(rows).id
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("more_policies", _, socket) do
    case Marketing.list(socket.assigns.current_staff, after: socket.assigns.policy_after) do
      {:ok, rows} ->
        {:noreply,
         socket
         |> assign(policy_after: length(rows) == 50 && List.last(rows).id)
         |> stream(:policies, rows)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("toggle_branch", %{"id" => id}, socket) do
    selected = toggle(socket.assigns.selected_branches, id)

    {:noreply,
     socket
     |> assign(selected_branches: selected)
     |> clear_exclusions_if_selected()}
  end

  def handle_event("toggle_channel", %{"id" => id}, socket) when id in ~w(in_app push sms) do
    channels = toggle(socket.assigns.channels, id)
    {:noreply, assign(socket, channels: channels)}
  end

  def handle_event("save", params, socket) do
    staff = socket.assigns.current_staff

    attrs =
      socket.assigns.draft
      |> Map.merge(Map.get(params, "policy", %{}))
      |> Map.put("channels", socket.assigns.channels)
      |> Map.put("expected_revision", socket.assigns.policy && socket.assigns.policy.revision)

    branches = if attrs["scope"] == "franchise", do: [], else: socket.assigns.selected_branches
    clients = split_ids(attrs["excluded_client_ids"])
    segments = split_ids(attrs["excluded_segment_ids"])

    result =
      if socket.assigns.policy do
        Marketing.update(staff, socket.assigns.policy.id, attrs, branches, clients, segments)
      else
        Marketing.create(staff, attrs, branches, clients, segments)
      end

    case result do
      {:ok, policy} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Policy saved"))
         |> push_navigate(to: ~p"/staff/marketing/#{policy.id}")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(draft: attrs, form: to_form(attrs, as: :policy))
         |> put_flash(
           :error,
           gettext("Could not save the policy. Check its fields and try again.")
         )}
    end
  end

  def handle_event("preview", _, %{assigns: %{policy: policy}} = socket) do
    case Marketing.preview(socket.assigns.current_staff, policy.id) do
      {:ok, preview} ->
        {:noreply, assign(socket, preview: preview)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not prepare the audience preview."))}
    end
  end

  def handle_event("status", %{"action" => action}, %{assigns: %{policy: policy}} = socket)
      when action in ["activate", "pause"] do
    result =
      if action == "activate",
        do: Marketing.activate(socket.assigns.current_staff, policy.id, policy.revision),
        else: Marketing.pause(socket.assigns.current_staff, policy.id, policy.revision)

    case result do
      {:ok, updated} ->
        {:noreply,
         socket
         |> assign(policy: updated)
         |> put_flash(:info, gettext("Policy status updated"))}

      {:error, :preview_required} ->
        {:noreply,
         put_flash(socket, :error, gettext("Complete the audience preview before activation."))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not update the policy status."))}
    end
  end

  def handle_event("report", %{"report" => filters}, %{assigns: %{policy: policy}} = socket) do
    case Marketing.report(socket.assigns.current_staff, policy.id, filters) do
      {:ok, report} ->
        {:noreply,
         assign(socket,
           report: report,
           report_filters: filters,
           report_form: to_form(filters, as: :report)
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not load the report."))}
    end
  end

  def handle_event("toggle_compare", %{"id" => id}, socket) do
    ids = toggle(socket.assigns.compare_ids, id)
    {:noreply, assign(socket, compare_ids: Enum.take(ids, 10))}
  end

  def handle_event(
        "more_comparison_policies",
        _,
        %{assigns: %{live_action: :show, comparison_after: after_id, policy: policy}} = socket
      )
      when is_binary(after_id) do
    case Marketing.list(socket.assigns.current_staff, after: after_id, limit: 50) do
      {:ok, rows} ->
        {:noreply,
         assign(socket,
           comparison_policies:
             socket.assigns.comparison_policies ++ Enum.reject(rows, &(&1.id == policy.id)),
           comparison_after: length(rows) == 50 && List.last(rows).id
         )}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("more_comparison_policies", _, socket), do: {:noreply, socket}

  def handle_event("compare", _, socket) do
    case Marketing.compare_reports(
           socket.assigns.current_staff,
           socket.assigns.compare_ids,
           socket.assigns.report_filters
         ) do
      {:ok, comparison} ->
        {:noreply, assign(socket, comparison: comparison)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not compare policies."))}
    end
  end

  defp comparison_page(staff, current_id) do
    case Marketing.list(staff, limit: 50) do
      {:ok, rows} ->
        {Enum.reject(rows, &(&1.id == current_id)), length(rows) == 50 && List.last(rows).id}

      _ ->
        {[], nil}
    end
  end

  defp promotions(staff, branch_id, selected, query \\ "") do
    rows =
      case Marketing.available_promotions(staff, branch_id, query) do
        {:ok, values} -> values
        _ -> []
      end

    if selected && selected.branch_id == branch_id &&
         not Enum.any?(rows, &(elem(&1, 1) == selected.id)),
       do: [{selected.name, selected.id} | rows],
       else: rows
  end

  defp toggle(values, value),
    do: if(value in values, do: List.delete(values, value), else: values ++ [value])

  defp sync_audience(socket, params) do
    old = socket.assigns.draft
    draft = Map.merge(old, params)

    socket =
      socket
      |> assign(draft: draft, form: to_form(draft, as: :policy))

    if draft["segment_id"] != old["segment_id"] or draft["scope"] != old["scope"],
      do: clear_exclusions_if_selected(socket),
      else: socket
  end

  defp clear_exclusions_if_selected(socket) do
    had_exclusions? =
      socket.assigns.excluded_clients != [] or socket.assigns.excluded_segments != []

    socket
    |> assign(
      excluded_clients: [],
      excluded_segments: [],
      client_results: [],
      segment_results: [],
      exclusions_reset?: socket.assigns.exclusions_reset? or had_exclusions?
    )
    |> update_exclusion_draft()
  end

  defp add_exclusion(socket, selected_key, results_key, id) do
    selected = Map.fetch!(socket.assigns, selected_key)
    option = Enum.find(Map.fetch!(socket.assigns, results_key), &(&1.id == id))

    if option && length(selected) < 1000 && not Enum.any?(selected, &(&1.id == id)) do
      socket
      |> assign(selected_key, selected ++ [option])
      |> update_exclusion_draft()
    else
      socket
    end
  end

  defp remove_exclusion(socket, selected_key, id) do
    socket
    |> assign(selected_key, Enum.reject(Map.fetch!(socket.assigns, selected_key), &(&1.id == id)))
    |> update_exclusion_draft()
  end

  defp update_exclusion_draft(socket) do
    draft =
      socket.assigns.draft
      |> Map.put(
        "excluded_client_ids",
        Enum.map_join(socket.assigns.excluded_clients, "\n", & &1.id)
      )
      |> Map.put(
        "excluded_segment_ids",
        Enum.map_join(socket.assigns.excluded_segments, "\n", & &1.id)
      )

    assign(socket, draft: draft, form: to_form(draft, as: :policy))
  end

  defp exclusion_choices(ids, records, unavailable, label_fun) do
    labels = Map.new(records, &{&1.id, label_fun.(&1)})
    Enum.map(ids, &%{id: &1, label: Map.get(labels, &1, unavailable)})
  end

  defp client_label(client) do
    if is_binary(client.name) and client.name != "",
      do: "#{client.name} · #{client.phone}",
      else: client.phone
  end

  defp split_ids(nil), do: []
  defp split_ids(value), do: String.split(value, ~r/[\s,;]+/, trim: true)

  defp status_label(:draft), do: gettext("Draft")
  defp status_label(:initializing), do: gettext("Preparing audience")
  defp status_label(:active), do: gettext("Active")
  defp status_label(:paused), do: gettext("Paused")

  defp scope_label(:branches), do: gettext("Selected branches")
  defp scope_label(:franchise), do: gettext("Entire network")
  defp scope_label("branches"), do: scope_label(:branches)
  defp scope_label("franchise"), do: scope_label(:franchise)
  defp scope_label(_), do: gettext("Not selected")

  defp initial_mode_label(:future_only), do: gettext("Future participants only")
  defp initial_mode_label(:all_current), do: gettext("All current audience")
  defp initial_mode_label("future_only"), do: initial_mode_label(:future_only)
  defp initial_mode_label("all_current"), do: initial_mode_label(:all_current)
  defp initial_mode_label(_), do: gettext("Not selected")

  defp branch_label(branches, id) do
    Enum.find_value(branches, gettext("Branch unavailable"), fn branch ->
      branch.id == id && branch.name
    end)
  end

  defp policy_draft(policy, exclusions) do
    @defaults
    |> Map.merge(%{
      "name" => policy.name,
      "scope" => Atom.to_string(policy.scope),
      "segment_id" => policy.segment_id,
      "reward_branch_id" => policy.reward_branch_id,
      "bonus_amount" => policy.bonus_amount && to_string(policy.bonus_amount),
      "promotion_id" => policy.promotion_id || "",
      "inactivity_days" => to_string(policy.inactivity_days),
      "reward_ttl_days" => to_string(policy.reward_ttl_days),
      "attribution_days" => to_string(policy.attribution_days),
      "initial_mode" => Atom.to_string(policy.initial_mode),
      "message_title" => policy.message_title,
      "message_body" => policy.message_body,
      "max_issues" => (policy.max_issues && to_string(policy.max_issues)) || "",
      "excluded_client_ids" => Enum.join(exclusions.client_ids, "\n"),
      "excluded_segment_ids" => Enum.join(exclusions.segment_ids, "\n")
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl space-y-6 p-4 sm:p-8">
      <header class="flex flex-wrap items-center justify-between gap-4">
        <div>
          <p class="text-sm uppercase tracking-wide text-base-content/60">{gettext("Customers")}</p>
          <h1 class="text-3xl font-semibold">{gettext("Marketing policies")}</h1>
        </div>
        <.link
          :if={@can_manage and @live_action == :index}
          navigate={~p"/staff/marketing/new"}
          class="btn btn-primary"
        >{gettext("New policy")}</.link>
      </header>

      <section
        :if={@live_action == :index}
        id="marketing-policies"
        phx-update="stream"
        class="grid gap-3 md:grid-cols-2"
      >
        <article
          :for={{dom_id, policy} <- @streams.policies}
          id={dom_id}
          class="rounded-2xl border border-base-300 bg-base-100 text-base-content p-5 shadow-sm transition hover:shadow-md"
        >
          <.link
            navigate={~p"/staff/marketing/#{policy.id}"}
            class="text-lg font-semibold text-primary"
          >{policy.name}</.link>
          <p class="mt-2 text-sm text-base-content/60">
            {status_label(policy.status)} · {scope_label(policy.scope)} · {gettext("%{count} issues",
              count: policy.issued_count
            )}
          </p>
        </article>
      </section>
      <button
        :if={@live_action == :index and @policy_after}
        id="marketing-more-policies"
        phx-click="more_policies"
        class="btn btn-outline"
      >{gettext("More policies")}</button>

      <section
        :if={@live_action in [:new, :edit]}
        id="marketing-policy-wizard"
        class="rounded-2xl border border-base-300 bg-base-100 text-base-content p-6 shadow-sm"
      >
        <p class="mb-4 text-sm text-base-content/60">{gettext("Step %{step} of 5", step: @step)}</p>
        <p
          :if={@exclusions_reset?}
          id="marketing-exclusions-reset"
          class="mb-4 rounded-xl bg-warning/10 p-3 text-sm text-base-content"
        >
          {gettext(
            "Exclusions were cleared because the audience or branches changed. Review them again."
          )}
        </p>
        <.form
          :if={@step == 1}
          for={@form}
          id="marketing-policy-audience"
          phx-change="change"
          phx-submit="next"
          class="grid gap-4 md:grid-cols-2"
        >
          <h2 class="md:col-span-2 text-lg font-semibold">{gettext("Audience")}</h2>
          <.input field={@form[:name]} type="text" label={gettext("Policy name")} required />
          <.input
            field={@form[:scope]}
            type="select"
            label={gettext("Scope")}
            options={[
              {gettext("Selected branches"), "branches"},
              {gettext("Entire network"), "franchise"}
            ]}
          />
          <.input
            field={@form[:segment_id]}
            type="select"
            label={gettext("Audience segment")}
            options={[{gettext("Select a segment"), ""} | Enum.map(@segments, &{&1.name, &1.id})]}
          />
          <button
            :if={@segment_after}
            type="button"
            id="marketing-more-segments"
            phx-click="more_segments"
            class="btn btn-outline"
          >{gettext("More segments")}</button>
          <div class="md:col-span-2 rounded-xl bg-base-200 p-4">
            <p class="mb-2 font-medium">{gettext("Policy branches")}</p>
            <div class="flex flex-wrap gap-2">
              <button
                :for={branch <- @branches}
                type="button"
                phx-click="toggle_branch"
                phx-value-id={branch.id}
                class={[
                  "rounded-full border px-3 py-1 text-sm transition",
                  branch.id in @selected_branches && "border-primary bg-primary/10 text-primary"
                ]}
              >{branch.name}</button>
            </div>
            <p class="mt-2 text-xs text-base-content/60">
              {gettext("A network-wide policy does not need selected branches.")}
            </p>
          </div>
          <button id="marketing-next-audience" class="btn btn-primary md:col-span-2">{gettext("Next")}</button>
        </.form>

        <div :if={@step == 2} class="space-y-4">
          <.form
            for={@form}
            id="marketing-policy-reward"
            phx-change="choose_reward_branch"
            phx-submit="next"
            class="grid gap-4 md:grid-cols-2"
          >
            <h2 class="md:col-span-2 text-lg font-semibold">{gettext("Reward")}</h2>
            <.input
              field={@form[:reward_branch_id]}
              type="select"
              label={gettext("Reward branch")}
              options={[{gettext("Select a branch"), ""} | Enum.map(@branches, &{&1.name, &1.id})]}
            />
            <.input
              field={@form[:bonus_amount]}
              type="number"
              label={gettext("Bonus points")}
              min="1"
            />
            <.input
              field={@form[:promotion_id]}
              type="select"
              label={gettext("Active personal promotion")}
              options={[{gettext("No promotion"), ""} | @promotions]}
            />
            <p class="md:col-span-2 text-xs text-base-content/60">
              {gettext("Choose one reward. A promo code expires with the policy reward.")}
            </p>
            <div class="md:col-span-2 flex gap-2">
              <button type="button" phx-click="back" class="btn btn-outline">{gettext("Back")}</button>
              <button id="marketing-next-reward" class="btn btn-primary">{gettext("Next")}</button>
            </div>
          </.form>
          <.form
            for={@promotion_search_form}
            id="marketing-promotion-search"
            phx-submit="search_promotions"
            class="flex gap-2"
          >
            <.input
              field={@promotion_search_form[:query]}
              type="text"
              label={gettext("Search promotions by name")}
            />
            <button class="btn btn-outline self-end">{gettext("Search")}</button>
          </.form>
        </div>

        <.form
          :if={@step == 3}
          for={@form}
          id="marketing-policy-message"
          phx-change="change"
          phx-submit="next"
          class="grid gap-4 md:grid-cols-2"
        >
          <h2 class="md:col-span-2 text-lg font-semibold">{gettext("Notification")}</h2>
          <div class="md:col-span-2">
            <p class="mb-2 font-medium">{gettext("Channels")}</p>
            <button
              :for={
                {id, title} <- [
                  {"in_app", gettext("On site")},
                  {"push", "Push"},
                  {"sms", gettext("SMS (unavailable)")}
                ]
              }
              type="button"
              phx-click="toggle_channel"
              phx-value-id={id}
              class={[
                "mr-2 rounded-full border px-3 py-1 text-sm",
                id in @channels && "border-primary bg-primary/10 text-primary"
              ]}
            >{title}</button>
          </div>
          <.input field={@form[:message_title]} type="text" label={gettext("Message title")} required />
          <.input
            field={@form[:message_body]}
            type="textarea"
            label={gettext("Message body")}
            required
          />
          <div class="md:col-span-2 flex gap-2">
            <button type="button" phx-click="back" class="btn btn-outline">{gettext("Back")}</button>
            <button id="marketing-next-message" class="btn btn-primary">{gettext("Next")}</button>
          </div>
        </.form>

        <.form
          :if={@step == 4}
          for={@form}
          id="marketing-policy-limits"
          phx-change="change"
          phx-submit="next"
          class="grid gap-4 md:grid-cols-2"
        >
          <h2 class="md:col-span-2 text-lg font-semibold">{gettext("Limits and first run")}</h2>
          <.input
            field={@form[:inactivity_days]}
            type="number"
            min="1"
            label={gettext("Days since last completed order")}
            required
          />
          <.input
            field={@form[:reward_ttl_days]}
            type="number"
            min="1"
            label={gettext("Reward duration, days")}
            required
          />
          <.input
            field={@form[:attribution_days]}
            type="number"
            min="1"
            label={gettext("Observation window, days")}
            required
          />
          <.input
            field={@form[:initial_mode]}
            type="select"
            label={gettext("First run")}
            options={[
              {gettext("Future participants only"), "future_only"},
              {gettext("All current audience"), "all_current"}
            ]}
          />
          <.input
            field={@form[:max_issues]}
            type="number"
            min="1"
            label={gettext("Issue limit (optional)")}
          />
          <div class="md:col-span-2 flex gap-2">
            <button type="button" phx-click="back" class="btn btn-outline">{gettext("Back")}</button>
            <button id="marketing-next-limits" class="btn btn-primary">{gettext("Review")}</button>
          </div>
        </.form>

        <div
          :if={@step == 4}
          id="marketing-exclusions"
          class="mt-6 grid gap-5 border-t border-base-300 pt-5 md:grid-cols-2"
        >
          <div class="space-y-3">
            <h3 class="font-semibold">{gettext("Exclude customers")}</h3>
            <.form
              for={@client_search_form}
              id="marketing-client-search"
              phx-submit="search_excluded_clients"
              class="flex items-end gap-2"
            >
              <.input
                field={@client_search_form[:query]}
                type="text"
                minlength="2"
                label={gettext("Search customers by name or phone")}
              />
              <button class="btn btn-outline">{gettext("Search")}</button>
            </.form>
            <p :if={@draft["segment_id"] == ""} class="text-sm text-base-content/60">
              {gettext("Choose an audience segment before searching.")}
            </p>
            <div id="marketing-client-results" class="flex flex-wrap gap-2">
              <button
                :for={client <- @client_results}
                type="button"
                phx-click="add_excluded_client"
                phx-value-id={client.id}
                class="btn btn-outline btn-sm"
              >{client.label}</button>
            </div>
            <p :if={@excluded_clients == []} class="text-sm text-base-content/60">
              {gettext("No customers excluded")}
            </p>
            <div id="marketing-excluded-clients" class="flex flex-wrap gap-2">
              <button
                :for={client <- @excluded_clients}
                type="button"
                phx-click="remove_excluded_client"
                phx-value-id={client.id}
                aria-label={gettext("Remove %{name}", name: client.label)}
                class="rounded-full border border-primary bg-primary/10 px-3 py-1 text-sm text-primary"
              >{client.label} ×</button>
            </div>
          </div>
          <div class="space-y-3">
            <h3 class="font-semibold">{gettext("Exclude groups")}</h3>
            <.form
              for={@segment_search_form}
              id="marketing-segment-search"
              phx-submit="search_excluded_segments"
              class="flex items-end gap-2"
            >
              <.input
                field={@segment_search_form[:query]}
                type="text"
                minlength="2"
                label={gettext("Search groups by name")}
              />
              <button class="btn btn-outline">{gettext("Search")}</button>
            </.form>
            <div id="marketing-segment-results" class="flex flex-wrap gap-2">
              <button
                :for={segment <- @segment_results}
                type="button"
                phx-click="add_excluded_segment"
                phx-value-id={segment.id}
                class="btn btn-outline btn-sm"
              >{segment.label}</button>
            </div>
            <p :if={@excluded_segments == []} class="text-sm text-base-content/60">
              {gettext("No groups excluded")}
            </p>
            <div id="marketing-excluded-segments" class="flex flex-wrap gap-2">
              <button
                :for={segment <- @excluded_segments}
                type="button"
                phx-click="remove_excluded_segment"
                phx-value-id={segment.id}
                aria-label={gettext("Remove %{name}", name: segment.label)}
                class="rounded-full border border-primary bg-primary/10 px-3 py-1 text-sm text-primary"
              >{segment.label} ×</button>
            </div>
          </div>
        </div>

        <div :if={@step == 5} id="marketing-policy-review" class="space-y-4">
          <h2 class="text-lg font-semibold">{gettext("Review and enable")}</h2>
          <p>
            {gettext("Audience: %{segment} · %{scope}",
              segment:
                Enum.find_value(@segments, gettext("Not selected"), fn s ->
                  s.id == @draft["segment_id"] && s.name
                end),
              scope: scope_label(@draft["scope"])
            )}
          </p>
          <p>
            {gettext("Reward branch: %{branch}",
              branch:
                Enum.find_value(@branches, gettext("Not selected"), fn b ->
                  b.id == @draft["reward_branch_id"] && b.name
                end)
            )}
          </p>
          <p>
            {gettext("Initial audience: %{mode}", mode: initial_mode_label(@draft["initial_mode"]))}
          </p>
          <p>
            {gettext(
              "A preview is required before the first activation. Save the draft, run the preview, then enable the policy on its page."
            )}
          </p>
          <div class="flex gap-2">
            <button type="button" phx-click="back" class="btn btn-outline">{gettext("Back")}</button>
            <button id="marketing-save" type="button" phx-click="save" class="btn btn-primary">{gettext(
              "Save draft and continue"
            )}</button>
          </div>
        </div>
      </section>

      <section :if={@live_action == :show and @policy} id="marketing-policy-detail" class="space-y-4">
        <.link navigate={~p"/staff/marketing"} class="text-sm text-primary">{gettext("← All policies")}</.link>
        <div class="rounded-2xl border border-base-300 bg-base-100 text-base-content p-6 shadow-sm">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 class="text-2xl font-semibold">{@policy.name}</h2>
              <p class="text-sm text-base-content/60">
                {gettext("Status: %{status} · revision %{revision}",
                  status: status_label(@policy.status),
                  revision: @policy.revision
                )}
              </p>
            </div>
            <.link
              :if={@can_manage and @policy.status == :draft}
              navigate={~p"/staff/marketing/#{@policy.id}/edit"}
              class="btn btn-outline"
            >{gettext("Edit")}</.link>
          </div>
          <p class="mt-4 text-sm">
            {gettext(
              "After %{days} days without an order · reward valid for %{ttl} days · initial audience: %{mode}",
              days: @policy.inactivity_days,
              ttl: @policy.reward_ttl_days,
              mode: initial_mode_label(@policy.initial_mode)
            )}
          </p>
          <p
            :if={@policy.last_error}
            id="marketing-policy-error"
            class="mt-3 rounded-lg bg-warning/10 p-3 text-sm text-base-content"
          >
            {gettext("A reward could not be issued. Check that it is available.")}
          </p>
          <div :if={@can_manage} class="mt-5 flex flex-wrap gap-2">
            <button
              :if={@policy.status == :draft}
              id="marketing-preview"
              phx-click="preview"
              class="btn btn-outline"
            >{gettext("Audience preview")}</button>
            <button
              :if={@policy.status in [:draft, :paused]}
              id="marketing-activate"
              phx-click="status"
              phx-value-action="activate"
              class="btn btn-primary"
            >{gettext("Activate")}</button>
            <button
              :if={@policy.status in [:active, :initializing]}
              id="marketing-pause"
              phx-click="status"
              phx-value-action="pause"
              class="btn btn-outline"
            >{gettext("Pause")}</button>
          </div>
          <div
            :if={@preview}
            id="marketing-preview-result"
            class="mt-4 rounded-xl bg-primary/10 p-4 text-sm"
          >
            <%= if @preview.status == :pending do %>
              {gettext("The audience preview is being prepared. Refresh it later.")}
            <% else %>
              {gettext("Eligible customers: %{count}", count: @preview.eligible_clients)}. {gettext(
                "Bonus points: %{points}",
                points: @preview.bonus_points || gettext("Not applicable")
              )}. {gettext(
                "SMS cost: unknown (provider unavailable). Calculated: %{time}",
                time: @preview.counted_at
              )}.
            <% end %>
          </div>
        </div>
        <div
          :if={@can_report}
          class="rounded-2xl border border-base-300 bg-base-100 text-base-content p-6 shadow-sm"
        >
          <h3 class="text-lg font-semibold">{gettext("Report")}</h3>
          <.form
            for={@report_form}
            id="marketing-report-form"
            phx-submit="report"
            class="mt-3 grid gap-3 sm:grid-cols-4"
          >
            <.input field={@report_form[:from]} type="date" label={gettext("From")} />
            <.input field={@report_form[:to]} type="date" label={gettext("To")} />
            <.input
              field={@report_form[:branch_id]}
              type="select"
              label={gettext("Branch")}
              options={[{gettext("All branches"), ""} | Enum.map(@branches, &{&1.name, &1.id})]}
            />
            <button id="marketing-report" class="btn btn-outline self-end">{gettext("Show")}</button>
          </.form>
          <p
            :if={@report && @report.status == :pending}
            id="marketing-report-pending"
            class="mt-4 rounded-xl bg-primary/10 p-4 text-sm"
          >
            {gettext("The report is being prepared. Refresh it later.")}
          </p>
          <div
            :if={@report && @report.status == :ready}
            id="marketing-report-result"
            class="mt-4 space-y-5"
          >
            <p class="text-xs text-base-content/60">
              {gettext("Snapshot as of %{time}", time: @report.as_of)}
            </p>
            <div class="grid gap-3 sm:grid-cols-3">
              <p>{gettext("Issues: %{value}", value: @report.data["issued"])}</p><p>
                {gettext("Exclusions: %{value}", value: @report.data["excluded"])}
              </p>
              <p>{gettext("Linked orders: %{value}", value: @report.data["linked_orders"])}</p>
              <p>
                {gettext("Returning customers: %{value}", value: @report.data["returned_clients"])}
              </p>
              <p>
                {gettext("Net revenue after refunds: %{value}",
                  value: @report.data["linked_net_revenue"]
                )}
              </p>
              <p>
                {gettext("Redeemed promo codes: %{value}", value: @report.data["promo_redemptions"])}
              </p>
              <p>
                {gettext("Recorded discount: %{value}",
                  value: @report.data["recorded_promo_discount"]
                )}
              </p>
              <p>{gettext("Points issued: %{value}", value: @report.data["bonus_points_issued"])}</p>
              <p>{gettext("Points spent: unknown (spending is not linked to this reward)")}</p>
              <p>{gettext("Clicks: %{value}", value: @report.data["clicked_notices"])}</p>
              <p>{gettext("On-site cards: %{value}", value: @report.data["in_app_available"])}</p>
              <p>
                {gettext("Push accepted by transport: %{value}",
                  value: @report.data["push_provider_accepted"]
                )}
              </p>
              <p>{gettext("Push outcome unknown: %{value}", value: @report.data["push_unknown"])}</p>
              <p>{gettext("Push skipped: %{value}", value: @report.data["push_skipped"])}</p>
              <p>{gettext("SMS unavailable: %{value}", value: @report.data["sms_unavailable"])}</p>
            </div>
            <table id="marketing-report-daily" class="w-full text-left text-sm">
              <thead>
                <tr>
                  <th class="py-2">{gettext("Date")}</th><th>{gettext("Issues")}</th><th>
                    {gettext("Orders")}
                  </th><th>{gettext("Revenue")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={day <- @report.data["series"]}>
                  <td class="border-t py-2">{day["day"]}</td><td class="border-t">{day["issued"]}</td>
                  <td class="border-t">{day["linked_orders"]}</td><td class="border-t">
                    {day["linked_net_revenue"]}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div id="marketing-compare" class="mt-6 border-t pt-4">
            <h4 class="font-medium">{gettext("Compare policies")}</h4>
            <p class="text-xs text-base-content/60">
              {gettext("Select up to 10 policies. The current policy is included.")}
            </p>
            <div class="mt-2 flex flex-wrap gap-2">
              <button
                :for={other <- @comparison_policies}
                type="button"
                phx-click="toggle_compare"
                phx-value-id={other.id}
                class={[
                  "rounded-full border px-3 py-1 text-sm",
                  other.id in @compare_ids && "border-primary bg-primary/10"
                ]}
              >
                {other.name}
              </button>
            </div>
            <button
              :if={@comparison_after}
              id="marketing-more-comparison-policies"
              type="button"
              phx-click="more_comparison_policies"
              class="btn btn-outline mt-3"
            >{gettext("More policies")}</button>
            <button
              id="marketing-compare-run"
              type="button"
              phx-click="compare"
              class="btn btn-outline mt-3"
            >{gettext("Compare")}</button>
            <p
              :if={@comparison && @comparison.status == :pending}
              id="marketing-compare-pending"
              class="mt-3 text-sm"
            >
              {gettext("The comparison is being prepared. Refresh it later.")}
            </p>
            <div
              :if={@comparison && @comparison.status == :ready}
              id="marketing-compare-result"
              class="mt-3 space-y-3 text-sm"
            >
              <p>
                {gettext("Snapshot as of %{time}. Shared orders are counted once.",
                  time: @comparison.as_of
                )}
              </p>
              <p>
                {gettext("Linked orders: %{orders} · net revenue after refunds: %{revenue}",
                  orders: @comparison.data["linked_orders"],
                  revenue: @comparison.data["linked_net_revenue"]
                )}
              </p>
              <table class="w-full text-left">
                <thead>
                  <tr>
                    <th>{gettext("Date")}</th><th>{gettext("Orders")}</th><th>
                      {gettext("Revenue")}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={day <- @comparison.data["series"]}>
                    <td>{day["day"]}</td><td>{day["linked_orders"]}</td><td>
                      {day["linked_net_revenue"]}
                    </td>
                  </tr>
                </tbody>
              </table>
              <h5 class="font-medium">{gettext("Return branch")}</h5>
              <table class="w-full text-left">
                <thead>
                  <tr>
                    <th>{gettext("Branch")}</th><th>{gettext("Orders")}</th><th>
                      {gettext("Revenue")}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={branch <- @comparison.data["return_branches"] || []}>
                    <td>{branch_label(@branches, branch["branch_id"])}</td><td>
                      {branch["linked_orders"]}
                    </td><td>
                      {branch["linked_net_revenue"]}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
          <p class="mt-3 text-xs text-base-content/60">
            {gettext(
              "Orders in the observation window are associated with the reward; this does not prove additional sales. Delivery without provider confirmation has an unknown outcome."
            )}
          </p>
        </div>
      </section>
    </div>
    """
  end
end
