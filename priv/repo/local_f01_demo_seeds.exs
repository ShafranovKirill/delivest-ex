defmodule LocalF01DemoSeeds do
  @moduledoc false
  import Ecto.Query

  alias Delivest.{Background, Features, Marketing, Relations, Repo, Segments}
  alias Delivest.Background.Schedule
  alias Delivest.Identity.{Branch, Client, RolePresets, Staff, StaffBranch}
  alias Delivest.Identity.Branch.BranchInfo
  alias Delivest.Integrations.Zvonok
  alias Delivest.Net.{Category, Product}
  alias Delivest.Oms.{Cart, Order, OrderItem, OrderTransition}
  alias Delivest.Payments.{Payment, Refund}
  alias Delivest.Marketing.{Policy, Report}
  alias Delivest.Promo.Promotion

  @marker "demo-center"
  @order_count 1_800

  def run do
    assert_database!()

    case Repo.get_by(Branch, slug: @marker) do
      nil ->
        if Repo.aggregate(Order, :count) != 0 or Repo.aggregate(Branch, :count) != 0 do
          raise "Demo database is not empty; refusing to mix demo with existing data"
        end

        {:ok, {branches, clients, staff}} =
          Repo.transaction(fn -> seed_base!() end, timeout: :infinity)

        seed_features!(branches)
        seed_segments_and_policies!(branches, clients, staff)

      _branch ->
        unless Repo.aggregate(Order, :count) >= @order_count and
                 Repo.aggregate(
                   from(c in Client,
                     where: c.phone >= "+79990000001" and c.phone <= "+79990000185"
                   ),
                   :count
                 ) == 185 and
                 Repo.aggregate(Policy, :count) >= 4 do
          raise "Incomplete demo base found; create a fresh dedicated demo database to retry"
        end
    end

    unless System.get_env("LOCAL_DEMO_PREPARE") == "1" or
             System.get_env("DEV_DATABASE") == "delivest_f01_demo_local" do
      finish_demo!()
    end

    IO.puts(
      "Demo ready: #{Repo.aggregate(Branch, :count)} branches, " <>
        "#{Repo.aggregate(Client, :count)} clients, #{Repo.aggregate(Order, :count)} orders, " <>
        "#{Repo.aggregate(Segments.Segment, :count)} segments, " <>
        "#{Repo.aggregate(Policy, :count)} policies"
    )
  end

  defp assert_database! do
    database = Application.fetch_env!(:delivest, Repo)[:database]
    host = Application.fetch_env!(:delivest, Repo)[:hostname]

    unless is_binary(database) and String.starts_with?(database, "delivest_f01_demo_") and
             host in ["localhost", "127.0.0.1"] do
      raise "Demo seed requires a dedicated loopback database"
    end
  end

  defp seed_base! do
    RolePresets.seed()

    {:ok, _} =
      %Zvonok.Settings{}
      |> Zvonok.Settings.changeset(%{
        public_key: "local-demo-disabled",
        campaign_id: "local-demo-disabled",
        webhook_token: "local-demo-disabled",
        enabled: true,
        dev_skip_calls: true
      })
      |> Repo.insert()

    hours =
      Map.new(~w(monday tuesday wednesday thursday friday saturday sunday), fn day ->
        {day, %{"open" => "00:00", "close" => "23:59", "enabled" => true}}
      end)

    branches =
      for {name, slug, code, address} <- [
            {"Центр", "demo-center", "DCTR", "Москва, Тверская улица, 7"},
            {"Север", "demo-north", "DNTH", "Москва, Ленинградский проспект, 35"},
            {"Юг", "demo-south", "DSTH", "Москва, Варшавское шоссе, 87"}
          ] do
        branch =
          %Branch{}
          |> Branch.changeset(%{name: name, slug: slug, code: code, is_active: true})
          |> Repo.insert!()

        %BranchInfo{}
        |> BranchInfo.changeset(%{
          branch_id: branch.id,
          address: address,
          city: "Москва",
          phone_number: "+74950000000",
          delivery_time: 40,
          working_hours: hours,
          fiscal: %{mode: :off},
          payments: %{cash: true, card_offline: true, online: false},
          loyalty: %{enabled: true, shop_enabled: true, spend_enabled: true}
        })
        |> Repo.insert!()

        branch
      end

    role = RolePresets.admin_role()
    password_hash = Argon2.hash_pwd_salt("DemoPassword123!")

    staff =
      %Staff{}
      |> Ecto.Changeset.change(%{
        login: "demo_admin",
        name: "Администратор демо",
        password_hash: password_hash,
        role_id: role.id
      })
      |> Repo.insert!()

    for branch <- branches do
      Repo.insert!(%StaffBranch{staff_id: staff.id, branch_id: branch.id})
    end

    staff = Repo.preload(staff, [:role, :branches])

    menu = [
      {"Пицца", [{"Маргарита", 59_000}, {"Пепперони", 69_000}, {"Четыре сыра", 79_000}]},
      {"Салаты", [{"Цезарь", 45_000}, {"Греческий", 39_000}]},
      {"Напитки", [{"Лимонад", 18_000}, {"Морс", 16_000}, {"Капучино", 22_000}]},
      {"Десерты", [{"Чизкейк", 31_000}, {"Тирамису", 34_000}]}
    ]

    products =
      for {{category_name, items}, category_index} <- Enum.with_index(menu),
          reduce: [] do
        acc ->
          category =
            %Category{}
            |> Category.changeset(%{
              name: category_name,
              order: category_index * 1.0,
              is_active: true
            })
            |> Repo.insert!()

          for branch <- branches do
            {:ok, _} =
              Relations.create_relation(Repo, "Branch", branch.id, "Category", category.id, %{})
          end

          new_products =
            for {{name, price}, item_index} <- Enum.with_index(items) do
              product =
                %Product{}
                |> Product.changeset(%{
                  name: name,
                  price: price,
                  weight: if(category_name == "Напитки", do: 300, else: 400),
                  category_id: category.id,
                  slug: "demo-#{category_index}-#{item_index}",
                  is_active: true,
                  order: item_index * 1.0
                })
                |> Repo.insert!()

              for branch <- branches do
                {:ok, _} =
                  Relations.create_relation(Repo, "Branch", branch.id, "Product", product.id, %{})
              end

              {product, category}
            end

          acc ++ new_products
      end

    first_names =
      ~w(Анна Мария Елена Ольга Ирина Наталья София Дарья Юлия Полина Иван Дмитрий Алексей Сергей Михаил Павел Артём Максим Андрей Кирилл)

    last_names =
      ~w(Иванова Смирнова Кузнецова Попова Соколова Волкова Морозова Новикова Петрова Фёдорова Иванов Смирнов Кузнецов Попов Соколов Волков Морозов Новиков Петров Фёдоров)

    clients =
      for index <- 1..185 do
        phone = "+7999" <> String.pad_leading(Integer.to_string(index), 7, "0")

        %Client{}
        |> Client.changeset(%{
          phone: phone,
          name:
            "#{Enum.at(first_names, rem(index - 1, 20))} #{Enum.at(last_names, rem(index - 1, 20))}",
          status: :active
        })
        |> Repo.insert!()
      end

    seed_orders!(branches, clients, products, staff)
    {branches, clients, staff}
  end

  defp seed_orders!(branches, clients, products, staff) do
    now = DateTime.utc_now(:second)

    1..@order_count
    |> Enum.chunk_every(200)
    |> Enum.each(fn indices ->
      rows =
        for index <- indices do
          client_index = rem(index - 1, 180)
          client = Enum.at(clients, client_index)
          branch = Enum.at(branches, rem(index + client_index, 3))
          {product, category} = Enum.at(products, rem(index * 7, length(products)))
          quantity = 1 + rem(index, 3)
          amount = product.price * quantity

          age =
            cond do
              rem(index, 181) == 0 -> 0
              client_index < 40 -> 35 + rem(index * 11, 55)
              true -> rem(index * 17, 89)
            end

          at = DateTime.add(now, -age * 86_400 - rem(index * 137, 70_000), :second)

          status =
            cond do
              rem(index, 181) == 0 -> :ready
              rem(index, 31) == 0 -> :cancelled
              true -> :completed
            end

          id = Ecto.UUID.generate()
          cart_id = Ecto.UUID.generate()
          payment_id = Ecto.UUID.generate()

          cart = %{
            id: cart_id,
            branch_id: branch.id,
            client_id: client.id,
            session_id: "demo-history-#{index}",
            expires_at: DateTime.add(at, 86_400, :second),
            inserted_at: at,
            updated_at: at
          }

          order = %{
            id: id,
            cart_id: cart_id,
            number: "DEMO-#{String.pad_leading(Integer.to_string(index), 6, "0")}",
            daily_number: index,
            business_date: DateTime.to_date(at),
            branch_id: branch.id,
            client_id: client.id,
            customer_phone: client.phone,
            customer_name: client.name,
            persons: 1 + rem(index, 4),
            status: status,
            fulfillment_type: if(rem(index, 4) == 0, do: :pickup, else: :dine_in),
            payment_method: :cash,
            source: "demo",
            total_amount: amount,
            subtotal_amount: amount,
            discount_amount: 0,
            points_spent: 0,
            delivery_amount: 0,
            inserted_at: at,
            updated_at: at
          }

          item = %{
            id: Ecto.UUID.generate(),
            order_id: id,
            product_id: product.id,
            title: product.name,
            price: product.price,
            base_price: product.price,
            quantity: quantity,
            category_id: category.id,
            category_name: category.name,
            inserted_at: at,
            updated_at: at
          }

          transition = %{
            order_id: id,
            from: :created,
            to: status,
            source: :staff,
            staff_id: staff.id,
            reason: "Локальная демонстрация",
            inserted_at: DateTime.from_unix!(DateTime.to_unix(at, :microsecond), :microsecond)
          }

          payment = %{
            id: payment_id,
            order_id: id,
            branch_id: branch.id,
            method: :cash,
            amount: amount,
            status:
              case status do
                :completed -> :paid
                :cancelled -> :cancelled
                _ -> :pending
              end,
            collected_by_id: staff.id,
            paid_at: if(status == :completed, do: at),
            fiscalized_by: :none,
            inserted_at: at,
            updated_at: at
          }

          refund =
            if status == :completed and rem(index, 113) == 0 do
              %{
                id: Ecto.UUID.generate(),
                payment_id: payment_id,
                order_id: id,
                amount: div(amount, 2),
                reason: "Частичный возврат наличных в демо",
                status: :succeeded,
                refunded_by_id: staff.id,
                refunded_at: DateTime.add(at, 3_600, :second),
                inserted_at: at,
                updated_at: at
              }
            end

          {cart, order, item, transition, payment, refund}
        end

      {:ok, _} =
        Repo.transaction(fn ->
          {carts, orders, items, transitions, payments, refunds} =
            Enum.reduce(rows, {[], [], [], [], [], []}, fn {c, o, i, t, p, r},
                                                           {cs, os, is, ts, ps, rs} ->
              {[c | cs], [o | os], [i | is], [t | ts], [p | ps], if(r, do: [r | rs], else: rs)}
            end)

          Repo.insert_all(Cart, carts)
          Repo.insert_all(Order, orders)
          Repo.insert_all(OrderItem, items)
          Repo.insert_all(OrderTransition, transitions)
          Repo.insert_all(Payment, payments)
          if refunds != [], do: Repo.insert_all(Refund, refunds)
        end)
    end)
  end

  defp seed_features!(branches) do
    {:ok, _} = Features.configure("marketing_policies", :franchise, true, actor: "local-f01-demo")

    for branch <- branches do
      {:ok, _} =
        Features.configure("marketing_policies", {:branch, branch.id}, true,
          actor: "local-f01-demo"
        )
    end
  end

  defp seed_segments_and_policies!(branches, clients, staff) do
    [center | _] = branches

    {:ok, dormant} =
      Segments.create(
        staff,
        %{name: "Давно не заказывали", kind: :manual, scope: :franchise},
        [],
        Enum.take(clients, 40) |> Enum.map(& &1.id)
      )

    {:ok, vip} =
      Segments.create(
        staff,
        %{name: "Постоянные гости", kind: :manual, scope: :franchise},
        [],
        Enum.slice(clients, 40, 60) |> Enum.map(& &1.id)
      )

    {:ok, _} =
      Segments.create(
        staff,
        %{name: "Новые гости", kind: :manual, scope: :franchise},
        [],
        Enum.slice(clients, 180, 5) |> Enum.map(& &1.id)
      )

    for {name, metric, op, value} <- [
          {"Неактивные 30+ дней", "days_since_last_order", "gte", 30},
          {"10+ заказов", "order_count", "gte", 10},
          {"Высокий средний чек", "avg_check", "gte", 100_000}
        ] do
      {:ok, _} =
        Segments.create(staff, %{
          name: name,
          kind: :dynamic,
          scope: :franchise,
          rules: %{
            "version" => 1,
            "match" => "all",
            "conditions" => [%{"metric" => metric, "op" => op, "value" => value}]
          }
        })
    end

    promotion =
      %Promotion{branch_id: center.id}
      |> Promotion.changeset(%{
        name: "Вернитесь за пиццей — скидка 10%",
        description: "Персональный код для локального демо",
        kind: :personal_code,
        rules: "then discount 10%",
        enabled: true
      })
      |> Repo.insert!()

    policy_attrs = fn name, segment, extras ->
      Map.merge(
        %{
          "name" => name,
          "scope" => "franchise",
          "segment_id" => segment.id,
          "reward_branch_id" => center.id,
          "inactivity_days" => 30,
          "reward_ttl_days" => 14,
          "attribution_days" => 7,
          "initial_mode" => "all_current",
          "channels" => ["in_app"],
          "message_title" => "Рады видеть вас снова!",
          "message_body" => "Ваше персональное предложение уже ждёт вас в приложении."
        },
        extras
      )
    end

    {:ok, promo} =
      Marketing.create(
        staff,
        policy_attrs.("Возвращение — 10%", dormant, %{"promotion_id" => promotion.id}),
        []
      )

    {:ok, bonus} =
      Marketing.create(
        staff,
        policy_attrs.("Возвращение — 500 бонусов", dormant, %{"bonus_amount" => 500}),
        []
      )

    {:ok, _} =
      Marketing.create(
        staff,
        policy_attrs.("Постоянным гостям — черновик", vip, %{"bonus_amount" => 300}),
        []
      )

    {:ok, _} =
      Marketing.create(
        staff,
        policy_attrs.("Новый цикл — черновик", dormant, %{
          "bonus_amount" => 200,
          "initial_mode" => "future_only"
        }),
        []
      )

    _ = {promo, bonus}
  end

  defp finish_demo! do
    branches = Repo.all(from b in Branch, where: b.slug in ~w(demo-center demo-north demo-south))

    clients =
      Repo.all(
        from c in Client,
          where: c.phone >= "+79990000001" and c.phone <= "+79990000185",
          order_by: c.phone
      )

    staff = Repo.get_by!(Staff, login: "demo_admin") |> Repo.preload([:role, :branches])

    policies =
      Repo.all(
        from p in Policy,
          where: p.name in ["Возвращение — 10%", "Возвращение — 500 бонусов"]
      )

    for policy <- policies, policy.status == :draft do
      {:ok, _} = Marketing.preview(staff, policy.id)
    end

    wait_for_previews!(policies, staff, 30)

    for policy <- policies, policy.status == :draft do
      {:ok, _active} = Marketing.activate(staff, policy.id, policy.revision)
    end

    wait_for_issues!(20, 60)
    Process.sleep(1_100)
    seed_return_orders!(branches, clients, staff)

    for policy <- policies, filters <- report_filters() do
      {:ok, _} = Report.request(Repo.get!(Policy, policy.id), filters)
    end

    Background.kick()
    wait_for_reports!(policies, 60)
  end

  defp wait_for_previews!(_policies, _staff, 0), do: raise("Demo policy previews timed out")

  defp wait_for_previews!(policies, staff, remaining) do
    if Enum.all?(policies, fn policy ->
         policy.status != :draft or
           match?({:ok, %{status: :ready}}, Marketing.preview(staff, policy.id))
       end) do
      :ok
    else
      drive_background!("marketing.preview")
      Process.sleep(1_000)
      wait_for_previews!(policies, staff, remaining - 1)
    end
  end

  defp wait_for_issues!(_minimum, 0), do: raise("Demo marketing evaluation timed out")

  defp wait_for_issues!(minimum, remaining) do
    if Repo.aggregate(Delivest.Marketing.Issue, :count) >= minimum do
      :ok
    else
      drive_background!("marketing.evaluate")
      Process.sleep(1_000)
      wait_for_issues!(minimum, remaining - 1)
    end
  end

  defp wait_for_reports!(_policies, 0), do: raise("Demo reports timed out")

  defp wait_for_reports!(policies, remaining) do
    if Enum.all?(policies, fn policy ->
         Enum.all?(report_filters(), fn filters ->
           match?({:ok, %{status: :ready}}, Report.request(policy, filters))
         end)
       end) do
      :ok
    else
      drive_background!("marketing.report")
      Process.sleep(1_000)
      wait_for_reports!(policies, remaining - 1)
    end
  end

  defp report_filters do
    today = Date.utc_today()
    [%{}, %{from: Date.add(today, -29), to: today, branch_id: ""}]
  end

  defp drive_background!(kind) do
    schedule = Repo.get_by!(Schedule, kind: kind, scope_key: "franchise")

    if schedule.running do
      job = schedule.current_job_id && Repo.get(Oban.Job, schedule.current_job_id)

      if job && job.state == "scheduled" do
        :ok = Oban.pause_queue(queue: :background)

        try do
          Process.sleep(100)

          Oban.drain_queue(
            queue: :background,
            with_scheduled: true,
            with_recursion: true,
            with_limit: 10,
            with_safety: false
          )
        after
          Oban.resume_queue(queue: :background)
        end
      end
    else
      Background.invalidate(kind, :franchise)
    end

    Background.dispatch_due()
    Background.kick()
  end

  defp seed_return_orders!(branches, clients, staff) do
    # New completed orders are inserted only after genuine F01 issues exist, so
    # observational attribution and currentness use the same facts as the app.
    now = DateTime.utc_now(:second)

    for index <- 2..20 do
      number = "DEMO-RETURN-#{index}"

      unless Repo.exists?(from o in Order, where: o.number == ^number) do
        client = Enum.at(clients, index - 1)
        branch = Enum.at(branches, rem(index, length(branches)))
        id = Ecto.UUID.generate()
        cart_id = Ecto.UUID.generate()
        payment_id = Ecto.UUID.generate()
        amount = 75_000 + index * 1_000

        {:ok, _} =
          Repo.transaction(fn ->
            Repo.insert_all(Cart, [
              %{
                id: cart_id,
                branch_id: branch.id,
                client_id: client.id,
                session_id: "demo-return-#{index}",
                expires_at: DateTime.add(now, 86_400, :second),
                inserted_at: now,
                updated_at: now
              }
            ])

            Repo.insert_all(Order, [
              %{
                id: id,
                cart_id: cart_id,
                number: number,
                daily_number: 2_000 + index,
                business_date: DateTime.to_date(now),
                branch_id: branch.id,
                client_id: client.id,
                customer_phone: client.phone,
                customer_name: client.name,
                persons: 2,
                status: :completed,
                fulfillment_type: :pickup,
                payment_method: :cash,
                source: "demo",
                total_amount: amount,
                subtotal_amount: amount,
                discount_amount: 0,
                points_spent: 0,
                delivery_amount: 0,
                inserted_at: now,
                updated_at: now
              }
            ])

            Repo.insert_all(OrderTransition, [
              %{
                order_id: id,
                from: :created,
                to: :completed,
                source: :staff,
                staff_id: staff.id,
                inserted_at:
                  DateTime.from_unix!(DateTime.to_unix(now, :microsecond), :microsecond)
              }
            ])

            Repo.insert_all(Payment, [
              %{
                id: payment_id,
                order_id: id,
                branch_id: branch.id,
                method: :cash,
                amount: amount,
                status: :paid,
                collected_by_id: staff.id,
                paid_at: now,
                fiscalized_by: :none,
                inserted_at: now,
                updated_at: now
              }
            ])
          end)
      end
    end
  end
end

LocalF01DemoSeeds.run()
