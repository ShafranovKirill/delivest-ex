defmodule Mix.Tasks.Delivest.Events do
  use Mix.Task

  @shortdoc "List and recover event deliveries"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          event: :string,
          subscriber: :string,
          actor: :string,
          reason: :string,
          limit: :integer
        ]
      )

    if invalid != [], do: Mix.raise("Invalid options: #{inspect(invalid)}")

    case rest do
      ["list"] ->
        Delivest.Events.Recovery.list(Keyword.get(opts, :limit, 100))
        |> Enum.each(&Mix.shell().info(inspect(&1)))

      [action] when action in ["retry", "resolve"] ->
        result =
          apply(Delivest.Events.Recovery, String.to_existing_atom(action), [
            opts[:event],
            opts[:subscriber],
            opts[:actor],
            opts[:reason]
          ])

        case result do
          {:ok, :ok} -> Mix.shell().info("#{action} recorded")
          {:error, reason} -> Mix.raise("#{action} refused: #{inspect(reason)}")
        end

      _ ->
        Mix.raise(
          "Usage: mix delivest.events list [--limit N] | retry|resolve --event UUID --subscriber KEY --actor STAFF_UUID --reason TEXT"
        )
    end
  end
end
