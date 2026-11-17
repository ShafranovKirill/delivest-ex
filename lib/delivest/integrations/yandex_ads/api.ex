defmodule Delivest.Integrations.YandexAds.Api do
  @moduledoc "Yandex adapters through the shared journaled HTTP client."
  alias Delivest.HTTP.Client

  @direct "https://api.direct.yandex.com/json/v501"
  @metrika "https://api-metrika.yandex.net"
  @columns ~w(Date CampaignId CampaignName Impressions Clicks Cost)
  @page_size 5000

  def counters(settings), do: metrika(settings, :get, "/management/v1/counters", [])
  def list_counters(settings), do: counters(settings)

  def counter(settings),
    do: metrika(settings, :get, "/management/v1/counter/#{settings.counter_id}", [])

  def list_goals(settings),
    do: metrika(settings, :get, "/management/v1/counter/#{settings.counter_id}/goals", [])

  def create_goal(settings, identifier \\ nil) do
    identifier = identifier || settings.goal

    name =
      "Delivest " <>
        (identifier |> String.replace_prefix("delivest_", "") |> String.replace("_", " "))

    metrika(settings, :post, "/management/v1/counter/#{settings.counter_id}/goals", %{
      goal: %{
        name: name,
        type: "action",
        conditions: [%{type: "exact", url: identifier}]
      }
    })
  end

  def campaigns(settings), do: campaigns(settings, 0, [])

  def reporting_campaigns(settings) do
    with {:ok, campaigns} <- campaigns(settings) do
      if Enum.all?(
           campaigns,
           &(&1["Currency"] == settings.currency and &1["TimeZone"] == settings.timezone)
         ), do: {:ok, campaigns}, else: {:error, :unsupported_currency_or_timezone}
    end
  end

  defp campaigns(_settings, offset, _acc) when offset >= 100_000, do: {:error, :pagination_limit}

  defp campaigns(settings, offset, acc) do
    body = %{
      method: "get",
      params: %{
        SelectionCriteria: %{},
        FieldNames: ~w(Id Name Type State Currency TimeZone),
        UnifiedCampaignFieldNames: ~w(CounterIds PriorityGoals),
        Page: %{Limit: 1000, Offset: offset}
      }
    }

    case direct(settings, "/campaigns", body) do
      {:ok, %{status: 200, body: %{"result" => result}}} ->
        rows = Map.get(result, "Campaigns", [])

        case result["LimitedBy"] do
          next when is_integer(next) and next > offset -> campaigns(settings, next, acc ++ rows)
          nil -> {:ok, acc ++ rows}
          _ -> {:error, :invalid_pagination}
        end

      {:ok, _} ->
        {:error, :invalid_campaign_response}

      error ->
        error
    end
  end

  def report(settings, from, to) do
    settings = %{
      settings
      | cost_feature_generations:
          settings.cost_feature_generations ||
            Delivest.Integrations.YandexAds.costs_token(settings)
    }

    report(settings, from, to, 0, [])
  end

  defp report(_settings, _from, _to, offset, _acc) when offset >= 100_000,
    do: {:error, :report_too_large}

  defp report(settings, from, to, offset, acc) do
    current = Delivest.Integrations.YandexAds.get_settings()

    if not Delivest.Integrations.YandexAds.same_cost_settings?(current, settings) or
         Delivest.Integrations.YandexAds.costs_token(current) != settings.cost_feature_generations or
         not Delivest.Integrations.YandexAds.costs_active?(current),
       do: {:error, :disabled},
       else: fetch_report(settings, from, to, offset, acc)
  end

  defp fetch_report(settings, from, to, offset, acc) do
    body = %{
      params: %{
        SelectionCriteria: %{DateFrom: Date.to_iso8601(from), DateTo: Date.to_iso8601(to)},
        FieldNames: @columns,
        ReportName: "delivest-#{settings.generation}-#{from}-#{to}-#{offset}",
        ReportType: "CAMPAIGN_PERFORMANCE_REPORT",
        DateRangeType: "CUSTOM_DATE",
        Format: "TSV",
        IncludeVAT: if(settings.include_vat, do: "YES", else: "NO"),
        Page: %{Limit: @page_size, Offset: offset},
        OrderBy: [%{Field: "Date"}, %{Field: "CampaignId"}]
      }
    }

    opts = [
      headers: [
        {"processingMode", "auto"},
        {"skipReportHeader", "true"},
        {"skipReportSummary", "true"}
      ],
      decode_json: false
    ]

    case direct(settings, "/reports", body, opts) do
      {:ok, %{status: status, headers: headers}} when status in [201, 202] ->
        {:retry, retry_after(headers)}

      {:ok, %{status: 200, body: tsv}} ->
        with {:ok, rows} <- parse_report(tsv, from, to) do
          if length(rows) == @page_size,
            do: report(settings, from, to, offset + @page_size, acc ++ rows),
            else: {:ok, acc ++ rows}
        end

      {:ok, _} ->
        {:error, :invalid_report_response}

      {:error, {:http_error, 429, _}} ->
        {:retry, 60}

      error ->
        error
    end
  end

  def parse_report(tsv, from, to) when is_binary(tsv) and byte_size(tsv) <= 20_000_000 do
    [header | lines] = String.split(String.trim(tsv), ~r/\r?\n/)

    if String.split(String.trim_leading(header, "\uFEFF"), "\t") == @columns do
      Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, rows} ->
        case parse_line(line, from, to) do
          {:ok, row} -> {:cont, {:ok, [row | rows]}}
          _ -> {:halt, {:error, :invalid_report_row}}
        end
      end)
      |> case do
        {:ok, rows} ->
          rows = Enum.reverse(rows)

          if Enum.uniq_by(rows, &{&1.day, &1.campaign_id}) == rows,
            do: {:ok, rows},
            else: {:error, :duplicate_report_row}

        error ->
          error
      end
    else
      {:error, :invalid_report_header}
    end
  end

  def parse_report(_, _, _), do: {:error, :invalid_report}

  defp parse_line(line, from, to) do
    with [date, campaign, name, impressions, clicks, cost] <- String.split(line, "\t"),
         {:ok, day} <- Date.from_iso8601(date),
         true <- Date.compare(day, from) != :lt and Date.compare(day, to) != :gt,
         true <- Regex.match?(~r/^[0-9]{1,30}$/, campaign),
         true <- byte_size(name) <= 1000,
         {impressions, ""} when impressions >= 0 <- Integer.parse(impressions),
         {clicks, ""} when clicks >= 0 <- Integer.parse(clicks),
         {cost, ""} when cost >= 0 <- Integer.parse(cost) do
      {:ok,
       %{
         day: day,
         campaign_id: campaign,
         campaign_name: name,
         impressions: impressions,
         clicks: clicks,
         cost_micros: cost
       }}
    else
      _ -> {:error, :invalid_report_row}
    end
  end

  def upload(settings, csv) do
    metrika(
      settings,
      :post,
      "/management/v1/counter/#{settings.counter_id}/offline_conversions/upload",
      [{"file", {csv, filename: "delivest-conversion.csv", content_type: "text/csv"}}],
      format: :multipart
    )
  end

  def upload_status(settings, upload_id) do
    if Regex.match?(~r/^[0-9]{1,30}$/, upload_id),
      do:
        metrika(
          settings,
          :get,
          "/management/v1/counter/#{settings.counter_id}/offline_conversions/uploading/#{upload_id}",
          []
        ),
      else: {:error, :invalid_upload_id}
  end

  def purchase(settings, params) do
    if present?(settings.measurement_token) do
      Client.post(
        "https://mc.yandex.ru/collect",
        Map.merge(params, %{tid: settings.counter_id, ms: settings.measurement_token}),
        journal: :yandex_ads,
        format: :form,
        response: :full,
        retry: false
      )
    else
      {:error, :not_configured}
    end
  end

  def register_feed(settings, name, url, branch_id \\ nil) do
    with %URI{scheme: "https", host: host} when is_binary(host) <- URI.parse(url),
         true <- byte_size(url) <= 1024 and byte_size(name) <= 255,
         {:ok, %{status: 200, body: %{"result" => %{"Feeds" => feeds}}}} <-
           direct(settings, "/feeds", %{
             method: "get",
             params: %{
               FieldNames: ~w(Id Name Status SourceType),
               UrlFeedFieldNames: ["Url"],
               Page: %{Limit: 100, Offset: 0}
             }
           }) do
      case Enum.find(feeds, &(get_in(&1, ["UrlFeed", "Url"]) == url)) do
        %{"Status" => "ERROR"} -> {:error, :feed_provider_error}
        %{"Id" => id} = feed -> {:ok, %{id: id, status: feed["Status"]}}
        nil -> add_feed(settings, name, url, branch_id)
      end
    else
      _ -> {:error, :feed_unavailable}
    end
  end

  defp add_feed(settings, name, url, branch_id) do
    current = Delivest.Integrations.YandexAds.get_settings()

    if current.generation == settings.generation and
         (is_nil(branch_id) or Delivest.Integrations.YandexAds.enabled?(current, :feed, branch_id)) do
      case direct(settings, "/feeds", %{
             method: "add",
             params: %{
               Feeds: [
                 %{Name: name, BusinessType: "RETAIL", SourceType: "URL", UrlFeed: %{Url: url}}
               ]
             }
           }) do
        {:ok, %{status: 200, body: %{"result" => %{"AddResults" => [%{"Id" => id} = result]}}}}
        when is_integer(id) ->
          if Map.get(result, "Errors", []) == [],
            do: {:ok, %{id: id, status: "NEW"}},
            else: {:error, :feed_rejected}

        _ ->
          {:error, :feed_rejected}
      end
    else
      {:error, :disabled}
    end
  end

  def direct(settings, path, body, opts \\ []) do
    if present?(settings.direct_token) do
      headers = [{"authorization", "Bearer " <> settings.direct_token}, {"Accept-Language", "ru"}]

      headers =
        if present?(settings.client_login),
          do: [{"Client-Login", settings.client_login} | headers],
          else: headers

      headers = headers ++ Keyword.get(opts, :headers, [])

      options =
        opts
        |> Keyword.put(:headers, headers)
        |> Keyword.merge(journal: :yandex_ads, response: :full, retry: false)

      Client.post(@direct <> path, body, options)
    else
      {:error, :not_configured}
    end
  end

  def metrika(settings, method, path, body, opts \\ []) do
    if present?(settings.metrika_token) and
         (path == "/management/v1/counters" or valid_counter?(settings.counter_id)) do
      options =
        Keyword.merge(opts,
          headers: [{"authorization", "OAuth " <> settings.metrika_token}],
          journal: :yandex_ads,
          response: :full,
          retry: false
        )

      Client.request(method, @metrika <> path, body, options)
    else
      {:error, :not_configured}
    end
  end

  def retry_after(headers) do
    value =
      headers
      |> Enum.find_value(fn {key, values} ->
        if String.downcase(to_string(key)) in ["retryin", "retry-after"],
          do: List.first(List.wrap(values))
      end)

    case Integer.parse(to_string(value || "60")) do
      {seconds, ""} -> min(max(seconds, 1), 3600)
      _ -> 60
    end
  end

  defp valid_counter?(id), do: is_binary(id) and Regex.match?(~r/^[1-9][0-9]{0,19}$/, id)
  defp present?(value), do: is_binary(value) and value != ""
end
