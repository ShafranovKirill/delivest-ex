defmodule Delivest.Logs.Formatter do
  @max_message 8_000
  @metadata_keys [:request_id, :crash_reason, :error_code, :worker, :job_id]

  def to_entry(%{level: level, msg: msg, meta: meta}) do
    %{
      level: to_string(level),
      message: msg |> message(meta) |> String.slice(0, @max_message),
      source: source(meta),
      metadata: metadata(meta),
      inserted_at: timestamp(meta)
    }
  end

  defp message({:string, chardata}, _meta), do: IO.chardata_to_string(chardata)

  defp message({:report, report}, %{report_cb: callback}) when is_function(callback, 1) do
    {format, args} = callback.(report)
    format(format, args)
  end

  defp message({:report, report}, %{report_cb: callback}) when is_function(callback, 2),
    do: IO.chardata_to_string(callback.(report, %{}))

  defp message({:report, report}, _meta), do: inspect(report)
  defp message({format, args}, _meta), do: format(format, args)

  defp format(format, args), do: format |> :io_lib.format(args) |> IO.chardata_to_string()

  defp source(%{mfa: {module, function, arity}} = meta),
    do: "#{inspect(module)}.#{function}/#{arity}#{line(meta)}"

  defp source(_meta), do: nil

  defp line(%{line: line}), do: ":#{line}"
  defp line(_meta), do: ""

  defp metadata(meta) do
    meta
    |> Map.take(@metadata_keys)
    |> Map.new(fn {key, value} -> {key, if(is_binary(value), do: value, else: inspect(value))} end)
  end

  defp timestamp(%{time: time}), do: DateTime.from_unix!(time, :microsecond)
  defp timestamp(_meta), do: DateTime.utc_now()
end
