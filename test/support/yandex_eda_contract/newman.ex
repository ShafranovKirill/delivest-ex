defmodule Delivest.YandexEdaContract.Newman do
  @package "newman@6.2.1"

  def run(collection, dir) do
    collection_path = Path.join(dir, "collection.json")
    report_path = Path.join(dir, "report.json")
    File.write!(collection_path, Jason.encode!(collection))

    {output, _status} =
      System.cmd(
        "npx",
        [
          "--yes",
          @package,
          "run",
          collection_path,
          "--reporters",
          "cli,json",
          "--reporter-json-export",
          report_path,
          "--color",
          "off"
        ],
        stderr_to_stdout: true
      )

    case File.read(report_path) do
      {:ok, report} -> {:ok, report |> Jason.decode!() |> failures(), output}
      {:error, _reason} -> {:error, output}
    end
  end

  defp failures(%{"run" => %{"failures" => failures}}), do: Enum.map(failures, &describe/1)

  defp describe(%{"source" => source, "error" => error}),
    do: "#{source["name"]}: #{error["test"] || error["name"]} — #{error["message"]}"
end
